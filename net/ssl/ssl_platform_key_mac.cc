// Copyright 2015 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "net/ssl/ssl_platform_key_mac.h"

#include <CoreFoundation/CoreFoundation.h>
#include <Security/SecBase.h>
#include <Security/SecCertificate.h>
#include <Security/SecIdentity.h>
#include <Security/SecKey.h>
#include <Security/cssm.h>

#include <algorithm>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/apple/osstatus_logging.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/compiler_specific.h"
#include "base/containers/span.h"
#include "base/logging.h"
#include "base/mac/mac_util.h"
#include "base/memory/raw_ptr_exclusion.h"
#include "base/memory/scoped_policy.h"
#include "base/numerics/safe_conversions.h"
#include "crypto/evp.h"
#include "crypto/openssl_util.h"
#include "net/base/net_errors.h"
#include "net/cert/x509_certificate.h"
#include "net/cert/x509_util_apple.h"
#include "net/ssl/ssl_platform_key_util.h"
#include "net/ssl/ssl_private_key.h"
#include "net/ssl/threaded_ssl_private_key.h"
#include "third_party/boringssl/src/include/openssl/evp.h"
#include "third_party/boringssl/src/include/openssl/mem.h"
#include "third_party/boringssl/src/include/openssl/nid.h"
#include "third_party/boringssl/src/include/openssl/rsa.h"
#include "third_party/boringssl/src/include/openssl/ssl.h"

namespace net {

namespace {

#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101200
// CSSM is the supported signing interface on these systems. Keep the targeted
// deprecation exception local to that implementation, retaining PSS and RSA
// blinding without exporting private key material.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
class ScopedCSSM_CC_HANDLE {
 public:
  ScopedCSSM_CC_HANDLE() : handle_(0) {}
  explicit ScopedCSSM_CC_HANDLE(CSSM_CC_HANDLE handle) : handle_(handle) {}

  ScopedCSSM_CC_HANDLE(const ScopedCSSM_CC_HANDLE&) = delete;
  ScopedCSSM_CC_HANDLE& operator=(const ScopedCSSM_CC_HANDLE&) = delete;

  ~ScopedCSSM_CC_HANDLE() { reset(); }

  CSSM_CC_HANDLE get() const { return handle_; }

  void reset() {
    if (handle_) {
      CSSM_DeleteContext(handle_);
    }
    handle_ = 0;
  }

 private:
  CSSM_CC_HANDLE handle_;
};

class SSLPlatformKeyCSSM : public ThreadedSSLPrivateKey::Delegate {
 public:
  SSLPlatformKeyCSSM(bssl::UniquePtr<EVP_PKEY> pubkey,
                     SecKeyRef key,
                     const CSSM_KEY* cssm_key)
      : pubkey_(std::move(pubkey)),
        key_(key, base::scoped_policy::RETAIN),
        cssm_key_(cssm_key) {}

  SSLPlatformKeyCSSM(const SSLPlatformKeyCSSM&) = delete;
  SSLPlatformKeyCSSM& operator=(const SSLPlatformKeyCSSM&) = delete;

  ~SSLPlatformKeyCSSM() override {}

  std::string GetProviderName() override {
    // TODO(https://crbug.com/900721): Is there a more descriptive name to
    // return?
    return "CSSM";
  }

  std::vector<uint16_t> GetAlgorithmPreferences() override {
    return SSLPrivateKey::DefaultAlgorithmPreferences(
        EVP_PKEY_id(pubkey_.get()), true /* include PSS */);
  }

  Error Sign(uint16_t algorithm,
             base::span<const uint8_t> input,
             std::vector<uint8_t>* signature) override {
    if (!std::ranges::contains(GetAlgorithmPreferences(), algorithm)) {
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }
    crypto::OpenSSLErrStackTracer tracer(FROM_HERE);

    CSSM_CSP_HANDLE csp_handle;
    OSStatus status = SecKeyGetCSPHandle(key_.get(), &csp_handle);
    if (status != noErr) {
      OSSTATUS_LOG(WARNING, status);
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }

    const CSSM_ACCESS_CREDENTIALS* cssm_creds = nullptr;
    status = SecKeyGetCredentials(key_.get(), CSSM_ACL_AUTHORIZATION_SIGN,
                                  kSecCredentialTypeDefault, &cssm_creds);
    if (status != noErr) {
      OSSTATUS_LOG(WARNING, status);
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }

    CSSM_CC_HANDLE cssm_signature_raw = 0;
    if (CSSM_CSP_CreateSignatureContext(
            csp_handle, cssm_key_->KeyHeader.AlgorithmId, cssm_creds, cssm_key_,
            &cssm_signature_raw) != CSSM_OK) {
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }
    ScopedCSSM_CC_HANDLE cssm_signature(cssm_signature_raw);

    // Hash the input.
    const EVP_MD* md = SSL_get_signature_algorithm_digest(algorithm);
    uint8_t digest[EVP_MAX_MD_SIZE];
    unsigned digest_len;
    if (!md || !EVP_Digest(input.data(), input.size(), digest, &digest_len, md,
                           nullptr)) {
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }
    CSSM_DATA hash_data;
    hash_data.Length = digest_len;
    hash_data.Data = digest;

    std::optional<std::vector<uint8_t>> pss_storage;
    bssl::UniquePtr<uint8_t> free_digest_info;
    if (cssm_key_->KeyHeader.AlgorithmId == CSSM_ALGID_RSA) {
      if (SSL_is_signature_algorithm_rsa_pss(algorithm)) {
        pss_storage = AddPSSPadding(pubkey_.get(), md,
                                    base::span(digest).first(digest_len));
        if (!pss_storage) {
          return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
        }
        hash_data.Length = pss_storage->size();
        hash_data.Data = pss_storage->data();

        CSSM_CONTEXT_ATTRIBUTE padding_attr;
        padding_attr.AttributeType = CSSM_ATTRIBUTE_PADDING;
        padding_attr.AttributeLength = sizeof(uint32_t);
        padding_attr.Attribute.Uint32 = CSSM_PADDING_NONE;
        if (CSSM_UpdateContextAttributes(cssm_signature.get(), 1,
                                         &padding_attr) != CSSM_OK) {
          return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
        }
      } else {
        // CSSM expects the caller to prepend the DigestInfo.
        int hash_nid = EVP_MD_type(md);
        int is_alloced;
        if (!RSA_add_pkcs1_prefix(&hash_data.Data, &hash_data.Length,
                                  &is_alloced, hash_nid, hash_data.Data,
                                  hash_data.Length)) {
          return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
        }
        if (is_alloced) {
          free_digest_info.reset(hash_data.Data);
        }
      }

      // Set RSA blinding.
      CSSM_CONTEXT_ATTRIBUTE blinding_attr;
      blinding_attr.AttributeType = CSSM_ATTRIBUTE_RSA_BLINDING;
      blinding_attr.AttributeLength = sizeof(uint32_t);
      blinding_attr.Attribute.Uint32 = 1;
      if (CSSM_UpdateContextAttributes(cssm_signature.get(), 1,
                                       &blinding_attr) != CSSM_OK) {
        return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
      }
    }

    signature->resize(EVP_PKEY_size(pubkey_.get()));
    CSSM_DATA signature_data;
    signature_data.Length = signature->size();
    signature_data.Data = signature->data();

    if (CSSM_SignData(cssm_signature.get(), &hash_data, 1, CSSM_ALGID_NONE,
                      &signature_data) != CSSM_OK) {
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }
    if (signature_data.Length > signature->size()) {
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }
    signature->resize(signature_data.Length);
    return OK;
  }

 private:
  bssl::UniquePtr<EVP_PKEY> pubkey_;
  base::apple::ScopedCFTypeRef<SecKeyRef> key_;
  // Opaque CSP-owned storage retained by key_. The deprecated external type
  // cannot be instantiated in raw_ptr's modern SDK type traits.
  RAW_PTR_EXCLUSION const CSSM_KEY* cssm_key_;
};

#pragma clang diagnostic pop
#endif

// Returns the corresponding SecKeyAlgorithm or nullptr if unrecognized.
API_AVAILABLE(macos(10.12))
SecKeyAlgorithm GetSecKeyAlgorithm(uint16_t algorithm) {
  switch (algorithm) {
    case SSL_SIGN_RSA_PKCS1_SHA512:
      return kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA512;
    case SSL_SIGN_RSA_PKCS1_SHA384:
      return kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA384;
    case SSL_SIGN_RSA_PKCS1_SHA256:
      return kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256;
    case SSL_SIGN_RSA_PKCS1_SHA1:
      return kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA1;
    case SSL_SIGN_ECDSA_SECP521R1_SHA512:
      return kSecKeyAlgorithmECDSASignatureDigestX962SHA512;
    case SSL_SIGN_ECDSA_SECP384R1_SHA384:
      return kSecKeyAlgorithmECDSASignatureDigestX962SHA384;
    case SSL_SIGN_ECDSA_SECP256R1_SHA256:
      return kSecKeyAlgorithmECDSASignatureDigestX962SHA256;
    case SSL_SIGN_ECDSA_SHA1:
      return kSecKeyAlgorithmECDSASignatureDigestX962SHA1;
  }
  if (__builtin_available(macOS 10.13, *)) {
    switch (algorithm) {
      case SSL_SIGN_RSA_PSS_SHA512:
        return kSecKeyAlgorithmRSASignatureDigestPSSSHA512;
      case SSL_SIGN_RSA_PSS_SHA384:
        return kSecKeyAlgorithmRSASignatureDigestPSSSHA384;
      case SSL_SIGN_RSA_PSS_SHA256:
        return kSecKeyAlgorithmRSASignatureDigestPSSSHA256;
    }
  }

  return nullptr;
}

class API_AVAILABLE(macos(10.12)) SSLPlatformKeySecKey
    : public ThreadedSSLPrivateKey::Delegate {
 public:
  SSLPlatformKeySecKey(bssl::UniquePtr<EVP_PKEY> pubkey, SecKeyRef key)
      : pubkey_(std::move(pubkey)), key_(key, base::scoped_policy::RETAIN) {
    // Determine the algorithms supported by the key.
    for (uint16_t algorithm : SSLPrivateKey::DefaultAlgorithmPreferences(
             EVP_PKEY_id(pubkey_.get()), true /* include PSS */)) {
      bool unused;
      if (GetSecKeyAlgorithmWithFallback(algorithm, &unused)) {
        preferences_.push_back(algorithm);
      }
    }
  }

  SSLPlatformKeySecKey(const SSLPlatformKeySecKey&) = delete;
  SSLPlatformKeySecKey& operator=(const SSLPlatformKeySecKey&) = delete;

  ~SSLPlatformKeySecKey() override = default;

  std::string GetProviderName() override {
    // TODO(crbug.com/41423739): Is there a more descriptive name to
    // return?
    return "SecKey";
  }

  std::vector<uint16_t> GetAlgorithmPreferences() override {
    return preferences_;
  }

  Error Sign(uint16_t algorithm,
             base::span<const uint8_t> input,
             std::vector<uint8_t>* signature) override {
    bool pss_fallback = false;
    SecKeyAlgorithm sec_algorithm =
        GetSecKeyAlgorithmWithFallback(algorithm, &pss_fallback);
    if (!sec_algorithm) {
      // The caller should not request a signature algorithm we do not support.
      // However, it's possible `key_` previously reported it supported an
      // algorithm but no longer does. A compromised network service could also
      // request invalid algorithms, so cleanly fail.
      LOG(ERROR) << "Unsupported signature algorithm: " << algorithm;
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }

    const EVP_MD* md = SSL_get_signature_algorithm_digest(algorithm);
    uint8_t digest_buf[EVP_MAX_MD_SIZE];
    unsigned digest_len;
    if (!md || !EVP_Digest(input.data(), input.size(), digest_buf, &digest_len,
                           md, nullptr)) {
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }
    base::span<const uint8_t> digest =
        UNSAFE_TODO(base::span(digest_buf, digest_len));

    std::optional<std::vector<uint8_t>> pss_storage;
    if (pss_fallback) {
      // Implement RSA-PSS by adding the padding manually and then using
      // kSecKeyAlgorithmRSASignatureRaw.
      DCHECK(SSL_is_signature_algorithm_rsa_pss(algorithm));
      DCHECK_EQ(sec_algorithm, kSecKeyAlgorithmRSASignatureRaw);
      pss_storage = AddPSSPadding(pubkey_.get(), md, digest);
      if (!pss_storage) {
        return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
      }
      digest = *pss_storage;
    }

    base::apple::ScopedCFTypeRef<CFDataRef> digest_ref(
        CFDataCreate(kCFAllocatorDefault, digest.data(),
                     base::checked_cast<CFIndex>(digest.size())));

    base::apple::ScopedCFTypeRef<CFErrorRef> error;
    base::apple::ScopedCFTypeRef<CFDataRef> signature_ref(SecKeyCreateSignature(
        key_.get(), sec_algorithm, digest_ref.get(), error.InitializeInto()));
    if (!signature_ref) {
      LOG(ERROR) << error.get();
      return ERR_SSL_CLIENT_AUTH_SIGNATURE_FAILED;
    }

    auto signature_span = base::apple::CFDataToSpan(signature_ref.get());
    signature->assign(signature_span.begin(), signature_span.end());
    return OK;
  }

 private:
  // Returns the algorithm to use with |algorithm| and this key, or nullptr if
  // not supported. If the resulting algorithm should be manually padded for
  // RSA-PSS, |*out_pss_fallback| is set to true.
  SecKeyAlgorithm GetSecKeyAlgorithmWithFallback(uint16_t algorithm,
                                                 bool* out_pss_fallback) {
    SecKeyAlgorithm sec_algorithm = GetSecKeyAlgorithm(algorithm);
    if (sec_algorithm &&
        SecKeyIsAlgorithmSupported(key_.get(), kSecKeyOperationTypeSign,
                                   sec_algorithm)) {
      *out_pss_fallback = false;
      return sec_algorithm;
    }

    if (SSL_is_signature_algorithm_rsa_pss(algorithm) &&
        SecKeyIsAlgorithmSupported(key_.get(), kSecKeyOperationTypeSign,
                                   kSecKeyAlgorithmRSASignatureRaw)) {
      *out_pss_fallback = true;
      return kSecKeyAlgorithmRSASignatureRaw;
    }

    return nullptr;
  }

  std::vector<uint16_t> preferences_;
  bssl::UniquePtr<EVP_PKEY> pubkey_;
  base::apple::ScopedCFTypeRef<SecKeyRef> key_;
};

scoped_refptr<SSLPrivateKey> WrapSecKey(bssl::UniquePtr<EVP_PKEY> pubkey,
                                        SecKeyRef key) {
  int key_type = EVP_PKEY_id(pubkey.get());
  if (key_type != EVP_PKEY_RSA && key_type != EVP_PKEY_EC) {
    return nullptr;
  }

  if (__builtin_available(macOS 10.12, *)) {
    return base::MakeRefCounted<ThreadedSSLPrivateKey>(
        std::make_unique<SSLPlatformKeySecKey>(std::move(pubkey), key),
        GetSSLPlatformKeyTaskRunner());
  }
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101200
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  const CSSM_KEY* cssm_key = nullptr;
  OSStatus status = SecKeyGetCSSMKey(key, &cssm_key);
  if (status != noErr || !cssm_key) {
    OSSTATUS_LOG(WARNING, status);
    return nullptr;
  }
  return base::MakeRefCounted<ThreadedSSLPrivateKey>(
      std::make_unique<SSLPlatformKeyCSSM>(std::move(pubkey), key, cssm_key),
      GetSSLPlatformKeyTaskRunner());
#pragma clang diagnostic pop
#else
  return nullptr;
#endif
}

}  // namespace

scoped_refptr<SSLPrivateKey> CreateSSLPrivateKeyForSecKey(
    const X509Certificate* certificate,
    SecKeyRef key) {
  bssl::UniquePtr<EVP_PKEY> pubkey = GetClientCertPublicKey(certificate);
  if (!pubkey) {
    return nullptr;
  }
  return WrapSecKey(std::move(pubkey), key);
}

scoped_refptr<SSLPrivateKey> WrapUnexportableKey(
    const crypto::UnexportableSigningKey& unexportable_key) {
  bssl::UniquePtr<EVP_PKEY> pubkey = crypto::evp::PublicKeyFromBytes(
      unexportable_key.GetSubjectPublicKeyInfo());
  if (!pubkey) {
    return nullptr;
  }
  return WrapSecKey(std::move(pubkey), unexportable_key.GetSecKeyRef());
}

}  // namespace net

// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include "base/memory/raw_ptr.h"
#include "chrome/browser/enterprise/connectors/device_trust/key_management/core/mac/secure_enclave_client_impl.h"
#include "chrome/browser/enterprise/connectors/device_trust/key_management/core/mac/secure_enclave_helper_impl.h"
#include "testing/gtest/include/gtest/gtest.h"

#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
#error These tests require the forced unsupported production path.
#endif

namespace enterprise_connectors {
namespace {
class CountingHelper : public SecureEnclaveHelper {
 public:
  explicit CountingHelper(int* calls) : calls_(calls) {}
  base::apple::ScopedCFTypeRef<SecKeyRef> CreateSecureKey(CFDictionaryRef,
                                                          OSStatus*) override {
    ++*calls_;
    return base::apple::ScopedCFTypeRef<SecKeyRef>();
  }
  base::apple::ScopedCFTypeRef<SecKeyRef> CopyKey(CFDictionaryRef,
                                                  OSStatus*) override {
    ++*calls_;
    return base::apple::ScopedCFTypeRef<SecKeyRef>();
  }
  OSStatus Update(CFDictionaryRef, CFDictionaryRef) override {
    ++*calls_;
    return errSecInternalComponent;
  }
  OSStatus Delete(CFDictionaryRef) override {
    ++*calls_;
    return errSecInternalComponent;
  }
  bool IsSecureEnclaveSupported() override {
    ++*calls_;
    return false;
  }

 private:
  raw_ptr<int> calls_;
};

TEST(SecureEnclaveUnsupported, ClientRejectsBeforeQueryMutationOrSigning) {
  int calls = 0;
  SecureEnclaveHelper::SetInstanceForTesting(
      std::make_unique<CountingHelper>(&calls));
  SecureEnclaveClientImpl client;
  using KeyType = SecureEnclaveClient::KeyType;
  EXPECT_FALSE(client.CreatePermanentKey());
  OSStatus error = errSecSuccess;
  EXPECT_FALSE(client.CopyStoredKey(KeyType::kPermanent, &error));
  EXPECT_EQ(errSecUnimplemented, error);
  EXPECT_FALSE(client.CopyStoredKey(KeyType::kTemporary, nullptr));
  EXPECT_FALSE(
      client.UpdateStoredKeyLabel(KeyType::kPermanent, KeyType::kTemporary));
  EXPECT_FALSE(client.DeleteKey(KeyType::kPermanent));
  EXPECT_FALSE(client.DeleteKey(KeyType::kTemporary));
  std::vector<uint8_t> output{1, 2, 3};
  const auto original = output;
  error = errSecSuccess;
  EXPECT_FALSE(client.ExportPublicKey(nullptr, output, &error));
  EXPECT_EQ(errSecUnimplemented, error);
  EXPECT_EQ(original, output);
  error = errSecSuccess;
  EXPECT_FALSE(client.SignDataWithKey(nullptr, original, output, &error));
  EXPECT_EQ(errSecUnimplemented, error);
  EXPECT_EQ(original, output);
  EXPECT_FALSE(client.VerifySecureEnclaveSupported());
  EXPECT_EQ(0, calls);
}

TEST(SecureEnclaveUnsupported, NativeHelperRejectsBeforeSecurityCalls) {
  SecureEnclaveHelperImpl helper;
  OSStatus error = errSecSuccess;
  EXPECT_FALSE(helper.CreateSecureKey(nullptr, &error));
  EXPECT_EQ(errSecUnimplemented, error);
  EXPECT_FALSE(helper.CreateSecureKey(nullptr, nullptr));
  error = errSecSuccess;
  EXPECT_FALSE(helper.CopyKey(nullptr, &error));
  EXPECT_EQ(errSecUnimplemented, error);
  EXPECT_FALSE(helper.CopyKey(nullptr, nullptr));
  EXPECT_EQ(errSecUnimplemented, helper.Update(nullptr, nullptr));
  EXPECT_EQ(errSecUnimplemented, helper.Delete(nullptr));
  EXPECT_FALSE(helper.IsSecureEnclaveSupported());
}
}  // namespace
}  // namespace enterprise_connectors

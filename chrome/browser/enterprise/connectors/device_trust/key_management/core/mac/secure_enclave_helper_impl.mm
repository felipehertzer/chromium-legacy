// Copyright 2022 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/enterprise/connectors/device_trust/key_management/core/mac/secure_enclave_helper_impl.h"

#include <CryptoTokenKit/CryptoTokenKit.h>
#import <Foundation/Foundation.h>
#include <Security/Security.h>

#include <memory>

#include "base/apple/bridging.h"
#include "base/apple/scoped_cftyperef.h"

namespace enterprise_connectors {

namespace {
// Permanent enclave keys use the data-protection keychain (10.15+). Keep
// unsupported operations ahead of all queries, mutations and signing calls.
bool SecureEnclaveAPIsEnabled() {
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  return false;
#else
  return true;
#endif
}
}  // namespace

SecureEnclaveHelperImpl::~SecureEnclaveHelperImpl() = default;

base::apple::ScopedCFTypeRef<SecKeyRef>
SecureEnclaveHelperImpl::CreateSecureKey(CFDictionaryRef attributes,
                                         OSStatus* error) {
  if (@available(macOS 10.15, *)) {
    if (SecureEnclaveAPIsEnabled()) {
      base::apple::ScopedCFTypeRef<CFErrorRef> error_ref;
      base::apple::ScopedCFTypeRef<SecKeyRef> key(
          SecKeyCreateRandomKey(attributes, error_ref.InitializeInto()));

      // In the odd chance that the API did not populate `error_ref`, fallback
      // to errSecCoreFoundationUnknown.
      OSStatus status = error_ref ? CFErrorGetCode(error_ref.get())
                                  : errSecCoreFoundationUnknown;
      if (error) {
        *error = status;
      }

      return key;
    }
  }
  if (error) {
    *error = errSecUnimplemented;
  }
  return base::apple::ScopedCFTypeRef<SecKeyRef>();
}

base::apple::ScopedCFTypeRef<SecKeyRef> SecureEnclaveHelperImpl::CopyKey(
    CFDictionaryRef query,
    OSStatus* error) {
  if (@available(macOS 10.15, *)) {
    if (SecureEnclaveAPIsEnabled()) {
      base::apple::ScopedCFTypeRef<SecKeyRef> key;
      OSStatus status = SecItemCopyMatching(
          query, const_cast<CFTypeRef*>(
                     reinterpret_cast<const CFTypeRef*>(key.InitializeInto())));

      if (error) {
        *error = status;
      }

      return key;
    }
  }
  if (error) {
    *error = errSecUnimplemented;
  }
  return base::apple::ScopedCFTypeRef<SecKeyRef>();
}

OSStatus SecureEnclaveHelperImpl::Update(CFDictionaryRef query,
                                         CFDictionaryRef attributes_to_update) {
  if (@available(macOS 10.15, *)) {
    if (SecureEnclaveAPIsEnabled()) {
      return SecItemUpdate(query, attributes_to_update);
    }
  }
  return errSecUnimplemented;
}

OSStatus SecureEnclaveHelperImpl::Delete(CFDictionaryRef query) {
  if (@available(macOS 10.15, *)) {
    if (SecureEnclaveAPIsEnabled()) {
      return SecItemDelete(query);
    }
  }
  return errSecUnimplemented;
}

bool SecureEnclaveHelperImpl::IsSecureEnclaveSupported() {
  if (@available(macOS 10.15, *)) {
    if (SecureEnclaveAPIsEnabled()) {
      TKTokenWatcher* token_watcher = [[TKTokenWatcher alloc] init];
      return ([token_watcher.tokenIDs
          containsObject:base::apple::CFToNSPtrCast(
                             kSecAttrTokenIDSecureEnclave)]);
    }
  }
  return false;
}

}  // namespace enterprise_connectors

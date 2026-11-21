// Copyright 2012 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "net/base/platform_mime_util.h"

#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <string>

#include "base/apple/bridging.h"
#include "base/apple/foundation_util.h"
#include "base/apple/scoped_cftyperef.h"
#include "base/notreached.h"
#include "base/strings/sys_string_conversions.h"
#include "build/build_config.h"

#if BUILDFLAG(IS_IOS)
#include <MobileCoreServices/MobileCoreServices.h>
#else
#include <CoreServices/CoreServices.h>
#endif  // BUILDFLAG(IS_IOS)

namespace net {

#if BUILDFLAG(IS_MAC) && __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
namespace {
bool IsDynamicType(CFStringRef type) {
  if (__builtin_available(macOS 10.10, *)) {
    return UTTypeIsDynamic(type);
  }
  // Dynamic UTIs use the reserved dyn. prefix on older Launch Services.
  return CFStringHasPrefix(type, CFSTR("dyn."));
}
base::apple::ScopedCFTypeRef<CFTypeRef> CopyExtensionTags(CFStringRef type) {
  if (__builtin_available(macOS 10.10, *)) {
    return base::apple::ScopedCFTypeRef<CFTypeRef>(
        UTTypeCopyAllTagsWithClass(type, kUTTagClassFilenameExtension));
  }
  base::apple::ScopedCFTypeRef<CFDictionaryRef> declaration(
      UTTypeCopyDeclaration(type));
  if (!declaration) {
    return base::apple::ScopedCFTypeRef<CFTypeRef>();
  }
  CFDictionaryRef specification =
      base::apple::GetValueFromDictionary<CFDictionaryRef>(
          declaration.get(), kUTTypeTagSpecificationKey);
  CFTypeRef tags =
      specification
          ? CFDictionaryGetValue(specification, kUTTagClassFilenameExtension)
          : nullptr;
  return base::apple::ScopedCFTypeRef<CFTypeRef>(tags,
                                                 base::scoped_policy::RETAIN);
}
}  // namespace
#endif

bool PlatformMimeUtil::GetPlatformMimeTypeFromExtension(
    const base::FilePath::StringType& ext,
    std::string* result) const {
  std::string ext_nodot = ext;
  if (ext_nodot.length() >= 1 && ext_nodot[0] == L'.') {
    ext_nodot.erase(ext_nodot.begin());
  }

  if (@available(macOS 11.0, iOS 14.0, *)) {
    UTType* uttype =
        [UTType typeWithFilenameExtension:base::SysUTF8ToNSString(ext_nodot)];
    // Dynamic UTTypes are made by the system in the event that there's a
    // non-identifiable mime type. For now, we should treat dynamic UTTypes as a
    // nonstandard format.
    if (uttype.dynamic || uttype.preferredMIMEType == nil) {
      return false;
    }
    *result = base::SysNSStringToUTF8(uttype.preferredMIMEType);
    return true;
  }
#if BUILDFLAG(IS_MAC) && __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
  base::apple::ScopedCFTypeRef<CFStringRef> type(
      UTTypeCreatePreferredIdentifierForTag(
          kUTTagClassFilenameExtension,
          base::apple::NSToCFPtrCast(base::SysUTF8ToNSString(ext_nodot)),
          nullptr));
  if (!type || IsDynamicType(type.get())) {
    return false;
  }
  base::apple::ScopedCFTypeRef<CFStringRef> mime(
      UTTypeCopyPreferredTagWithClass(type.get(), kUTTagClassMIMEType));
  if (mime) {
    *result = base::SysCFStringRefToUTF8(mime.get());
    return true;
  }
#endif
  return false;
}

bool PlatformMimeUtil::GetPlatformPreferredExtensionForMimeType(
    std::string_view mime_type,
    base::FilePath::StringType* ext) const {
  if (@available(macOS 11.0, iOS 14.0, *)) {
    UTType* uttype =
        [UTType typeWithMIMEType:base::SysUTF8ToNSString(mime_type)];
    if (uttype.dynamic || uttype.preferredFilenameExtension == nil) {
      return false;
    }
    *ext = base::SysNSStringToUTF8(uttype.preferredFilenameExtension);
    return true;
  }
#if BUILDFLAG(IS_MAC) && __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
  base::apple::ScopedCFTypeRef<CFStringRef> type(
      UTTypeCreatePreferredIdentifierForTag(
          kUTTagClassMIMEType,
          base::apple::NSToCFPtrCast(base::SysUTF8ToNSString(mime_type)),
          nullptr));
  if (!type || IsDynamicType(type.get())) {
    return false;
  }
  base::apple::ScopedCFTypeRef<CFStringRef> extension(
      UTTypeCopyPreferredTagWithClass(type.get(),
                                      kUTTagClassFilenameExtension));
  if (extension) {
    *ext = base::SysCFStringRefToUTF8(extension.get());
    return true;
  }
#endif
  return false;
}

void PlatformMimeUtil::GetPlatformExtensionsForMimeType(
    std::string_view mime_type,
    std::unordered_set<base::FilePath::StringType>* extensions) const {
  bool extensions_found = false;
  if (@available(macOS 11.0, iOS 14.0, *)) {
    NSArray<UTType*>* types =
        [UTType typesWithTag:base::SysUTF8ToNSString(mime_type)
                    tagClass:UTTagClassMIMEType
            conformingToType:nil];
    if (types) {
      for (UTType* type in types) {
        if (!type || type.preferredFilenameExtension == nil) {
          continue;
        }
        extensions_found = true;
        NSArray<NSString*>* extensions_list =
            type.tags[UTTagClassFilenameExtension];
        for (NSString* extension in extensions_list) {
          extensions->insert(base::SysNSStringToUTF8(extension));
        }
      }
    }

  } else {
#if BUILDFLAG(IS_MAC) && __MAC_OS_X_VERSION_MIN_REQUIRED < 110000
    base::apple::ScopedCFTypeRef<CFArrayRef> types(
        UTTypeCreateAllIdentifiersForTag(
            kUTTagClassMIMEType,
            base::apple::NSToCFPtrCast(base::SysUTF8ToNSString(mime_type)),
            nullptr));
    if (types) {
      for (CFIndex i = 0; i < CFArrayGetCount(types.get()); ++i) {
        CFStringRef type = base::apple::CFCast<CFStringRef>(
            CFArrayGetValueAtIndex(types.get(), i));
        if (!type || IsDynamicType(type)) {
          continue;
        }
        auto tags = CopyExtensionTags(type);
        if (CFStringRef extension =
                base::apple::CFCast<CFStringRef>(tags.get())) {
          extensions->insert(base::SysCFStringRefToUTF8(extension));
          extensions_found = true;
        } else if (CFArrayRef list =
                       base::apple::CFCast<CFArrayRef>(tags.get())) {
          for (CFIndex j = 0; j < CFArrayGetCount(list); ++j) {
            if (CFStringRef item_extension = base::apple::CFCast<CFStringRef>(
                    CFArrayGetValueAtIndex(list, j))) {
              extensions->insert(base::SysCFStringRefToUTF8(item_extension));
              extensions_found = true;
            }
          }
        }
      }
    }
#endif
  }

  if (extensions_found) {
    return;
  }

  base::FilePath::StringType ext;
  if (GetPlatformPreferredExtensionForMimeType(mime_type, &ext)) {
    extensions->insert(ext);
  }
}

}  // namespace net

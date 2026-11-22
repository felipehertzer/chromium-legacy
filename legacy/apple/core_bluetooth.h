// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef LEGACY_APPLE_CORE_BLUETOOTH_H_
#define LEGACY_APPLE_CORE_BLUETOOTH_H_

#import <CoreBluetooth/CoreBluetooth.h>
#import <Foundation/Foundation.h>

// Original Lion selectors, removed from current SDK declarations:
// https://chromium.googlesource.com/chromium/src/+/48.0.2564.80/base/mac/sdk_forward_declarations.h
@interface CBPeripheral (ChromiumLegacyLion)
@property(readonly, nonatomic) CFUUIDRef UUID;
@property(readonly) BOOL isConnected;
@end

namespace chromium_legacy {

#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && \
    __MAC_OS_X_VERSION_MIN_REQUIRED < 101300
inline constexpr NSInteger kBluetoothStateUnknown =
    CBCentralManagerStateUnknown;
inline constexpr NSInteger kBluetoothStateResetting =
    CBCentralManagerStateResetting;
inline constexpr NSInteger kBluetoothStatePoweredOff =
    CBCentralManagerStatePoweredOff;
inline constexpr NSInteger kBluetoothStatePoweredOn =
    CBCentralManagerStatePoweredOn;
#else
inline constexpr NSInteger kBluetoothStateUnknown = CBManagerStateUnknown;
inline constexpr NSInteger kBluetoothStateResetting = CBManagerStateResetting;
inline constexpr NSInteger kBluetoothStatePoweredOff = CBManagerStatePoweredOff;
inline constexpr NSInteger kBluetoothStatePoweredOn = CBManagerStatePoweredOn;
#endif

inline NSString* BluetoothUUIDStringFromData(NSData* data) {
  NSUInteger length = data.length;
  if (length != 2 && length != 4 && length != 16) {
    return nil;
  }
  NSMutableString* result = [NSMutableString stringWithCapacity:length * 2 + 4];
  for (NSUInteger index = 0; index < length; ++index) {
    if (length == 16 &&
        (index == 4 || index == 6 || index == 8 || index == 10)) {
      [result appendString:@"-"];
    }
    uint8_t byte = 0;
    [data getBytes:&byte range:NSMakeRange(index, 1)];
    [result appendFormat:@"%02X", static_cast<unsigned>(byte)];
  }
  return result;
}

inline NSString* BluetoothUUIDString(CBUUID* uuid) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.10, iOS 7.0, tvOS 9.0, *)) {
    return uuid.UUIDString;
  }
#endif
  return BluetoothUUIDStringFromData(uuid.data);
}

inline NSString* PeripheralIdentifier(CBPeripheral* peripheral) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.13, iOS 7.0, tvOS 9.0, *)) {
    return peripheral.identifier.UUIDString;
  }
  if (@available(macOS 10.9, iOS 7.0, tvOS 9.0, *)) {
    if ([peripheral respondsToSelector:@selector(identifier)]) {
      NSUUID* identifier = [peripheral performSelector:@selector(identifier)];
      return identifier.UUIDString;
    }
  }
#endif
  if (![peripheral respondsToSelector:@selector(UUID)]) {
    return nil;
  }
  CFUUIDRef identifier = peripheral.UUID;
  return identifier ? CFBridgingRelease(CFUUIDCreateString(nullptr, identifier))
                    : nil;
}

inline bool IsPeripheralConnected(CBPeripheral* peripheral) {
#if !defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS)
  if (@available(macOS 10.9, iOS 7.0, tvOS 9.0, *)) {
    return peripheral.state == CBPeripheralStateConnected;
  }
#endif
  return [peripheral respondsToSelector:@selector(isConnected)] &&
         peripheral.isConnected;
}

}  // namespace chromium_legacy

#endif  // LEGACY_APPLE_CORE_BLUETOOTH_H_

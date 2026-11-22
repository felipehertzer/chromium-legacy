// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <stdio.h>

#include "legacy/apple/core_bluetooth.h"

@interface LegacyBluetoothPeripheralProbe : NSObject
@property(nonatomic) BOOL connected;
- (CFUUIDRef)UUID;
- (NSUUID*)identifier API_AVAILABLE(macos(10.8), ios(6.0));
- (CBPeripheralState)state API_AVAILABLE(macos(10.9), ios(7.0));
- (BOOL)isConnected;
@end

@implementation LegacyBluetoothPeripheralProbe {
  CFUUIDRef _uuid;
}
- (instancetype)init {
  if ((self = [super init])) {
    _uuid = CFUUIDCreateFromString(
        nullptr, CFSTR("00112233-4455-6677-8899-AABBCCDDEEFF"));
  }
  return self;
}
- (void)dealloc {
  if (_uuid) {
    CFRelease(_uuid);
  }
}
- (CFUUIDRef)UUID {
  return _uuid;
}
- (NSUUID*)identifier {
  NSString* value = CFBridgingRelease(CFUUIDCreateString(nullptr, _uuid));
  return [[NSUUID alloc] initWithUUIDString:value];
}
- (CBPeripheralState)state {
  return self.connected ? CBPeripheralStateConnected
                        : CBPeripheralStateDisconnected;
}
- (BOOL)isConnected {
  return self.connected;
}
@end

namespace {
int checks = 0;
int failures = 0;
void Check(bool value, const char* label) {
  ++checks;
  if (!value) {
    ++failures;
    fprintf(stderr, "FAILED: %s\n", label);
  }
}
}  // namespace

int main() {
  @autoreleasepool {
    Check(CBAdvertisementDataServiceUUIDsKey &&
              CBAdvertisementDataServiceDataKey &&
              CBAdvertisementDataManufacturerDataKey &&
              CBAdvertisementDataTxPowerLevelKey &&
              CBAdvertisementDataLocalNameKey,
          "original advertisement keys resolve through the stable umbrella");
    if (@available(macOS 10.9, iOS 6.0, *)) {
      Check(CBAdvertisementDataOverflowServiceUUIDsKey != nil,
            "newer advertisement metadata remains available on supported "
            "systems");
    }
    CBUUID* short_uuid = [CBUUID UUIDWithString:@"180D"];
    CBUUID* full_uuid =
        [CBUUID UUIDWithString:@"00112233-4455-6677-8899-AABBCCDDEEFF"];
    Check([chromium_legacy::BluetoothUUIDString(short_uuid)
              isEqualToString:@"180D"],
          "16-bit service UUID remains canonical");
    Check([chromium_legacy::BluetoothUUIDString(full_uuid)
              isEqualToString:@"00112233-4455-6677-8899-AABBCCDDEEFF"],
          "128-bit service UUID retains network byte order");
    Check(chromium_legacy::BluetoothUUIDString(nil) == nil,
          "missing service UUID is rejected");

    const uint8_t bytes[] = {0x12, 0x34, 0x56, 0x78};
    NSData* data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    Check([chromium_legacy::BluetoothUUIDStringFromData(data)
              isEqualToString:@"12345678"],
          "32-bit service UUID retains all bytes");
    Check(chromium_legacy::BluetoothUUIDStringFromData([NSData data]) == nil,
          "empty UUID data is rejected");
    Check(chromium_legacy::BluetoothUUIDStringFromData(
              [NSData dataWithBytes:bytes length:1]) == nil,
          "invalid UUID width is rejected");

    LegacyBluetoothPeripheralProbe* peripheral =
        [[LegacyBluetoothPeripheralProbe alloc] init];
    CBPeripheral* value = (CBPeripheral*)peripheral;
    Check(!chromium_legacy::IsPeripheralConnected(value),
          "disconnected peripheral uses the correct selector");
    peripheral.connected = YES;
    Check(chromium_legacy::IsPeripheralConnected(value),
          "connected peripheral uses the correct selector");
    Check(!chromium_legacy::IsPeripheralConnected(nil),
          "missing peripheral is disconnected");
    NSString* identifier = chromium_legacy::PeripheralIdentifier(value);
    Check([identifier isEqualToString:@"00112233-4455-6677-8899-AABBCCDDEEFF"],
          "peripheral identity is stable across UUID representations");
    value = nil;
    peripheral = nil;
    Check([identifier isEqualToString:@"00112233-4455-6677-8899-AABBCCDDEEFF"],
          "identity string retains its value after peripheral destruction");
    Check(chromium_legacy::PeripheralIdentifier(nil) == nil,
          "missing peripheral identity is rejected");
    Check(chromium_legacy::kBluetoothStateUnknown == 0 &&
              chromium_legacy::kBluetoothStateResetting == 1 &&
              chromium_legacy::kBluetoothStatePoweredOff == 4 &&
              chromium_legacy::kBluetoothStatePoweredOn == 5,
          "manager state values retain the original ABI");
  }
  printf("%d Bluetooth compatibility checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}

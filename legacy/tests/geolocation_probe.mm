// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <iostream>
#include <string_view>
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_executor.h"
#include "legacy/apple/location.h"
#include "services/device/public/cpp/geolocation/location_manager_delegate.h"
#include "services/device/public/cpp/geolocation/system_geolocation_source_apple.h"

// The existing injection seam accepts this NSObject test double. It records
// requests without requiring CLLocationManager metaclass exports absent on
// Lion. Its methods never call the native location service, display a
// permission prompt, read a position or scan Wi-Fi.
@interface ProbeLocationManager : NSObject {
 @public
  int starts;
  int stops;
  int authorizations;
  CLLocationAccuracy accuracy;
}
@end
@implementation ProbeLocationManager
- (void)startUpdatingLocation {
  ++starts;
}
- (void)stopUpdatingLocation {
  ++stops;
}
- (void)requestWhenInUseAuthorization {
  ++authorizations;
}
- (void)setDesiredAccuracy:(CLLocationAccuracy)value {
  accuracy = value;
}
- (CLLocationAccuracy)desiredAccuracy {
  return accuracy;
}
@end

namespace {
int checks = 0;
int failures = 0;
void Check(bool result, std::string_view message) {
  ++checks;
  if (!result) {
    ++failures;
    std::cerr << "FAIL: " << message << "\n";
  }
}
struct State : device::SystemGeolocationSource::PositionObserver {
  device::LocationSystemPermissionStatus permission =
      device::LocationSystemPermissionStatus::kNotDetermined;
  int permission_callbacks = 0;
  int positions = 0;
  double latitude = 0;
  void Permission(device::LocationSystemPermissionStatus status) {
    ++permission_callbacks;
    permission = status;
  }
  void OnPositionUpdated(const device::mojom::Geoposition& position) override {
    ++positions;
    latitude = position.latitude;
  }
  void OnPositionError(const device::mojom::GeopositionError&) override {
    Check(false, "synthetic successful updates do not report an error");
  }
};
CLAuthorizationStatus AuthorizedStatus() {
  if (@available(macOS 10.12, *))
    return kCLAuthorizationStatusAuthorizedAlways;
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101200
  return kCLAuthorizationStatusAuthorized;
#else
  return kCLAuthorizationStatusDenied;
#endif
}
}  // namespace

int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::SingleThreadTaskExecutor executor;
  @autoreleasepool {
    using Permission = device::LocationSystemPermissionStatus;
    State state;
    auto source = std::make_unique<device::SystemGeolocationSourceApple>();
    ProbeLocationManager* manager = [[ProbeLocationManager alloc] init];
    source->SetLocationManagerForTesting((CLLocationManager*)manager);
    source->SetWifiStatusForTesting(true);
    LocationManagerDelegate* delegate = source->GetDelegateForTesting();
    source->RegisterPermissionUpdateCallback(
        base::BindRepeating(&State::Permission, base::Unretained(&state)));
    Check(state.permission == Permission::kNotDetermined,
          "initial authorization remains undetermined");
    for (CLAuthorizationStatus status :
         {kCLAuthorizationStatusDenied, kCLAuthorizationStatusRestricted}) {
      [delegate locationManager:(CLLocationManager*)manager
          didChangeAuthorizationStatus:status];
      Check(state.permission == Permission::kDenied,
            "denied and restricted authorization cannot grant permission");
    }
    [delegate locationManager:(CLLocationManager*)manager
        didChangeAuthorizationStatus:kCLAuthorizationStatusNotDetermined];
    source->RequestPermission();
    const bool explicit_request =
        chromium_legacy::ExplicitLocationAuthorizationAvailable();
    Check(manager->authorizations == (explicit_request ? 1 : 0),
          "explicit native request is selected only when available");
    Check(manager->starts == (explicit_request ? 0 : 1),
          "older authorization starts one pending native request");
    Check(manager->stops == 0, "pending authorization is not stopped early");
    source->RequestPermission();
    Check(explicit_request || manager->starts == 1,
          "repeated pending legacy permission requests do not start another "
          "watch");
    [delegate locationManager:(CLLocationManager*)manager
        didChangeAuthorizationStatus:AuthorizedStatus()];
    Check(state.permission == Permission::kAllowed,
          "authorized native status grants permission");
    Check(manager->stops == (explicit_request ? 0 : 1),
          "permission-only legacy updates stop when their answer arrives");
    source->AddPositionUpdateObserver(&state);
    source->StartWatchingPosition(true);
    base::RunLoop().RunUntilIdle();
    Check(manager->accuracy == kCLLocationAccuracyBest,
          "requested watch accuracy reaches the native manager");
    const int stops_before_watch_answer = manager->stops;
    source->RequestPermission();
    [delegate locationManager:(CLLocationManager*)manager
        didChangeAuthorizationStatus:AuthorizedStatus()];
    Check(manager->stops == stops_before_watch_answer,
          "authorization completion does not stop an actual position watch");
    CLLocation* position = [[CLLocation alloc]
        initWithCoordinate:CLLocationCoordinate2DMake(45, -75)
                  altitude:123
        horizontalAccuracy:7
          verticalAccuracy:9
                 timestamp:[NSDate dateWithTimeIntervalSince1970:123456]];
    [delegate locationManager:(CLLocationManager*)manager
           didUpdateLocations:@[ position ]];
    base::RunLoop().RunUntilIdle();
    Check(state.positions == 1 && state.latitude == 45,
          "synthetic native update reaches the production observer");
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
    [delegate locationManager:(CLLocationManager*)manager
          didUpdateToLocation:position
                 fromLocation:position];
    base::RunLoop().RunUntilIdle();
    Check(state.positions == 2,
          "original Lion callback forwards to the same production update path");
#endif
    const int valid_positions = state.positions;
    [delegate locationManager:(CLLocationManager*)manager
           didUpdateLocations:@[]];
    base::RunLoop().RunUntilIdle();
    Check(state.positions == valid_positions,
          "empty updates publish no fabricated position");
    Check(chromium_legacy::LocationAltitude(position, false) == 123,
          "traditional altitude retains the native measurement");
    source->StopWatchingPosition();
    base::RunLoop().RunUntilIdle();
    Check(manager->stops == stops_before_watch_answer + 1,
          "stopping a real watch stops its native updates");
    source->RemovePositionUpdateObserver(&state);
    const int callbacks_before_destruction = state.permission_callbacks;
    source.reset();
    [delegate locationManager:(CLLocationManager*)manager
        didChangeAuthorizationStatus:AuthorizedStatus()];
    [delegate locationManager:(CLLocationManager*)manager
           didUpdateLocations:@[ position ]];
    [delegate locationManager:(CLLocationManager*)manager
             didFailWithError:[NSError errorWithDomain:kCLErrorDomain
                                                  code:kCLErrorDenied
                                              userInfo:nil]];
    base::RunLoop().RunUntilIdle();
    Check(state.permission_callbacks == callbacks_before_destruction &&
              state.positions == valid_positions,
          "late native callbacks ignore a destroyed provider");
  }
  std::cout << checks << " geolocation checks, " << failures << " failures\n";
  return failures ? 1 : 0;
}

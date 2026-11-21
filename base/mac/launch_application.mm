// Copyright 2013 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "base/mac/launch_application.h"

#include <variant>

#include "base/apple/bridging.h"
#include "base/apple/foundation_util.h"
#include "base/command_line.h"
#include "base/functional/callback.h"
#include "base/logging.h"
#include "base/mac/launch_services_spi.h"
#include "base/mac/mac_util.h"
#include "base/metrics/histogram_functions.h"
#include "base/strings/sys_string_conversions.h"
#include "base/types/expected.h"

namespace base::mac {

namespace {

// These values are persisted to logs. Entries should not be renumbered and
// numeric values should never be reused.
enum class LaunchResult {
  kSuccess = 0,
  kSuccessDespiteError = 1,
  kFailure = 2,
  kMaxValue = kFailure,
};

NSArray* CommandLineArgsToArgsArray(const CommandLineArgs& command_line_args) {
  if (const CommandLine* command_line =
          std::get_if<CommandLine>(&command_line_args)) {
    const auto& argv = command_line->argv();
    size_t argc = argv.size();
    DCHECK_GT(argc, 0lu);

    NSMutableArray* args_array = [NSMutableArray arrayWithCapacity:argc - 1];
    // NSWorkspace automatically adds the binary path as the first argument and
    // thus it should not be included in the list.
    for (size_t i = 1; i < argc; ++i) {
      [args_array addObject:base::SysUTF8ToNSString(argv[i])];
    }

    return args_array;
  }

  if (const std::vector<std::string>* string_vector =
          std::get_if<std::vector<std::string>>(&command_line_args)) {
    NSMutableArray* args_array =
        [NSMutableArray arrayWithCapacity:string_vector->size()];
    for (const auto& arg : *string_vector) {
      [args_array addObject:base::SysUTF8ToNSString(arg)];
    }

    return args_array;
  }

  return @[];
}

__attribute__((availability(macos, introduced = 10.15)))
NSWorkspaceOpenConfiguration*
GetOpenConfiguration(LaunchApplicationOptions options,
                     const CommandLineArgs& command_line_args) {
  NSWorkspaceOpenConfiguration* config =
      [NSWorkspaceOpenConfiguration configuration];

  config.arguments = CommandLineArgsToArgsArray(command_line_args);

  config.activates = options.activate;
  config.createsNewApplicationInstance = options.create_new_instance;
  config.promptsUserIfNeeded = options.prompt_user_if_needed;

  if (options.hidden_in_background) {
    config.addsToRecentItems = NO;
    config.hides = YES;
    config._additionalLSOpenOptions = @{
      apple::CFToNSPtrCast(_kLSOpenOptionBackgroundLaunchKey) : @YES,
    };
  }

  return config;
}

#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101500
// Launch Services accepts both argv and URL events on Lion. A synchronous
// launch on a worker gives us the actual PID before invoking the callback.
void LaunchLegacyApplication(NSURL* bundle_url,
                             NSArray* arguments,
                             NSArray* urls,
                             LaunchApplicationOptions options,
                             void (^completion)(NSRunningApplication*,
                                                NSError*)) {
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        FSRef application;
        OSStatus status = noErr;
        ProcessSerialNumber process{};
        if (!CFURLGetFSRef(apple::NSToCFPtrCast(bundle_url), &application)) {
          status = fnfErr;
        } else {
          LSApplicationParameters parameters{};
          parameters.application = &application;
          parameters.argv = apple::NSToCFPtrCast(arguments);
          if (!options.activate) {
            parameters.flags |= kLSLaunchDontSwitch;
          }
          if (options.create_new_instance) {
            parameters.flags |= kLSLaunchNewInstance;
          }
          if (options.prompt_user_if_needed) {
            parameters.flags |= kLSLaunchAndDisplayErrors;
          }
          if (options.hidden_in_background) {
            // The newer invisible-launch SPI is absent on Lion. Keep the app
            // hidden and inactive using its supported launch flags.
            parameters.flags |= kLSLaunchAndHide | kLSLaunchDontSwitch |
                                kLSLaunchDontAddToRecents;
          }
          if (urls.count) {
            status = LSOpenURLsWithRole(apple::NSToCFPtrCast(urls), kLSRolesAll,
                                        nullptr, &parameters, &process, 1);
          } else {
            status = LSOpenApplication(&parameters, &process);
          }
        }
        pid_t pid = -1;
        if (status == noErr) {
          status = GetProcessPID(&process, &pid);
        }
        NSRunningApplication* app =
            status == noErr ? [NSRunningApplication
                                  runningApplicationWithProcessIdentifier:pid]
                            : nil;
        if (!app && status == noErr) {
          status = procNotFound;
        }
        completion(app, status == noErr
                            ? nil
                            : [NSError errorWithDomain:NSOSStatusErrorDomain
                                                  code:status
                                              userInfo:nil]);
      });
}
#endif

void LogResultAndInvokeCallback(const base::FilePath& app_bundle_path,
                                bool create_new_instance,
                                LaunchApplicationCallback callback,
                                NSRunningApplication* app,
                                NSError* error) {
  UmaHistogramEnumeration(
      "Mac.LaunchApplicationResult",
      app ? LaunchResult::kSuccess : LaunchResult::kFailure);

  if (error) {
    LOG(ERROR) << base::SysNSStringToUTF8(error.localizedDescription);
    std::move(callback).Run(nil, error);
  } else {
    std::move(callback).Run(app, nil);
  }
}

}  // namespace

void LaunchApplication(const base::FilePath& app_bundle_path,
                       const CommandLineArgs& command_line_args,
                       const std::vector<std::string>& url_specs,
                       LaunchApplicationOptions options,
                       LaunchApplicationCallback callback) {
  __block LaunchApplicationCallback callback_block_access =
      base::BindOnce(&LogResultAndInvokeCallback, app_bundle_path,
                     options.create_new_instance, std::move(callback));

  NSURL* bundle_url = apple::FilePathToNSURL(app_bundle_path);
  if (!bundle_url) {
    dispatch_async(dispatch_get_main_queue(), ^{
      std::move(callback_block_access)
          .Run(nil, [NSError errorWithDomain:NSCocoaErrorDomain
                                        code:NSFileNoSuchFileError
                                    userInfo:nil]);
    });
    return;
  }

  NSMutableArray* ns_urls = nil;
  if (!url_specs.empty()) {
    ns_urls = [NSMutableArray arrayWithCapacity:url_specs.size()];
    for (const auto& url_spec : url_specs) {
      [ns_urls
          addObject:[NSURL URLWithString:base::SysUTF8ToNSString(url_spec)]];
    }
  }

  void (^action_block)(NSRunningApplication*, NSError*) =
      ^void(NSRunningApplication* app, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
          std::move(callback_block_access).Run(app, error);
        });
      };

  if (@available(macOS 10.15, *)) {
    NSWorkspaceOpenConfiguration* configuration =
        GetOpenConfiguration(options, command_line_args);
    if (ns_urls) {
      [NSWorkspace.sharedWorkspace openURLs:ns_urls
                       withApplicationAtURL:bundle_url
                              configuration:configuration
                          completionHandler:action_block];
    } else {
      [NSWorkspace.sharedWorkspace openApplicationAtURL:bundle_url
                                          configuration:configuration
                                      completionHandler:action_block];
    }
  } else {
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101500
    LaunchLegacyApplication(bundle_url,
                            CommandLineArgsToArgsArray(command_line_args),
                            ns_urls, options, action_block);
#endif
  }
}

}  // namespace base::mac

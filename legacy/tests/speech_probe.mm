// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <AppKit/AppKit.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>

#import "legacy/apple/speech.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool ok, const char* name) {
  ++checks;
  if (!ok) {
    ++failures;
    std::fprintf(stderr, "FAIL: %s\n", name);
  }
}
}  // namespace
int main() {
  @autoreleasepool {
    NSArray* identifiers = chromium_legacy::LegacySpeechVoiceIdentifiers();
    Check(identifiers != nil, "native voice enumeration returns an array");
    NSString* default_voice = NSSpeechSynthesizer.defaultVoice;
    Check(!default_voice ||
              [[identifiers firstObject] isEqualToString:default_voice],
          "user-selected native voice is first");
    __block int starts = 0, ends = 0, words = 0, errors = 0;
    __block BOOL finished = NO;
    __block NSUInteger end_index = 0;
    __block BOOL callbacks_on_main = YES;
    NSMutableString* text = [@"Legacy speech test." mutableCopy];
    ChromiumLegacySpeechSynthesizer* synthesizer =
        [[ChromiumLegacySpeechSynthesizer alloc]
            initWithText:text
                   voice:nil
                    rate:1.5
                   pitch:1.0
                  volume:0.25
                 handler:^(chromium_legacy::SpeechEvent event, NSRange range,
                           NSString* message) {
                   callbacks_on_main &= NSThread.isMainThread;
                   switch (event) {
                     case chromium_legacy::SpeechEvent::kStart:
                       ++starts;
                       break;
                     case chromium_legacy::SpeechEvent::kEnd:
                       ++ends;
                       end_index = range.location;
                       finished = YES;
                       break;
                     case chromium_legacy::SpeechEvent::kWord:
                       ++words;
                       break;
                     case chromium_legacy::SpeechEvent::kError:
                       ++errors;
                       std::fprintf(stderr, "Native speech error: %s\n",
                                    message.UTF8String);
                       finished = YES;
                       break;
                   }
                 }];
    Check(synthesizer != nil, "owned native synthesizer can be constructed");
    if (!synthesizer) {
      std::printf("%d speech checks, %d failures\n", checks, failures);
      return 1;
    }
    [text setString:@"Caller changed its mutable string."];
    NSNumber* rate = [synthesizer objectForProperty:NSSpeechRateProperty
                                              error:nil];
    NSNumber* volume = [synthesizer objectForProperty:NSSpeechVolumeProperty
                                                error:nil];
    Check(rate && std::abs(rate.doubleValue - 300) < 1,
          "web rate 1.5 maps to the original 300 words per minute");
    Check(volume && std::abs(volume.doubleValue - 0.25) < 0.01,
          "volume is passed to the native synthesizer");
    [synthesizer speechSynthesizer:synthesizer
                     willSpeakWord:NSMakeRange(0, 6)
                          ofString:@"Legacy speech test."];
    Check(words == 1, "valid word ranges reach the callback");
    [synthesizer speechSynthesizer:synthesizer
                     willSpeakWord:NSMakeRange(NSUIntegerMax, 2)
                          ofString:@"short"];
    [synthesizer speechSynthesizer:synthesizer
                     willSpeakWord:NSMakeRange(4, NSUIntegerMax)
                          ofString:@"short"];
    [synthesizer speechSynthesizer:synthesizer
                     willSpeakWord:NSMakeRange(0, 0)
                          ofString:@"short"];
    Check(words == 1, "invalid and overflowing word ranges are rejected");
    char directory[] = "/tmp/chromium-speech-probe.XXXXXX";
    if (!mkdtemp(directory)) {
      return 1;
    }
    NSString* directory_path = [NSString stringWithUTF8String:directory];
    NSURL* output = [NSURL
        fileURLWithPath:[directory_path
                            stringByAppendingPathComponent:@"speech.aiff"]];
    Check([synthesizer startAtURL:output],
          "real speech synthesis starts with silent file output");
    Check(starts == 1, "start event is delivered exactly once");
    Check(![synthesizer startAtURL:output],
          "an utterance cannot be started twice");
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    while (!finished && deadline.timeIntervalSinceNow > 0) {
      [NSRunLoop.currentRunLoop
             runMode:NSDefaultRunLoopMode
          beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    Check(finished && ends == 1 && errors == 0 && end_index == 19,
          "native file synthesis completes without an error");
    NSDictionary* info =
        [NSFileManager.defaultManager attributesOfItemAtPath:output.path
                                                       error:nil];
    Check([[info objectForKey:NSFileSize] unsignedLongLongValue] > 64,
          "native synthesizer produced an audio file");
    Check(callbacks_on_main,
          "native callbacks remain on their original thread");
    const int word_count = words;
    [synthesizer stopSpeaking];
    [synthesizer speechSynthesizer:synthesizer
                     willSpeakWord:NSMakeRange(0, 6)
                          ofString:@"Legacy speech test."];
    [synthesizer speechSynthesizer:synthesizer didFinishSpeaking:YES];
    Check(
        words == word_count && ends == 1,
        "late callbacks after cancellation cannot complete another utterance");
    [NSFileManager.defaultManager removeItemAtPath:directory_path error:nil];
  }
  std::printf("%d speech checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}

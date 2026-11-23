// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_SPEECH_H_
#define LEGACY_APPLE_SPEECH_H_

#import <AppKit/AppKit.h>

namespace chromium_legacy {
enum class SpeechEvent { kStart, kEnd, kWord, kError };
using SpeechEventHandler = void (^)(SpeechEvent, NSRange, NSString*);

inline bool ForceLegacySpeechForTests() {
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) && \
    __MAC_OS_X_VERSION_MIN_REQUIRED < 101400
  return true;
#else
  return false;
#endif
}

inline NSArray<NSString*>* LegacySpeechVoiceIdentifiers() {
  NSMutableArray<NSString*>* identifiers =
      [NSSpeechSynthesizer.availableVoices mutableCopy];
  NSString* default_voice = NSSpeechSynthesizer.defaultVoice;
  if (default_voice) {
    [identifiers removeObject:default_voice];
    [identifiers insertObject:default_voice atIndex:0];
  }
  return identifiers;
}
}  // namespace chromium_legacy

// A single utterance owns its native synthesizer and text, as in Chromium's
// original NSSpeechSynthesizer backend. Cancellation detaches callbacks before
// asking the OS to stop, so late events cannot complete a replacement
// utterance.
@interface ChromiumLegacySpeechSynthesizer
    : NSSpeechSynthesizer <NSSpeechSynthesizerDelegate>
- (instancetype)initWithText:(NSString*)text
                       voice:(NSString*)voice
                        rate:(double)rate
                       pitch:(double)pitch
                      volume:(double)volume
                     handler:(chromium_legacy::SpeechEventHandler)handler;
// A nil URL speaks normally; a file URL uses the native file output API.
- (BOOL)startAtURL:(NSURL*)url;
@end

#endif  // LEGACY_APPLE_SPEECH_H_

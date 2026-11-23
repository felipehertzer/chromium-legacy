// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import "legacy/apple/speech.h"

@implementation ChromiumLegacySpeechSynthesizer {
  NSString* _text;
  chromium_legacy::SpeechEventHandler _handler;
  BOOL _started;
  BOOL _finished;
}

- (instancetype)initWithText:(NSString*)text
                       voice:(NSString*)voice
                        rate:(double)rate
                       pitch:(double)pitch
                      volume:(double)volume
                     handler:(chromium_legacy::SpeechEventHandler)handler {
  if ((self = [super initWithVoice:nil])) {
    _text = [text copy];
    _handler = [handler copy];
    self.delegate = self;
    if (voice.length) {
      [self setVoice:voice];
    }
    // Preserve Chromium's pre-AVSpeech parameter mapping (M110).
    if (rate >= 0) {
      [self setObject:@(static_cast<int>(rate * 200))
          forProperty:NSSpeechRateProperty
                error:nil];
    }
    if (pitch >= 0) {
      NSNumber* default_pitch =
          [self objectForProperty:NSSpeechPitchBaseProperty error:nil];
      const int baseline = default_pitch ? default_pitch.intValue : 48;
      [self setObject:@(static_cast<int>(baseline * (0.5 * pitch + 0.5)))
          forProperty:NSSpeechPitchBaseProperty
                error:nil];
    }
    if (volume >= 0) {
      [self setObject:@(volume) forProperty:NSSpeechVolumeProperty error:nil];
    }
  }
  return self;
}

- (BOOL)startAtURL:(NSURL*)url {
  if (_started || !_text) {
    return NO;
  }
  _started = YES;
  const BOOL success = url ? [super startSpeakingString:_text toURL:url]
                           : [super startSpeakingString:_text];
  if (success && _handler) {
    _handler(chromium_legacy::SpeechEvent::kStart, NSMakeRange(0, 0), nil);
  }
  return success;
}

- (void)stopSpeaking {
  _handler = nil;
  self.delegate = nil;
  [super stopSpeaking];
}

- (void)speechSynthesizer:(NSSpeechSynthesizer*)sender
        didFinishSpeaking:(BOOL)finished {
  (void)finished;
  if (sender != self || _finished) {
    return;
  }
  _finished = YES;
  if (_handler) {
    _handler(chromium_legacy::SpeechEvent::kEnd, NSMakeRange(_text.length, 0),
             nil);
  }
}

- (void)speechSynthesizer:(NSSpeechSynthesizer*)sender
            willSpeakWord:(NSRange)range
                 ofString:(NSString*)string {
  if (sender != self || _finished || range.location > string.length ||
      range.length == 0 || range.length > string.length - range.location) {
    return;
  }
  if (_handler) {
    _handler(chromium_legacy::SpeechEvent::kWord, range, nil);
  }
}

- (void)speechSynthesizer:(NSSpeechSynthesizer*)sender
    didEncounterErrorAtIndex:(NSUInteger)index
                    ofString:(NSString*)string
                     message:(NSString*)message {
  if (sender != self || _finished || index > string.length) {
    return;
  }
  _finished = YES;
  if (_handler) {
    _handler(chromium_legacy::SpeechEvent::kError, NSMakeRange(index, 0),
             message);
  }
}
@end

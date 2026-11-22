// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_WEAK_KEY_MAP_H_
#define LEGACY_APPLE_WEAK_KEY_MAP_H_
#import <Foundation/Foundation.h>

// Small weak-key/strong-value map for Lion, whose NSMapTable only supports
// non-retained (not ARC-zeroing) weak keys. Not intended for concurrent access.
@interface ChromiumLegacyWeakKeyMap : NSObject
- (id)objectForKey:(id)key;
- (void)setObject:(id)object forKey:(id)key;
- (void)removeObjectForKey:(id)key;
@end
#endif  // LEGACY_APPLE_WEAK_KEY_MAP_H_

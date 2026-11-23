// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include "legacy/apple/weak_key_map.h"

@interface ChromiumLegacyWeakKeyEntry : NSObject
@property(weak) id key;
@property(strong) id value;
@end
@implementation ChromiumLegacyWeakKeyEntry
@synthesize key = _key;
@synthesize value = _value;
@end

@implementation ChromiumLegacyWeakKeyMap {
  NSMutableArray<ChromiumLegacyWeakKeyEntry*>* _entries;
}
- (instancetype)init {
  if ((self = [super init])) {
    _entries = [[NSMutableArray alloc] init];
  }
  return self;
}
- (ChromiumLegacyWeakKeyEntry*)entryForKey:(id)key {
  ChromiumLegacyWeakKeyEntry* result = nil;
  // Prune expired keys without reading dangling object pointers. A snapshot
  // permits removal during traversal; values are released when pruned.
  for (ChromiumLegacyWeakKeyEntry* entry in [_entries copy]) {
    id candidate = entry.key;
    if (!candidate) {
      [_entries removeObjectIdenticalTo:entry];
    } else if (key && (candidate == key || [candidate isEqual:key])) {
      result = entry;
    }
  }
  return result;
}
- (id)objectForKey:(id)key {
  return [self entryForKey:key].value;
}
- (void)setObject:(id)object forKey:(id)key {
  if (!key) {
    return;
  }
  if (!object) {
    [self removeObjectForKey:key];
    return;
  }
  ChromiumLegacyWeakKeyEntry* entry = [self entryForKey:key];
  if (!entry) {
    entry = [[ChromiumLegacyWeakKeyEntry alloc] init];
    entry.key = key;
    [_entries addObject:entry];
  }
  entry.value = object;
}
- (void)removeObjectForKey:(id)key {
  ChromiumLegacyWeakKeyEntry* entry = [self entryForKey:key];
  if (entry) {
    [_entries removeObjectIdenticalTo:entry];
  }
}
@end

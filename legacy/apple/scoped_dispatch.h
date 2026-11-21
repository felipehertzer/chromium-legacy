// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_SCOPED_DISPATCH_H_
#define LEGACY_APPLE_SCOPED_DISPATCH_H_
#include <dispatch/dispatch.h>

namespace chromium_legacy {
// Adopt a newly created dispatch object. ARC owns Objective-C dispatch objects;
// before 10.8 the corresponding C reference must be released explicitly.
template <typename T>
class ScopedDispatchObject {
 public:
  explicit ScopedDispatchObject(T value = nullptr) : value_(value) {}
  ScopedDispatchObject(const ScopedDispatchObject&) = delete;
  ScopedDispatchObject& operator=(const ScopedDispatchObject&) = delete;
  ~ScopedDispatchObject() {
#if !OS_OBJECT_USE_OBJC
    if (value_) {
      dispatch_release(value_);
    }
#endif
  }
  T get() const { return value_; }
  explicit operator bool() const { return value_ != nullptr; }
  void reset(T value = nullptr) {
#if OS_OBJECT_USE_OBJC
    value_ = value;
#else
    T previous = value_;
    value_ = value;
    if (previous) {
      dispatch_release(previous);
    }
#endif
  }

 private:
  T value_;
};
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_SCOPED_DISPATCH_H_

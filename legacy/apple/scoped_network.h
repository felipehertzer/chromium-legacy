// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef LEGACY_APPLE_SCOPED_NETWORK_H_
#define LEGACY_APPLE_SCOPED_NETWORK_H_

#import <Network/Network.h>

namespace chromium_legacy {
// Adopt a Network.framework create/copy result. The SDK uses C references for
// Lion deployment targets and ARC objects for modern targets. Copies retain
// ownership so a posted task can outlive the owner that scheduled it.
template <typename T>
class ScopedNetworkObject {
 public:
  explicit ScopedNetworkObject(T value = nullptr) : value_(value) {}
  ScopedNetworkObject(const ScopedNetworkObject& other) : value_(other.value_) {
    Retain(value_);
  }
  ScopedNetworkObject& operator=(const ScopedNetworkObject& other) {
    if (this != &other) {
      Retain(other.value_);
      Release(value_);
      value_ = other.value_;
    }
    return *this;
  }
  ScopedNetworkObject(ScopedNetworkObject&& other) : value_(other.value_) {
    other.value_ = nullptr;
  }
  ScopedNetworkObject& operator=(ScopedNetworkObject&& other) {
    if (this != &other) {
      Release(value_);
      value_ = other.value_;
      other.value_ = nullptr;
    }
    return *this;
  }
  ~ScopedNetworkObject() { Release(value_); }
  T get() const { return value_; }
  explicit operator bool() const { return value_ != nullptr; }
  void reset(T value = nullptr) {
    Release(value_);
    value_ = value;
  }

 private:
  static void Retain(T value) {
#if !OS_OBJECT_USE_OBJC
    if (@available(macOS 10.14, *)) {
      if (value) {
        nw_retain(value);
      }
    }
#else
    (void)value;
#endif
  }
  static void Release(T value) {
#if !OS_OBJECT_USE_OBJC
    if (@available(macOS 10.14, *)) {
      if (value) {
        nw_release(value);
      }
    }
#else
    (void)value;
#endif
  }
  T value_;
};
}  // namespace chromium_legacy
#endif  // LEGACY_APPLE_SCOPED_NETWORK_H_

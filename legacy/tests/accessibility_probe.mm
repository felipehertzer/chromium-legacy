// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <AppKit/AppKit.h>

#include <iostream>
#include <string_view>
#include <vector>

#include "base/apple/foundation_util.h"
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "ui/accessibility/accessibility_features.h"
#include "ui/accessibility/ax_action_data.h"
#include "ui/accessibility/ax_node_data.h"
#include "ui/accessibility/platform/ax_platform.h"
#include "ui/accessibility/platform/ax_platform_node.h"
#include "ui/accessibility/platform/ax_platform_node_base.h"
#include "ui/accessibility/platform/ax_platform_node_cocoa.h"
#include "ui/accessibility/platform/ax_platform_node_delegate.h"
#include "ui/accessibility/platform/ax_unique_id.h"
#include "ui/accessibility/platform/inspect/ax_element_wrapper_mac.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool ok, std::string_view description) {
  ++checks;
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << description << "\n";
  }
}
class PlatformDelegate : public ui::AXPlatform::Delegate {
 public:
  ui::AXMode GetAccessibilityMode() override {
    return ui::AXMode(ui::AXMode::kNativeAPIs);
  }
};
class NodeDelegate : public ui::AXPlatformNodeDelegate {
 public:
  const ui::AXNodeData& GetData() const override { return data; }
  ui::AXPlatformNodeId GetUniqueId() const override { return unique_id_.Get(); }
  bool AccessibilityPerformAction(const ui::AXActionData& action) override {
    actions.push_back(action.action);
    return true;
  }
  bool IsReadOnlyOrDisabled() const override {
    return data.GetRestriction() != ax::mojom::Restriction::kNone;
  }
  gfx::NativeViewAccessible GetParent() const override { return parent; }
  size_t GetChildCount() const override { return children.size(); }
  gfx::NativeViewAccessible ChildAtIndex(size_t index) const override {
    return children.at(index);
  }
  gfx::NativeViewAccessible GetNativeViewAccessible() override {
    return node ? node->GetNativeViewAccessible() : gfx::NativeViewAccessible();
  }
  ~NodeDelegate() override {
    if (node) {
      auto* cocoa = base::apple::ObjCCast<AXPlatformNodeCocoa>(
          node->GetNativeViewAccessible().Get());
      [cocoa detachAndNotifyDestroyed:NO];
      // Destroy while the delegate's unique ID and other fields are alive.
      node.reset();
    }
  }
  void Create(ax::mojom::Role role) {
    data.id = unique_id_.Get().value();
    data.role = role;
    node = ui::AXPlatformNode::Create(*this);
  }
  AXPlatformNodeCocoa* Cocoa() {
    return base::apple::ObjCCast<AXPlatformNodeCocoa>(
        node->GetNativeViewAccessible().Get());
  }
  ui::AXNodeData data;
  gfx::NativeViewAccessible parent;
  std::vector<gfx::NativeViewAccessible> children;
  std::vector<ax::mojom::Action> actions;
  ui::AXPlatformNode::Pointer node;

 private:
  ui::AXUniqueId unique_id_ = ui::AXUniqueId::Create();
};
}  // namespace

int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  // Attempting to force the experimental migration must remain safe in a
  // deployment targeting Lion, which has no NSAccessibilityElement defaults.
  base::FeatureList::InitInstance("MacAccessibilityAPIMigration", "");
  PlatformDelegate platform_delegate;
  ui::AXPlatform platform(platform_delegate);
  @autoreleasepool {
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101000
    Check(base::FeatureList::IsEnabled(features::kMacAccessibilityAPIMigration),
          "experimental feature flag was actually forced on");
    Check(!features::IsMacAccessibilityAPIMigrationEnabled(),
          "Lion build retains attribute-based API when feature is forced");
#endif
    size_t initial_count = ui::AXPlatformNodeBase::GetInstanceCount();
    {
      NodeDelegate root;
      root.Create(ax::mojom::Role::kGroup);
      NodeDelegate child;
      child.Create(ax::mojom::Role::kButton);
      child.data.SetName("Legacy button");
      child.data.AddAction(ax::mojom::Action::kDoDefault);
      child.data.AddState(ax::mojom::State::kFocusable);
      child.parent = root.node->GetNativeViewAccessible();
      root.children.push_back(child.node->GetNativeViewAccessible());
      AXPlatformNodeCocoa* cocoa = child.Cocoa();
      Check(cocoa != nil && [cocoa instanceActive],
            "real Chromium node created");
      Check([[cocoa accessibilityAttributeValue:NSAccessibilityRoleAttribute]
                isEqual:NSAccessibilityButtonRole],
            "legacy role lookup");
      Check([[cocoa accessibilityRole] isEqual:NSAccessibilityButtonRole],
            "internal role accessor");
      Check([[cocoa accessibilityAttributeValue:NSAccessibilityTitleAttribute]
                isEqual:@"Legacy button"] ||
                [[cocoa accessibilityAttributeValue:
                            NSAccessibilityDescriptionAttribute]
                    isEqual:@"Legacy button"],
            "button name remains accessible");
      child.data.AddStringAttribute(ax::mojom::StringAttribute::kDescription,
                                    "ARIA help text");
      child.data.AddIntAttribute(
          ax::mojom::IntAttribute::kDescriptionFrom,
          static_cast<int>(ax::mojom::DescriptionFrom::kAriaDescription));
      if (@available(macOS 11.0, *)) {
        Check([cocoa accessibilityHelp] == nil,
              "modern ARIA descriptions avoid duplicate help");
        Check([cocoa accessibilityCustomContent].count == 1,
              "modern ARIA description remains custom content");
      } else {
        Check([[cocoa accessibilityHelp] isEqual:@"ARIA help text"],
              "older systems retain ARIA description as help");
        Check([cocoa accessibilityCustomContent] == nil,
              "older systems avoid unavailable custom-content class");
      }
      child.data.AddStringAttribute(ax::mojom::StringAttribute::kHtmlTag,
                                    "fieldset");
      Check([[cocoa accessibilityHelp] isEqual:@"ARIA help text"],
            "fieldset keeps accessible description");
      Check([cocoa accessibilityCustomContent] == nil,
            "fieldset avoids duplicate custom content");
      Check(![cocoa accessibilityIsIgnored], "visible button is exposed");
      Check([cocoa respondsToSelector:@selector(accessibilityAttributeValue:)],
            "attribute protocol is advertised");
      Check([[cocoa accessibilityActionNames]
                containsObject:NSAccessibilityPressAction],
            "press advertised");
      [cocoa accessibilityPerformAction:NSAccessibilityPressAction];
      Check(child.actions.size() == 1 &&
                child.actions.back() == ax::mojom::Action::kDoDefault,
            "attribute action reaches actual Chromium delegate");
      Check([cocoa accessibilityPerformPress] && child.actions.size() == 2,
            "internal action accessor reaches delegate");
      Check(![cocoa accessibilityPerformIncrement] && child.actions.size() == 2,
            "unsupported action is rejected");
      Check([cocoa accessibilityParent] == root.Cocoa(),
            "native parent lookup");
      NSArray* children = [root.Cocoa()
          accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
      Check(children.count == 1 && [children objectAtIndex:0] == cocoa,
            "native child traversal");
      Check(ui::AXElementWrapper(cocoa).IsValidElement(),
            "inspector recognizes Chromium NSObject node");
      Check(ui::AXPlatformNode::FromNativeViewAccessible(
                child.node->GetNativeViewAccessible()) == child.node.get(),
            "owned native wrapper round trip");
      child.data.role = ax::mojom::Role::kTextField;
      child.data.AddState(ax::mojom::State::kRequired);
      Check([[cocoa accessibilityAttributeNames] containsObject:@"AXRequired"],
            "required attribute remains available before public constant");
      Check([[cocoa accessibilityAttributeValue:@"AXRequired"] boolValue],
            "required value lookup");
      child.data.SetRestriction(ax::mojom::Restriction::kDisabled);
      Check(![cocoa isAccessibilityEnabled], "disabled state is exposed");
      Check(![cocoa isAccessibilitySelectorAllowed:@selector(
                                                       setAccessibilityValue:)],
            "disabled node rejects value setter");
      child.data.SetRestriction(ax::mojom::Restriction::kReadOnly);
      Check(![cocoa isAccessibilitySelectorAllowed:@selector(
                                                       setAccessibilityValue:)],
            "read-only node rejects value setter");
      child.data.role = ax::mojom::Role::kSlider;
      child.data.SetRestriction(ax::mojom::Restriction::kNone);
      Check(![cocoa isAccessibilitySelectorAllowed:@selector(
                                                       setAccessibilityValue:)],
            "slider retains Chromium increment/decrement policy");
      child.data.role = ax::mojom::Role::kColumnHeader;
      child.data.AddIntAttribute(
          ax::mojom::IntAttribute::kSortDirection,
          static_cast<int>(ax::mojom::SortDirection::kAscending));
      Check([cocoa accessibilitySortDirection] == 1,
            "sort accessor preserves integer protocol ABI");
      gfx::NativeViewAccessible retained =
          child.node->GetNativeViewAccessible();
      [cocoa detachAndNotifyDestroyed:NO];
      child.node.reset();
      Check(retained.Get() == cocoa && ![cocoa instanceActive],
            "retained wrapper survives node destruction in detached state");
      Check(![cocoa accessibilityPerformPress], "detached node rejects action");
      Check(![cocoa isAccessibilitySelectorAllowed:@selector(
                                                       setAccessibilityValue:)],
            "detached node rejects selector");
      root.children.clear();
    }
    Check(ui::AXPlatformNodeBase::GetInstanceCount() == initial_count,
          "all Chromium platform nodes released");
  }
  std::cout << checks << " accessibility integration checks, " << failures
            << " failures\n";
  return failures ? 1 : 0;
}

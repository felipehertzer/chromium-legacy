// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <iostream>
#include <string_view>
#include "base/at_exit.h"
#include "base/command_line.h"
#include "content/common/mac/attributed_string_type_converters.mm"

namespace {
int checks = 0;
int failures = 0;
void Check(bool ok, std::string_view message) {
  ++checks;
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << message << "\n";
  }
}
using Decode =
    mojo::TypeConverter<CFAttributedStringRef, ui::mojom::AttributedStringPtr>;
using Encode =
    mojo::TypeConverter<ui::mojom::AttributedStringPtr, CFAttributedStringRef>;
}  // namespace
int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  @autoreleasepool {
    auto input = ui::mojom::AttributedString::New();
    input->string = u"Olá \U0001f600";
    input->attributes.push_back(ui::mojom::FontAttribute::New(
        u"Helvetica", 16, gfx::Range(0, input->string.size())));
    input->attributes.push_back(ui::mojom::FontAttribute::New(
        u"Helvetica", 30,
        gfx::Range(input->string.size() + 1, input->string.size() + 5)));
    CFAttributedStringRef decoded = Decode::Convert(input);
    // Read the borrowed return after the converter's locals were destroyed.
    Check(decoded && CFAttributedStringGetLength(decoded) ==
                         static_cast<CFIndex>(input->string.size()),
          "borrowed attributed string remains alive in its autorelease pool");
    auto encoded = Encode::Convert(decoded);
    Check(encoded->string == input->string, "UTF-16 text round trip");
    Check(encoded->attributes.size() == 1,
          "invalid attribute range is ignored");
    if (encoded->attributes.size() == 1) {
      const auto& font = encoded->attributes.front();
      Check(!font->font_name.empty(), "real native font name");
      Check(font->font_point_size == 16, "font point size round trip");
      Check(font->effective_range == gfx::Range(0, input->string.size()),
            "font range covers the complete string");
    }
    input->string = u"fallback";
    input->attributes.clear();
    input->attributes.push_back(
        ui::mojom::FontAttribute::New(u"org.chromium.legacy.nonexistent-font",
                                      19, gfx::Range(0, input->string.size())));
    auto fallback = Encode::Convert(Decode::Convert(input));
    Check(fallback->attributes.size() == 1 &&
              !fallback->attributes.front()->font_name.empty() &&
              fallback->attributes.front()->font_point_size == 19,
          "missing fonts retain the system font fallback and requested size");
    auto empty = ui::mojom::AttributedString::New();
    CFAttributedStringRef empty_decoded = Decode::Convert(empty);
    Check(empty_decoded && CFAttributedStringGetLength(empty_decoded) == 0,
          "empty attributed string");
    Check(Encode::Convert(nullptr)->string.empty(), "nil native string");
  }
  std::cout << checks << " attributed string checks, " << failures
            << " failures\n";
  return failures ? 1 : 0;
}

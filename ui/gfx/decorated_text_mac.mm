// Copyright 2018 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "ui/gfx/decorated_text_mac.h"

#import <Cocoa/Cocoa.h>
#include <CoreText/CoreText.h>

#include "base/apple/bridging.h"
#include "base/apple/foundation_util.h"
#include "base/strings/sys_string_conversions.h"
#include "ui/gfx/decorated_text.h"

namespace gfx {

NSAttributedString* GetAttributedStringFromDecoratedText(
    const DecoratedText& decorated_text) {
  NSMutableAttributedString* str = [[NSMutableAttributedString alloc]
      initWithString:base::SysUTF16ToNSString(decorated_text.text)];
  [str beginEditing];

  NSValue* const line_style =
      @(NSUnderlineStyleSingle | NSUnderlinePatternSolid);

  for (const auto& attribute : decorated_text.attributes) {
    DCHECK(!attribute.range.is_reversed());
    DCHECK_LE(attribute.range.end(), str.length);

    NSMutableDictionary* attrs = [NSMutableDictionary dictionary];
    NSRange range = attribute.range.ToNSRange();

    CTFontRef font = attribute.font.GetCTFont();
    if (font) {
      [attrs setObject:base::apple::CFToNSPtrCast(font) forKey:NSFontAttributeName];
    }

    // NSFont does not have underline as an attribute. Hence handle it
    // separately.
    const bool underline = attribute.font.GetStyle() & gfx::Font::UNDERLINE;
    if (underline) {
      [attrs setObject:line_style forKey:NSUnderlineStyleAttributeName];
    }

    if (attribute.strike) {
      [attrs setObject:line_style forKey:NSStrikethroughStyleAttributeName];
    }

    [str setAttributes:attrs range:range];
  }

  [str endEditing];
  return str;
}

}  // namespace gfx

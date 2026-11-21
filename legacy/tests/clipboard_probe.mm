// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

#include <string>

#include "ui/base/clipboard/clipboard_constants.h"
#include "ui/base/clipboard/clipboard_format_type.h"
#include "ui/base/clipboard/clipboard_util_mac.h"
#include "ui/base/clipboard/url_file_parser.h"

namespace {
int checks = 0;
int failures = 0;
void Check(bool value, const char* label) {
  ++checks;
  if (!value) {
    ++failures;
    fprintf(stderr, "FAILED: %s\n", label);
  }
}
}  // namespace

int main() {
  @autoreleasepool {
    auto owner = base::MakeRefCounted<ui::UniquePasteboard>();
    NSPasteboard* pb = owner->get();
    Check(pb != nil, "isolated pasteboard created");
    NSArray* items = ui::clipboard_util::PasteboardItemsFromUrls(
        @[
          @"https://example.invalid/first", @"https://example.invalid/second"
        ],
        @[ @"First title", @"Second title" ]);
    Check(items.count == 2, "two URL pasteboard items");
    [pb writeObjects:items];
    NSArray<URLAndTitle*>* result =
        ui::clipboard_util::URLsAndTitlesFromPasteboard(pb, false);
    Check(result.count == 2, "Safari URL/title representation read");
    Check([result.firstObject.URL
              isEqualToString:@"https://example.invalid/first"] &&
              [result.firstObject.title isEqualToString:@"First title"],
          "URL/title preserved");

    NSPasteboardItem* item = [[NSPasteboardItem alloc] init];
    [item setString:@"https://example.invalid/standard" forType:@"public.url"];
    [item setString:@"A standard URL" forType:ui::kUTTypeUrlName];
    [pb clearContents];
    [pb writeObjects:@[ item ]];
    result = ui::clipboard_util::URLsAndTitlesFromPasteboard(pb, false);
    Check(result.count == 1 &&
              [result.firstObject.title isEqualToString:@"A standard URL"],
          "standard URL/title UTI representation read");

    char folder[] = "/tmp/chromium-legacy-clipboard.XXXXXX";
    char* directory = mkdtemp(folder);
    Check(directory != nullptr, "temporary file directory created");
    if (directory) {
      NSString* path = [[NSString stringWithUTF8String:directory]
          stringByAppendingPathComponent:@"Shortcut.url"];
      NSString* contents =
          @"[InternetShortcut]\r\nURL=https://example.invalid/shortcut\r\n";
      Check([contents writeToFile:path
                       atomically:YES
                         encoding:NSWindowsCP1252StringEncoding
                            error:nil],
            "Windows URL shortcut written");
      item = [[NSPasteboardItem alloc] init];
      [item setString:[NSURL fileURLWithPath:path].absoluteString
              forType:@"public.file-url"];
      [pb clearContents];
      [pb writeObjects:@[ item ]];
      result = ui::clipboard_util::URLsAndTitlesFromPasteboard(pb, false);
      Check(result.count == 1 &&
                [result.firstObject.URL
                    isEqualToString:@"https://example.invalid/shortcut"],
            "URL shortcut type and contents recognized");
      auto file_info = ui::clipboard_util::FilesFromPasteboard(pb);
      Check(file_info.size() == 1 &&
                file_info.front().path.value() == path.UTF8String,
            "file URL read without changing its path");

      NSString* webloc = [[NSString stringWithUTF8String:directory]
          stringByAppendingPathComponent:@"Web title.webloc"];
      [@{@"URL" : @"https://example.invalid/webloc"} writeToFile:webloc
                                                      atomically:YES];
      item = [[NSPasteboardItem alloc] init];
      [item setString:[NSURL fileURLWithPath:webloc].absoluteString
              forType:@"public.file-url"];
      [item setString:@"https://example.invalid/webloc" forType:@"public.url"];
      [pb clearContents];
      [pb writeObjects:@[ item ]];
      result = ui::clipboard_util::URLsAndTitlesFromPasteboard(pb, false);
      Check(result.count == 1 &&
                [result.firstObject.title isEqualToString:@"Web title"],
            "webloc conformance and filename title recognized");
      std::string oversized(
          ui::clipboard_util::internal::kMaximumParsableFileSize + 1, 'x');
      NSData* data = [NSData dataWithBytes:oversized.data()
                                    length:oversized.size()];
      [data writeToFile:path atomically:YES];
      item = [[NSPasteboardItem alloc] init];
      [item setString:[NSURL fileURLWithPath:path].absoluteString
              forType:@"public.file-url"];
      [pb clearContents];
      [pb writeObjects:@[ item ]];
      result = ui::clipboard_util::URLsAndTitlesFromPasteboard(pb, false);
      Check(result.count == 0, "oversized shortcut rejected");
      [[NSFileManager defaultManager]
          removeItemAtPath:[NSString stringWithUTF8String:directory]
                     error:nil];
    }
    Check([ui::ClipboardFormatType::UrlType().ToNSString()
              isEqualToString:@"public.url"] &&
              [ui::ClipboardFormatType::FilenamesType().ToNSString()
                  isEqualToString:@"public.file-url"] &&
              [ui::ClipboardFormatType::SvgType().ToNSString()
                  isEqualToString:@"public.svg-image"],
          "canonical clipboard identifiers preserved");
  }
  printf("%d clipboard checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}

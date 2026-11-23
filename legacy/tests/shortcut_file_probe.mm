// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <iostream>
#include <string_view>
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "chrome/browser/shortcuts/chrome_webloc_file.mm"

namespace {
int checks = 0;
int failures = 0;
void Check(bool success, std::string_view message) {
  ++checks;
  if (!success) {
    ++failures;
    std::cerr << "FAIL: " << message << "\n";
  }
}
bool WritePlist(id value, const base::FilePath& path) {
  NSData* data = [NSPropertyListSerialization
      dataWithPropertyList:value
                    format:NSPropertyListXMLFormat_v1_0
                   options:0
                     error:nil];
  return [data writeToURL:base::apple::FilePathToNSURL(path)
                  options:NSDataWritingAtomic
                    error:nil];
}
}  // namespace
int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  @autoreleasepool {
    base::ScopedTempDir directory;
    if (!directory.CreateUniqueTempDir())
      return 1;
    const base::FilePath path =
        directory.GetPath().AppendASCII("owned.crwebloc");
    auto profile =
        base::SafeBaseName::Create(base::FilePath::FromUTF8Unsafe("Perfil 😀"));
    Check(profile.has_value(), "Unicode profile basename is valid");
    if (!profile)
      return 1;
    const GURL url("https://example.test/path?q=caf%C3%A9#fragment");
    shortcuts::ChromeWeblocFile shortcut(url, *profile);
    Check(shortcut.SaveToFile(path),
          "shortcut saves to an owned temporary file");
    auto loaded = shortcuts::ChromeWeblocFile::LoadFromFile(path);
    Check(loaded && loaded->target_url() == url &&
              loaded->profile_path_name().path() == profile->path(),
          "shortcut URL and Unicode profile round trip");
    const GURL replacement("https://example.test/replaced");
    Check(shortcuts::ChromeWeblocFile(replacement, *profile).SaveToFile(path),
          "shortcut replaces an existing file through the atomic writer");
    loaded = shortcuts::ChromeWeblocFile::LoadFromFile(path);
    Check(loaded && loaded->target_url() == replacement,
          "replacement file remains complete and readable");
    NSArray* invalid = @[
      @{@"URL" : @42,
        @"CrProfile" : @"Default"},
      @{@"URL" : @"https://example.test",
        @"CrProfile" : @42},
      @{@"URL" : @"https://example.test", @"CrProfile" : @".."},
      @{@"URL" : @"://invalid", @"CrProfile" : @"Default"},
      @{@"URL" : @"https://example.test"},
      @{},
      @[ @"not a dictionary" ],
    ];
    for (id value in invalid) {
      if (!WritePlist(value, path))
        return 1;
      Check(!shortcuts::ChromeWeblocFile::LoadFromFile(path),
            "malformed shortcut fields/root are rejected without unsafe "
            "messages");
    }
    if (!WritePlist(
            @{@"URL" : @"https://example.test", @"CrProfile" : @"../Default"},
            path))
      return 1;
    auto normalized = shortcuts::ChromeWeblocFile::LoadFromFile(path);
    Check(normalized && normalized->profile_path_name().path() ==
                            base::FilePath("Default"),
          "profile paths retain their existing safe basename normalization");
    if (!base::WriteFile(path, "not a property list"))
      return 1;
    Check(!shortcuts::ChromeWeblocFile::LoadFromFile(path),
          "malformed property-list data is rejected");
    Check(!shortcuts::ChromeWeblocFile::LoadFromFile(
              directory.GetPath().AppendASCII("missing.crwebloc")),
          "missing shortcut is rejected");
    Check(!shortcut.SaveToFile(directory.GetPath()
                                   .AppendASCII("missing-parent")
                                   .AppendASCII("file.crwebloc")),
          "failed atomic write reports failure without creating parent "
          "directories");
  }
  std::cout << checks << " shortcut file checks, " << failures << " failures\n";
  return failures ? 1 : 0;
}

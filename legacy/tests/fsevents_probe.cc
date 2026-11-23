// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <iostream>
#include <vector>

#include "base/apple/scoped_cftyperef.h"
#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/run_loop.h"
#include "base/task/sequenced_task_runner.h"
#include "base/task/single_thread_task_executor.h"
#include "base/time/time.h"
#include "content/browser/file_system_access/file_path_watcher/file_path_watcher_fsevents.h"
#include "legacy/apple/fsevents.h"

namespace {
using Watcher = content::FilePathWatcher;
using ChangeType = Watcher::ChangeType;
using Tracker = content::FilePathWatcherFSEventsChangeTracker;
int checks = 0;
int failures = 0;
void Check(bool ok, const char* name) {
  ++checks;
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << name << '\n';
  }
}
template <typename Predicate>
bool WaitFor(Predicate condition) {
  const auto deadline = base::TimeTicks::Now() + base::Seconds(5);
  do {
    if (condition()) {
      return true;
    }
    base::RunLoop loop;
    base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
        FROM_HERE, loop.QuitClosure(), base::Milliseconds(20));
    loop.Run();
  } while (base::TimeTicks::Now() < deadline);
  return condition();
}
}  // namespace

int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  base::SingleThreadTaskExecutor executor;

  auto plain = chromium_legacy::ReadFSEventsPath(CFSTR("/owned/plain"));
  Check(
      plain.path && CFEqual(plain.path, CFSTR("/owned/plain")) && !plain.inode,
      "old streams preserve string paths without fabricating file IDs");
  base::apple::ScopedCFTypeRef<CFMutableDictionaryRef> dictionary(
      CFDictionaryCreateMutable(nullptr, 0, &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks));
  CFDictionarySetValue(dictionary.get(), kFSEventStreamEventExtendedDataPathKey,
                       CFSTR("/owned/extended"));
  int64_t inode_value = 123456789;
  base::apple::ScopedCFTypeRef<CFNumberRef> inode(
      CFNumberCreate(nullptr, kCFNumberSInt64Type, &inode_value));
  CFDictionarySetValue(dictionary.get(), kFSEventStreamEventExtendedFileIDKey,
                       inode.get());
  auto extended = chromium_legacy::ReadFSEventsPath(dictionary.get());
  Check(extended.path && CFEqual(extended.path, CFSTR("/owned/extended")) &&
            extended.inode == 123456789,
        "extended streams retain the OS path and inode");
  CFDictionarySetValue(dictionary.get(), kFSEventStreamEventExtendedFileIDKey,
                       CFSTR("wrong type"));
  Check(!chromium_legacy::ReadFSEventsPath(dictionary.get()).inode,
        "invalid inode types remain absent");
  CFDictionarySetValue(dictionary.get(), kFSEventStreamEventExtendedDataPathKey,
                       kCFBooleanTrue);
  Check(!chromium_legacy::ReadFSEventsPath(dictionary.get()).path &&
            !chromium_legacy::ReadFSEventsPath(kCFBooleanTrue).path &&
            !chromium_legacy::ReadFSEventsPath(nullptr).path,
        "malformed callback data does not become a path");

  base::ScopedTempDir temporary;
  if (!temporary.CreateUniqueTempDir()) {
    return 1;
  }
  const auto root = base::MakeAbsoluteFilePath(temporary.GetPath());
  const auto first = root.AppendASCII("first");
  const auto second = root.AppendASCII("second");
  const auto absent = root.AppendASCII("absent");
  const auto stable = root.AppendASCII("preexisting");
  std::vector<Watcher::ChangeInfo> changes;
  bool callback_error = false;
  auto callback = base::BindRepeating(
      [](std::vector<Watcher::ChangeInfo>* changes, bool* error,
         const Watcher::ChangeInfo& info, const base::FilePath&, bool failed) {
        *error |= failed;
        changes->push_back(info);
      },
      base::Unretained(&changes), base::Unretained(&callback_error));
  auto has = [&](ChangeType type, const base::FilePath& path) {
    for (const auto& change : changes) {
      if (change.change_type == type && change.modified_path == path) {
        return true;
      }
    }
    return false;
  };
  if (!base::WriteFile(second, "existing")) {
    return 1;
  }
  {
    Tracker tracker(callback, root, Watcher::Type::kRecursive, true);
    tracker.DispatchEvents({
        {1,
         {kFSEventStreamEventFlagItemRenamed |
              kFSEventStreamEventFlagItemIsFile,
          absent, std::nullopt}},
        {2,
         {kFSEventStreamEventFlagItemRenamed |
              kFSEventStreamEventFlagItemIsFile,
          second, std::nullopt}},
    });
    Check(
        changes.size() == 2 && has(ChangeType::kDeleted, absent) &&
            has(ChangeType::kCreated, second),
        "unrelated renames without IDs produce separate delete/create events");
    changes.clear();
    tracker.DispatchEvents({
        {3,
         {kFSEventStreamEventFlagItemRenamed |
              kFSEventStreamEventFlagItemIsFile,
          absent, 42}},
        {4,
         {kFSEventStreamEventFlagItemRenamed |
              kFSEventStreamEventFlagItemIsFile,
          second, 42}},
    });
    Check(changes.size() == 1 && has(ChangeType::kMoved, second) &&
              changes[0].moved_from_path == absent,
          "matching OS file IDs retain current move reporting");
  }
  base::DeleteFile(second);
  changes.clear();

  if (!base::WriteFile(stable, "before watching")) {
    return 1;
  }
  content::FilePathWatcherFSEvents watcher;
  const bool started = watcher.WatchWithChangeInfo(
      root, {.type = Watcher::Type::kRecursive, .report_modified_path = true},
      callback, base::DoNothingAs<void(size_t, size_t)>());
  Check(started, "production watcher starts on its owned directory");
  if (started) {
    Check(base::WriteFile(first, "created") &&
              WaitFor([&] { return has(ChangeType::kCreated, first); }),
          "native stream reports file creation");
    changes.clear();
    Check(base::Move(first, second) && WaitFor([&] {
            return has(ChangeType::kMoved, second) ||
                   (has(ChangeType::kDeleted, first) &&
                    has(ChangeType::kCreated, second));
          }),
          "native rename reports a matched move or separate delete/create");
    if (!chromium_legacy::FSEventsExtendedDataFlag()) {
      Check(!has(ChangeType::kMoved, second) &&
                has(ChangeType::kDeleted, first) &&
                has(ChangeType::kCreated, second),
            "legacy stream never invents an inode match");
    }
    changes.clear();
    // Use an established path: FSEvents may coalesce a just-renamed path's
    // rename flag with a subsequent write and report another move-in instead.
    Check(base::WriteFile(stable, "modified contents") &&
              WaitFor([&] { return has(ChangeType::kModified, stable); }),
          "native stream reports content modification");
    changes.clear();
    Check(base::DeleteFile(second) &&
              WaitFor([&] { return has(ChangeType::kDeleted, second); }),
          "native stream reports deletion");
  }
  watcher.Cancel();
  changes.clear();
  base::WriteFile(first, "after cancellation");
  base::RunLoop drain;
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE, drain.QuitClosure(), base::Seconds(1));
  drain.Run();
  Check(changes.empty() && !callback_error,
        "cancellation suppresses callbacks and no stream error occurred");
  std::cout << checks << " FSEvents checks, " << failures << " failures\n";
  return failures ? 1 : 0;
}

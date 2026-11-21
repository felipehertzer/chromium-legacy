// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
use std::collections::HashMap;
use std::fs::{self, File, FileTimes};
use std::io::Write;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::process::Command;
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[derive(Default)]
struct Checks {
    count: usize,
    failures: usize,
}
impl Checks {
    fn check(&mut self, success: bool, description: &str) {
        self.count += 1;
        if !success {
            self.failures += 1;
            eprintln!("FAIL: {description}");
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut checks = Checks::default();
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?;
    checks.check(now.as_secs() > 1_700_000_000, "system clock epoch");
    let start = Instant::now();
    thread::sleep(Duration::from_millis(20));
    checks.check(start.elapsed() >= Duration::from_millis(10), "monotonic clock");

    let state = Arc::new((Mutex::new(false), Condvar::new()));
    let other = state.clone();
    let worker = thread::spawn(move || {
        *other.0.lock().unwrap() = true;
        other.1.notify_one();
    });
    let (ready, timeout) = state
        .1
        .wait_timeout_while(state.0.lock().unwrap(), Duration::from_secs(5), |value| !*value)
        .map_err(|_| "condition variable mutex poisoned")?;
    checks.check(*ready && !timeout.timed_out(), "mutex and condition variable");
    drop(ready);
    worker.join().unwrap();
    let start = Instant::now();
    thread::park_timeout(Duration::from_millis(20));
    checks.check(start.elapsed() >= Duration::from_millis(10), "thread parking");

    // Constructing the randomly seeded hasher exercises the OS CSPRNG path.
    let mut map = HashMap::new();
    map.insert("key", 42);
    checks.check(map.get("key") == Some(&42), "randomly seeded hash map");
    #[repr(align(128))]
    struct Aligned(u8);
    let aligned = Box::new(Aligned(42));
    checks.check(
        (&*aligned as *const Aligned as usize) % 128 == 0 && aligned.0 == 42,
        "aligned allocation",
    );

    let root = std::env::temp_dir().join(format!(
        "chromium-legacy-rust-{}-{}",
        std::process::id(),
        now.as_nanos()
    ));
    // Never remove a pre-existing path, even if a previous run collided.
    fs::create_dir(&root)?;
    let source = root.join("source");
    let nested = source.join("nested");
    let outside = root.join("outside");
    fs::create_dir_all(&nested)?;
    fs::create_dir(&outside)?;
    fs::write(outside.join("keep"), b"outside")?;
    let entry = nested.join("entry");
    let mut file = File::create(&entry)?;
    file.write_all(b"payload")?;
    checks.check(fs::read(&entry)? == b"payload", "file read/write");
    let accessed = file.metadata()?.accessed()?;
    let modified = UNIX_EPOCH + Duration::new(1_700_000_000, 123_456_789);
    file.set_times(FileTimes::new().set_modified(modified))?;
    let metadata = file.metadata()?;
    checks.check(
        metadata.modified()?.duration_since(UNIX_EPOCH)?.as_secs() == 1_700_000_000,
        "file descriptor timestamp update",
    );
    checks.check(metadata.accessed()? == accessed, "omitted access time is preserved");
    file.set_permissions(fs::Permissions::from_mode(0o600))?;
    checks.check(file.metadata()?.permissions().mode() & 0o777 == 0o600, "file permissions");
    drop(file);
    symlink(&outside, source.join("link"))?;
    checks.check(
        Command::new("/bin/sh")
            .args(["-c", "test -f entry"])
            .current_dir(&nested)
            .status()?
            .success(),
        "child process working directory",
    );
    let renamed = root.join("renamed");
    fs::rename(&source, &renamed)?;
    fs::remove_dir_all(&renamed)?;
    checks.check(
        fs::read(outside.join("keep"))? == b"outside",
        "recursive removal preserves symlink targets",
    );
    fs::remove_dir_all(&root)?;
    checks.check(!root.exists(), "test directory cleanup");
    println!("{} Rust runtime checks, {} failures", checks.count, checks.failures);
    if checks.failures != 0 {
        return Err("Rust runtime checks failed".into());
    }
    Ok(())
}

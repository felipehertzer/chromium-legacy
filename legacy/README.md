# Chromium Legacy: current-release port

Experimental work to bring current Chromium to Intel Macs running OS X Lion
10.7 and later. This branch is based on **Chromium 159.0.8154.13**, the Mac
stable version checked on 2026-11-21. It is **not yet a working legacy browser**.

The inherited `master.lion` branch and release `1303823` are retained for
reference. The latest old release contains Chromium 127.0.6494.0; the later
inherited branch contains an unfinished Chromium 129 merge. Neither is used as
the source-version label for this port.

## What is implemented

- A system-version fallback that reads `SystemVersion.plist` when the old kernel
  has no `kern.osproductversion` sysctl. It uses Foundation APIs available on
  Lion, including the original `objectForKey:` dictionary selector.
- Missing VM-detection sysctls no longer abort startup.
- Finder tags are only used on Mavericks 10.9 and later.
- Experimental Intel/Lion build arguments in `legacy/args/lion.gn`.
- Pinned source and dependency references in `legacy/revisions.json` and a
  repeatable inventory of the original legacy changes in `legacy/port-audit.json`.

The standalone production fallback compiles for x86_64 with deployment target
10.7 and passes 17 XML/binary property-list and error-handling checks on the
current host. This does not validate the complete browser or a Lion runtime.

## Run the focused checks

```sh
legacy/test_os_version.sh
python3 -m unittest discover -s legacy/tests -p 'test_*.py' -v
python3 legacy/audit_port.py --output /tmp/chromium-port-audit.json
```

The audit needs the three full commit IDs in `legacy/revisions.json` available
locally. It reads Git trees without downloading Chromium dependencies or file
blobs. Its report compares the old compatibility delta with the **unmodified**
159 upstream tree; it is a review queue, not a count of completed port changes.

The Foundation-only probe deliberately avoids C++ standard-library headers for
its Lion cross-compile. The browser requires a separately ported libc++; the
probe does not establish that current Chromium's C++ or Rust runtimes support
Lion.

## Remaining work

The original Lion patch changes 491 paths. Against the current upstream tree,
366 have changed, 33 were removed, 43 are legacy additions, and 49 still match
the original upstream versions. Each affected subsystem needs review and build
validation. The compatibility forks for Skia, ANGLE, Dawn, SwiftShader, Vulkan
Memory Allocator, WebRTC, libc++, and BoringSSL are recorded as references only;
they have not been rebased onto Chromium 159's dependency revisions.

A full browser build has not been attempted: the current machine has around
53 GiB free, below this project's working budget of 150 GiB for source,
dependencies, and build output. A modern Mac with a larger APFS workspace is
needed for the full integration build. Lion 10.7.5 and Catalina 10.15.7 runtime
tests are still required after compilation, including renderer processes,
sandboxing, browsing, TLS, graphics, media, downloads, and extensions.

The next build should use Chromium's pinned toolchain, keep availability and
linker diagnostics enabled, and use `legacy/args/lion.gn` as the starting GN
arguments. Do not bypass unsupported APIs by disabling the sandbox or by only
changing the bundle's minimum version. No release artifact is published from
this experimental branch.

References: [original Lion build instructions](https://github.com/blueboxd/chromium-legacy/wiki/Building),
[current Chromium Mac build instructions](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md).

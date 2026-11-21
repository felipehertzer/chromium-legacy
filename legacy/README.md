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
- A Mach-port fallback using Lion's allocation, rights, and queue-limit APIs,
  with cleanup on failure. `mach_port_construct` is explicitly weak-linked;
  modern systems retain the modern path. Event synchronization uses this helper.
- Lion-compatible PartitionAlloc primitives: POSIX mutexes and cache storage,
  system-provided `arc4random_buf` before 10.12, and a Foundation system-version
  fallback before 10.10. Its two core static libraries build for Intel/10.7.
- Bundled aligned allocation uses `posix_memalign` for legacy deployments. The
  dependency patch is pinned to the current libc++ revision and applied by a
  checked `gclient` hook; it never substitutes the old Chromium 127 dependency.
- Separate deployment targets for native ARM build tools and the Intel browser
  during cross-compilation. Generated flags retain 10.7 for the browser and use
  13.0 for build-host tools.
- Experimental Intel/Lion build arguments in `legacy/args/lion.gn`.
- Pinned source and dependency references in `legacy/revisions.json` and a
  repeatable inventory of the original legacy changes in `legacy/port-audit.json`.

The standalone production helpers compile for x86_64 with deployment target
10.7. Native tests pass 17 XML/binary property-list checks and 129 Mach checks,
including message delivery, queue limits, failed allocations, and port cleanup.
Both probes also pass on an Intel Mac running Catalina 10.15.7 over SSH. The
Catalina Foundation executable is linked for 10.15; its production helper is
separately cross-compiled for 10.7. The probes also pass using Chromium's pinned
Clang/LLD with fatal linker warnings. These checks do not validate the complete
browser or execution on Lion.

## Run the focused checks

```sh
legacy/test_os_version.sh
legacy/test_mach_port.sh
python3 legacy/apply_dependency_patches.py --check
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

## Reproduce the integration build

Use a modern build Mac with Xcode and at least 150 GiB of working space. Put
`depot_tools` on `PATH` using the upstream instructions linked below. `src` must
be a real directory inside the workspace, not a symlink.

```sh
mkdir chromium-build && cd chromium-build
git clone --depth 1 --branch codex/current-chromium-lion \
  https://github.com/felipehertzer/chromium-legacy.git src
cp src/legacy/gclient.template .gclient
gclient sync --no-history --shallow
cd src
mkdir -p out/Lion
cp legacy/args/lion.gn out/Lion/args.gn
gn gen out/Lion --fail-on-unused-args
ninja -C out/Lion -j4 chrome
```

The dependency-patch hook checks the exact dependency commit and patch
applicability before changing files. Repeated runs preserve an already applied
patch, and conflicting local changes fail without being overwritten. A changed
upstream dependency pin requires reviewing and updating its patch manifest.

## Remaining work

The original Lion patch changes 491 paths. Against the current upstream tree,
366 have changed, 33 were removed, 43 are legacy additions, and 49 still match
the original upstream versions. Each affected subsystem needs review and build
validation. The compatibility forks for Skia, ANGLE, Dawn, SwiftShader, Vulkan
Memory Allocator, WebRTC, libc++, and BoringSSL are recorded as references only;
they have not been rebased onto Chromium 159's dependency revisions.

The complete Chromium source and 231 processed dependencies are checked out
using shallow history and the small Mac configuration. Setup hooks pass with
the pinned Clang 24 and Rust 1.101 toolchains and local Xcode 27. GN successfully
generates the full build. The first browser compilation exposed host-toolchain
availability errors; the host deployment-target fix resolves that initial
configuration problem. Both PartitionAlloc libraries now compile for Intel
with minimum 10.7, including the cache-layout assertions. The production
`legacy_mach_port`, `scoped_mach_port`, and `waitable_event_apple` objects also
compile through Chromium's generated Ninja build. Rust compilation receives the
same deployment target through `MACOSX_DEPLOYMENT_TARGET`; Rust runtime support
still requires a separate audit.

The integration build currently fails in libc++ clocks (`clock_gettime`, macOS
10.12+) and filesystem operations (`utimensat`, `fchmodat`, `openat`,
`fdopendir`, and `unlinkat`). Abseil's timeout implementation also needs review.
These diagnostics remain errors. The filesystem port must preserve directory
and symlink handling under concurrent changes. No browser executable was built.

Lion 10.7.5 and Catalina 10.15.7 browser runtime tests are still required after
compilation, including renderer processes, sandboxing, browsing, TLS, graphics,
media, downloads, and extensions.

Builds use Chromium's pinned toolchain, keep availability and linker
diagnostics enabled, and start with `legacy/args/lion.gn`. Do not bypass unsupported APIs by disabling the sandbox or by only
changing the bundle's minimum version. No release artifact is published from
this experimental branch.

References: [original Lion build instructions](https://github.com/blueboxd/chromium-legacy/wiki/Building),
[current Chromium Mac build instructions](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md).

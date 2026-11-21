# Chromium Legacy: current-release port

Experimental work to bring Chromium **159.0.8154.13** to Intel Macs running
**OS X Lion 10.7 and later**. The source revision is pinned in
`legacy/revisions.json`; Mac Stable was checked on 2026-11-21. This is not yet
an installable browser or a maintained legacy security release.

The inherited `master.lion` branch and release `1303823` remain references.
That old release contains Chromium 127.0.6494.0; the inherited branch contains
an unfinished Chromium 129 merge. Neither supplies the browser version label
or replaces a Chromium 159 dependency.

## Implemented compatibility work

- System-version reads fall back to `SystemVersion.plist`, using Foundation
  selectors available on Lion. Numeric parsing rejects malformed versions.
  Missing VM-detection sysctls no longer abort startup; Finder tags require 10.9.
- Mach events use the original allocation, rights, and queue-limit APIs when
  `mach_port_construct` is absent. The new symbol is weak-linked, and failures
  release allocated rights.
- PartitionAlloc uses POSIX mutexes, the matching thread-cache storage layout,
  legacy system-version reads, and system-provided randomness on older macOS.
- Current bundled libc++ compiles for Intel/10.7. Compatibility covers aligned
  allocation, clocks, filesystem timestamps and permissions, recursive removal,
  and atomic waits. Missing `__ulock` functions select pthread condition
  variables; colliding wait addresses cannot lose a notification.
- Relative filesystem operations before 10.10 use isolated workers with the
  kernel's per-thread working directory. They retain directory identity across
  renames without changing the caller's cwd. This costs a worker per operation.
  The separate libc++ removal fallback uses opaque FSRefs and does not follow
  leaf symlinks.
- BoringSSL uses Security.framework's `SecRandomCopyBytes` when `getentropy` is
  absent. Failure aborts; the fallback does not weaken entropy requirements.
- Base compatibility covers logging, backup exclusion, timer tolerance, thread
  priorities, process clocks, audit-token decoding, IOKit default ports,
  application opening, and process spawning. Missing thermal-state reporting
  returns unknown; unsupported QoS overrides remain best effort.
- Basic password operations retain the encrypted system Keychain. Frameworks
  absent on Lion are weak-linked. Secure Enclave and biometric key providers
  report unavailable when their required APIs or entitlements are absent.
- Abseil timeout clocks, Perfetto's optional native signposts, and Dawn's common
  allocation/system-version helpers have initial compatibility changes.
- Native ARM build tools use a modern host deployment target while the Intel
  browser retains 10.7. Availability diagnostics and linker warnings stay fatal.

Before 10.12, Base's continuous-clock fallback uses `mach_absolute_time`, which
excludes system sleep. The pre-10.15 application-launch fallback can hide an
app and avoid activation, but lacks the newer invisible-background-launch SPI.
These limitations need review alongside the remaining browser port.

## Verified so far

The two PartitionAlloc libraries, current libc++, and Base's static library
compile with deployment target 10.7. The five previously blocked Crypto objects
also compile. The full browser is still being compiled and ported.

| Check | Build Mac | Intel Catalina 10.15.7 |
| --- | --- | --- |
| Foundation/version probe | 24 checks passed | 24 checks passed |
| Mach-port probe | 129 checks passed | 129 checks passed |
| Filesystem/clock helpers | 64 checks passed | 64 checks passed |
| Current C++ runtime and BoringSSL probe | 32 checks passed | 32 checks passed |
| Forced legacy runtime backends | 32 checks passed | 32 checks passed |

The runtime probe checks allocation, clocks, atomic waiting, condition variables,
filesystem operations, entropy, TLS context creation, audit-token decoding, and
process cwd inheritance. It does not test a TLS handshake or the browser.
Thirteen Python tests cover the port inventory, pinned patch application, and
Mach-O audit behavior.

An additional symbol audit compares the probes with the **actual Lion 10.7.5
(11G63) libraries** extracted from Apple's official installer. All 149 imports
in the forced runtime probe have their required symbols; three absent imports
are weak and guarded. The Foundation probe's 28 imports are present. This is
an ABI check, not proof of execution, Objective-C selector compatibility, or
sandbox behavior on Lion. A Lion runtime test is still required.

## Run the focused checks

```sh
legacy/test_os_version.sh
legacy/test_mach_port.sh
legacy/test_platform.sh
python3 legacy/apply_dependency_patches.py --check
python3 -m unittest discover -s legacy/tests -p 'test_*.py' -v
python3 legacy/audit_port.py --output /tmp/chromium-port-audit.json
```

`CXX` and `SDKROOT` can select Chromium's pinned compiler and an installed SDK.
The standalone checks keep fatal linker warnings and use the sibling LLD when
available. The inventory audit reads Git trees without downloading dependency
blobs and needs the three full commits from `legacy/revisions.json` locally.
Its 491-path report is a review queue, not a completion count.

## Reproduce the integration build

Use a modern build Mac with Xcode, the upstream `depot_tools` setup, and at least
150 GiB of working space. `src` must be a real directory inside the workspace.

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
ninja -C out/Lion -j4 runtime_probe
out/Lion/runtime_probe
ninja -C out/Lion -j4 chrome
```

The dependency hook verifies exact Git revisions and preflights every patch.
Repeated runs preserve applied patches; conflicting local changes fail without
being overwritten. Changed dependency pins require reviewing their patches.

To exercise the legacy runtime backends on a newer Mac, create a separate
output directory with the same arguments and append
`legacy_force_fallbacks_for_tests = true`. Build `runtime_probe` there. This
mode forces the clock, filesystem, entropy, and libc++ wait fallbacks; official
builds reject it. It does not emulate an old kernel.

The `base_probe` target adds integration checks using the actual Base and Crypto
libraries. Its link currently exposes Rust's minimum macOS 10.12 requirement;
it has not passed and must not be used as evidence of runtime support.

For a symbol audit against an extracted, unmodified OS root:

```sh
python3 legacy/audit_macho.py out/Lion/runtime_probe \
  --system-root /path/to/extracted/lion --output /tmp/lion-abi.json
```

The audit follows dylib reexports and resolves OS symlinks inside the supplied
root. Missing required symbols, unknown ordinals, or incomplete required
libraries fail the check. Missing weak imports are reported separately and
still require reviewing guards at their call sites.

## Remaining work

The full source and 231 processed dependencies are checked out using shallow
history and the small Mac configuration. Setup hooks and GN generation pass
with pinned Clang 24/Rust 1.101 and local Xcode 27. The integration link exposed
that Rust 1.101 clamps Intel macOS objects to 10.12 even when the deployment
environment requests 10.7. A separate, source-patched compiler and runtime port
are being prepared; lowering a bundle version or ignoring linker diagnostics
will not resolve this.

Skia, ANGLE, SwiftShader, Vulkan Memory Allocator, WebRTC, V8, sandboxing,
graphics, media, UI, and the remaining browser API usage still need build and
runtime validation. The eight older compatibility forks remain references;
they have not been substituted for current dependency revisions.

After compilation, full-browser tests are required on Lion 10.7.5 and Catalina
10.15.7: startup, renderers, sandboxing, browsing, TLS, graphics, media,
downloads, and extensions. No browser executable or release artifact has been
published from this experimental branch.

References: [original Lion build instructions](https://github.com/blueboxd/chromium-legacy/wiki/Building),
[Chromium Mac build instructions](https://chromium.googlesource.com/chromium/src/+/main/docs/mac_build_instructions.md),
[Apple's Lion installer](https://support.apple.com/en-ca/106383).

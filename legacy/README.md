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
- Rust 1.101's compiler target is rebuilt from the pinned source to accept
  10.7 and the Core 2 CPU baseline. Target std is rebuilt with clock, entropy,
  filesystem, and directory-descriptor adapters. Host build tools retain their
  own modern std; the original packaged compiler is preserved for bootstrap.
- Build-local SDK stubs restore Foundation's old NSObject exports and the
  CoreText path under ApplicationServices. Xcode and SDK headers stay untouched.
- Missing Mach queue inspection uses receive-status queries. MAP_JIT is disabled
  before Mojave. Missing signature-validation attributes return unsupported;
  audit-token identities are never weakened to PID checks.
- Skia's font/ICC helpers, Crashpad's clocks and audit tokens, and network/UI
  calls have additional availability guards. Optional modern frameworks are
  weak-linked; old certificate-chain and CSSM signing paths retain OS keys.
- macOS Services exchange stable UTI strings. Big Sur and newer use the modern
  UTType implementation; Lion through Catalina use LaunchServices, including
  obsolete pasteboard aliases and canonical type identifiers. Context menus use
  the original rectangle-based window/screen conversion APIs.
- Font fallback uses Lion's original CoreText cascade API when the language-list
  API is unavailable. Display discovery uses old dictionary selectors, fixed-mode
  refresh queries, and original ICC profile/name APIs on older systems.
- Current Dawn Metal source compiles behind a macOS 13 capability gate. Older
  Macs do not discover Dawn Metal adapters or enable Graphite; the remaining
  Ganesh/OpenGL path still needs full-browser validation. ANGLE retains its
  separate Metal capability checks and uses C ownership for old dispatch objects.
- libvpx, TensorFlow Lite/XLA, and XNNPACK timers retain modern clock APIs when
  available and use Mach clocks or gettimeofday on old macOS. pthreadpool retains
  cache-line-aligned storage and C11 atomics with naturally aligned pointer types.
- Clipboard and drag/drop use stable UTI strings and LaunchServices on older
  macOS. Clipboard integration checks use an isolated pasteboard. Old screen
  capture uses fresh CGImage snapshots when display streams are unavailable.
- The pinned Crubit frontend is rebuilt against the custom compiler. Original
  Chromium interoperability tests cover integers, chars, cross-crate objects,
  allocator declarations, and standard-library Duration values.
- CoreVideo attachment fallbacks preserve Copy ownership and propagation flags.
  Dispatch owners release C objects on old macOS and use ARC on modern hosts.
  ScreenCaptureKit loopback capture is unavailable before macOS 13.
- Camera code retains the original still-image API before 10.15 and gates
  portrait effects/KVO at macOS 12. Systems without VideoToolbox select the
  existing libyuv converter for NV12/I420. Actual camera capture remains untested.
- Current V8 thread setup uses per-thread background priority where QoS classes
  are absent. Modern QoS behavior is unchanged.
- CoreAnimation uses shape masks for corner combinations that old CALayer
  cannot clip directly. Lion uses ordinary CALayers instead of the 10.8 video
  display layer. Protected video promotion is rejected before capture protection
  exists. HDR copying requires 10.15 and a Metal device.
- Native ARM build tools use a modern host deployment target while the Intel
  browser retains 10.7. Availability diagnostics and linker warnings stay fatal.

Before 10.12, Base's continuous-clock fallback uses `mach_absolute_time`, which
excludes system sleep. The pre-10.15 application-launch fallback can hide an
app and avoid activation, but lacks the newer invisible-background-launch SPI.
These limitations need review alongside the remaining browser port.

## Verified so far

The two PartitionAlloc libraries, current libc++, and Base's static library
compile with deployment target 10.7. Crypto and the separately rebuilt Rust std also compile. The full browser is still being compiled and ported.

| Check | Build Mac | Intel Catalina 10.15.7 |
| --- | --- | --- |
| Foundation/version probe | 24 checks passed | 24 checks passed |
| Mach-port probe | 129 checks passed | 129 checks passed |
| Filesystem/clock helpers | 64 checks passed | 64 checks passed |
| Current C++ runtime and BoringSSL probe | 35 checks passed | 35 checks passed |
| Forced legacy C++ runtime backends | 35 checks passed | 35 checks passed |
| Rust 1.101 runtime | 13 checks passed | 13 checks passed |
| Forced legacy Rust runtime backends | 13 checks passed | 13 checks passed |
| Base/Crypto integration | 23 checks passed | 23 checks passed |
| Base with forced event-queue fallback | 23 checks passed | 23 checks passed |
| SDK Foundation subclass/CoreText probe | passed | passed |
| Services types/font cascades, normal and forced legacy paths | 18 checks each | 18 checks each |
| libvpx timer, normal and forced legacy paths | 4 checks each, Intel and ARM | 4 checks each |
| pthreadpool C11 atomics, including contention | 12 checks, Intel and ARM | 12 checks passed |
| TensorFlow Lite/XLA clocks, normal and forced legacy paths | 3 checks each | 3 checks each |
| Isolated clipboard URL/file integration, normal and forced legacy paths | 12 checks each | 12 checks each |
| Display ID/refresh queries, normal and forced legacy paths | 8 checks each | 8 checks each |
| CoreVideo/GCD ownership, normal and forced legacy paths | 16 checks each, Intel and ARM | 16 checks each |
| Original Chromium Rust/C++ interoperability tests | 5 tests passed | 5 tests passed |
| Actual compositor clipping, normal and forced legacy paths | 13 checks each | 13 checks each |

The runtime probe checks allocation, clocks, atomic waiting, condition variables,
filesystem operations, entropy, TLS context creation, audit-token decoding, and
process cwd inheritance. It does not test a TLS handshake or the browser.
Thirty-three Python tests cover the port inventory, pinned dependency/Rust patch
application, SDK overlay preservation, and Mach-O audit behavior.

An additional symbol audit compares the probes with the **actual Lion 10.7.5
(11G63) libraries** extracted from Apple's official installer. The Rust,
Base/Crypto, SDK, Services/fonts, clipboard, displays, media ownership, Rust/C++ bindings,
compositor clipping, timers, atomics, and forced C++
runtime probes have no missing required symbols
or incomplete required libraries. Absent optional symbols remain weak and their
call sites have guards or fallbacks. This checks link compatibility; actual
execution, Objective-C selectors, and sandbox behavior on Lion remain untested.
Only the Catalina Mac is available for physical-machine tests.
The installer recovery system omits AVFoundation. Its original framework was
extracted from the same installer's Essentials.pkg for the compositor audit.
`audit_macho.py --supplemental-root PATH` fills absent libraries from that
extraction; existing primary-root libraries retain precedence, and malformed
libraries still fail the audit.


## Run the focused checks

```sh
legacy/test_os_version.sh
legacy/test_mach_port.sh
legacy/test_platform.sh
legacy/test_appkit.sh
legacy/test_vpx_timer.sh
legacy/test_pthreadpool_atomics.sh
legacy/test_media_platform.sh
python3 legacy/test_ml_clocks.py
# Requires the integration objects and a retained base_probe.rsp:
python3 legacy/test_clipboard.py
python3 legacy/test_display.py
python3 legacy/test_core_animation.py
python3 legacy/apply_dependency_patches.py --check
python3 legacy/apply_rust_std_patches.py --check
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
On Apple Silicon, Rosetta must be installed: the Intel snapshot tools run on the
build host. This keeps the normal context snapshots while sharing the target's
compiled Blink/V8 libraries instead of compiling Blink for a second architecture.


```sh
mkdir chromium-build && cd chromium-build
git clone --depth 1 --branch codex/current-chromium-lion \
  https://github.com/felipehertzer/chromium-legacy.git src
cp src/legacy/gclient.template .gclient
gclient sync --no-history --shallow
cd src
mkdir -p out/Lion
# Requires LLVM 23 development files; adjust the path for the build host.
python3 legacy/build_rust_compiler.py \
  --llvm-config /opt/homebrew/opt/llvm/bin/llvm-config --jobs 2
python3 legacy/build_crubit.py --jobs 2
cp legacy/args/lion.gn out/Lion/args.gn
cat ../rust-lion-compiler.gni ../crubit-lion.gni >> out/Lion/args.gn
buildtools/mac/gn gen out/Lion --fail-on-unused-args
ninja -C out/Lion -j4 -d keeprsp runtime_probe rust_probe base_probe sdk_probe crubit_probe
out/Lion/runtime_probe
out/Lion/rust_probe
out/Lion/base_probe
out/Lion/sdk_probe
out/Lion/crubit_probe
ninja -C out/Lion -j4 chrome
```

The Rust compiler build uses LLVM 23.1.4; Chromium's pinned Clang 24 still builds
C/C++. The compiler build verifies its resulting minimum version and CPU target,
then writes the host-library list and GN arguments to `rust-lion-compiler.gni`.
It completes a second compiler build to install matching rustc-dev metadata, and
provides the matching LLVM objcopy for Cargo release builds. Host stdlib inputs
come from bootstrap's std artifact manifest. `build_crubit.py` builds the pinned
Rust-to-C++ frontend, preserves the original tools/support sources, and emits
`crubit-lion.gni`.

Crubit uses date-based `rustversion` checks for unstable compiler APIs. Its
explicit `RUSTVERSION=1` query goes through a wrapper that reports the verified
source commit's snapshot date for a custom `-dev` build. Other version queries,
actual compiler invocations, crate versions, and metadata checks are unchanged.

The Rust std hook verifies the exact toolchain package and source hashes before
applying the compatibility patch. It preserves unknown edits and can recover
an already partially applied patch. Original tool executables are unchanged.

The dependency hook verifies exact Git revisions and preflights every patch.
Repeated runs preserve applied patches; conflicting local changes fail without
being overwritten. Changed dependency pins require reviewing their patches.

To exercise the legacy runtime backends on a newer Mac, create a separate
output directory with the same arguments and append
`legacy_force_fallbacks_for_tests = true`. Build `runtime_probe` and `rust_probe`
there. This mode forces the clock, filesystem, entropy, and libc++ wait fallbacks; official
builds reject it. It does not emulate an old kernel.

The `base_probe` target checks actual Base/Crypto clocks, threading, manual and
automatic events, directory copy/removal with symlink boundaries, and process
launch with a requested directory. Its normal build passed on both Macs.

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
with pinned Clang 24, the source-patched Rust 1.101 compiler, and local Xcode 27.
The Rust minimum-version blocker is fixed and the linked integration probes run
on Catalina. The complete browser build continues to expose other compatibility
work. The custom compiler and Crubit now pass the original interoperability tests
on Catalina; the remaining auxiliary host tools still need full-build validation.

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

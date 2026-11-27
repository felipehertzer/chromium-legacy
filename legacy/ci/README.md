# Mac build and DMG automation

The `Build Chromium Legacy DMG` workflow is manually dispatched from Actions.
It compiles the selected revision, applies the existing checks, signs a staged
copy with the upstream role entitlements, audits all bundle executables against
original Lion libraries, and uploads a verified HFS+/UDZO DMG and SHA256SUMS.
It does not publish automatically or claim that a new build passed old-OS
browser tests. Run the browser harness on the target Mac before a release.

## Prepared Mac runner

Use a dedicated modern Mac runner with the `chromium-legacy` label. The workflow
is manual and restricted to the repository owner; it does not run pull requests.
No runner is installed by adding these workflow files.

The standard and larger GitHub-hosted macOS runners currently provide 14 GB
of disk, while the initial source/toolchain/build setup needs at least 150 GiB.
See [GitHub's runner specifications](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and [larger runner specifications](https://docs.github.com/en/actions/reference/runners/larger-runners).

Prepare the workspace with the [integration build instructions](../README.md#reproduce-the-integration-build).
Configure the runner environment:

- `CHROMIUM_LEGACY_WORKSPACE`: directory containing the real `src` checkout,
  pinned dependencies, rebuilt Rust/Crubit toolchains and `out/Lion/args.gn`.
- `CHROMIUM_LION_SYSTEM_ROOT`: extracted original Lion system libraries.
- `CHROMIUM_LION_SUPPLEMENTAL_ROOT_1` and `_2`: optional additional original
  Lion framework/package library roots from the same OS build.
- `DEVELOPER_DIR`: supported Xcode developer directory.
- `PATH`: Python 3.10+, Ninja, upstream depot_tools and the required host tools.
- `CHROMIUM_LEGACY_JOBS`: optional Ninja parallelism, default 4.

Update the prepared checkout and pinned dependencies before dispatching. Select
that same branch/revision in Actions: the job refuses a mismatching commit or
uncommitted source edits and never resets a user's checkout. Initial compiler
bootstrap is a separate setup step; subsequent jobs reuse the pinned tools.
At least 30 GiB must remain free for an incremental job. A workspace lock and
workflow concurrency prevent overlapping CI builds; avoid a separate manual
Ninja writer in the same output directory.

The job uploads artifacts for seven days. The artifact is experimental and
ad-hoc signed; it is not Apple notarized and has no automatic update channel.
A successful build/ABI audit is not proof of Lion browser execution.

## Package an already validated application

```sh
python3 legacy/package_dmg.py \
  --app /path/to/Chromium.app \
  --metadata /path/to/validated-build-metadata \
  --output /path/to/new-release-assets
```

The private metadata directory must contain `build-info.json`. An optional
`catalina-browser-report.json` must match the executable hashes, actual version,
Intel host and successful checks before its runtime results are exported.
Only selected public facts are included. Raw installation reports, process IDs,
commands, full signing/ABI dumps and local paths stay outside the distribution.

The packager preserves signed app bytes and creates an Applications shortcut.
It authors an HFS+ filesystem with `hdiutil makehybrid`, verifies that the raw
HFS+ attribute fork is absent, normalizes FinderInfo in its own writable
image while preserving file modes and symlinks, then compresses it as UDZO. This avoids exporting
protected local attributes that normal file copies can retain. The mounted
image is checked for strict signatures, executable hashes, the V8 snapshot,
symlinks, local home/test paths, profile files and selected credential patterns.
Checks report file names and issue categories, never matched secret values.

Use `--zip` to also create a ZIP from explicitly written data-only entries:
no AppleDouble, extended attributes, UID/GID or creator timestamps. The ZIP is
CRC checked, extracted and checked again. macOS may attach new provenance to a
local working/extracted copy; that is separate from attributes serialized in
the distribution. Existing output images are preserved.

These checks are a guard against accidental disclosure, not an exhaustive
secret detector or a guarantee that arbitrary custom build inputs are safe.
Self-hosted GitHub Actions logs can show the runner's machine name and paths;
use a dedicated builder with generic names for future public build logs.

## Official upstream

Use the official Chromium repository to fetch new source revisions:

```sh
git remote add upstream https://github.com/chromium/chromium.git
git fetch --filter=blob:none --no-tags upstream main
```

If an existing `upstream` remote points to blueboxd, rename it to
`legacy-upstream` first. Keep `origin` pointing at this fork. The original legacy
port remains a reference; it does not supply modern Chromium dependencies.

GitHub reports this fork's network root as `chromium/chromium` and its immediate
parent as `blueboxd/chromium-legacy`. Configuring the Git upstream changes where
we fetch code; it does not change that GitHub parent label. No repository is
recreated or detached. The release baseline in `legacy/revisions.json` stays
pinned. Fetching `main` does not merge it into a validated browser release.

Integrate new Chromium revisions on a separate compatibility branch, review the
new API/dependency requirements, rebuild, audit and run the old-OS browser tests
before advancing the release pin. Do not use GitHub's parent-fork sync operation
to overwrite the port with the inherited old Chromium branch.

For a temporary personal runner, the optional Actions secrets
`LEGACY_PRIVATE_MACHINE_NAME`, `LEGACY_PRIVATE_MACHINE_HOME` and
`LEGACY_PRIVATE_BUILD_ROOT` register exact noncredential strings for redaction
before the runner prints setup diagnostics. Configure these privately, verify
actual logs, and remove temporary entries afterwards. Never put authentication
passwords or keys in these masking-only settings. Redaction does not sanitize
compiled binaries; the separate compiler mapping and export checks do that.

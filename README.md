# Experimental Chromium Legacy port

This fork targets current Chromium on **OS X Lion 10.7 and later (Intel)**.
The principal `master.lion` branch contains Chromium **159.0.8154.13 Mac Beta**.
The complete browser builds and passed 28 GUI/browser checks on Intel
**macOS Catalina 10.15.7**, including WebGL and process sandboxing.
Lion remains the compilation target; actual Lion runtime testing is pending.

Download experimental builds from [Releases](https://github.com/felipehertzer/chromium-legacy/releases).
For build automation and the official `chromium/chromium:main` upstream, see
[the CI guide](legacy/ci/README.md).

See [legacy/README.md](legacy/README.md) for the implemented compatibility fixes,
focused tests, pinned revisions, patch inventory, and remaining work.

---

# ![Logo](chrome/app/theme/chromium/product_logo_64.png) Chromium

Chromium is an open-source browser project that aims to build a safer, faster,
and more stable way for all users to experience the web.

The project's web site is https://www.chromium.org.

To check out the source code locally, don't use `git clone`! Instead,
follow [the instructions on how to get the code](docs/get_the_code.md).

Documentation in the source is rooted in [docs/README.md](docs/README.md).

Learn how to [Get Around the Chromium Source Code Directory
Structure](https://www.chromium.org/developers/how-tos/getting-around-the-chrome-source-code).

For historical reasons, there are some small top level directories. Now the
guidance is that new top level directories are for product (e.g. Chrome,
Android WebView, Ash). Even if these products have multiple executables, the
code should be in subdirectories of the product.

If you found a bug, please file it at https://crbug.com/new.

// Copyright 2026 The Chromium Legacy Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#include <algorithm>
#include <iostream>
#include <string_view>
#include "base/apple/scoped_nsautorelease_pool.h"
#include "base/at_exit.h"
#include "base/command_line.h"
#include "printing/backend/cups_compat.h"
#include "printing/backend/cups_helper.h"
#include "printing/backend/print_backend.h"
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
#include "printing/backend/print_backend_cups.h"
#endif

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
// Trusted synthetic PPD data, parsed locally; no printer or server is queried.
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
constexpr char kPpd[] = R"(*PPD-Adobe: "4.3"
*OpenGroup: General/General
*ColorDevice: False
*OpenUI *ColorModel/Color Model: PickOne
*DefaultColorModel: Gray
*ColorModel Gray/Grayscale: "<</cupsColorSpace 0/cupsColorOrder 0>>setpagedevice"
*CloseUI: *ColorModel
*OpenUI *Duplex/2-Sided Printing: PickOne
*DefaultDuplex: DuplexTumble
*Duplex None/Off: "<</Duplex false>>setpagedevice"
*Duplex DuplexNoTumble/Long Edge: "<</Duplex true/Tumble false>>setpagedevice"
*Duplex DuplexTumble/Short Edge: "<</Duplex true/Tumble true>>setpagedevice"
*CloseUI: *Duplex
*OpenUI *PageSize/Page Size: PickOne
*DefaultPageSize: Letter
*PageSize Letter/US Letter: "<</PageSize [612 792]>>setpagedevice"
*CloseUI: *PageSize
*PaperDimension Letter: "612 792"
*ImageableArea Letter: "18 36 594 756"
*OpenUI *Resolution/Resolution: PickOne
*DefaultResolution: 600dpi
*Resolution 600dpi/600 dpi: " "
*CloseUI: *Resolution
*CloseGroup: General
)";
#endif
}  // namespace
int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::apple::ScopedNSAutoreleasePool pool;
  base::CommandLine::Init(argc, argv);
  bool native_expected = false;
  if (__builtin_available(macOS 10.9, *))
    native_expected = true;
#if defined(CHROMIUM_LEGACY_FORCE_FALLBACKS_FOR_TESTS) && \
    __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
  native_expected = false;
#endif
  Check(printing::NativeCupsIppAvailable() == native_expected,
        "native IPP selection follows OS support and the legacy backend test "
        "mode");
  // Both constructors are lazy and establish no server connection here.
  auto backend = printing::PrintBackend::CreateInstance("en-US");
  Check(backend != nullptr,
        "real printing backend factory constructs a backend");
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1090
  cups_dest_t destination = {};
  char name[] = "LegacyFixture";
  destination.name = name;
  destination.num_options =
      cupsAddOption("printer-type", "0", 0, &destination.options);
  destination.num_options =
      cupsAddOption("printer-info", "Owned fixture", destination.num_options,
                    &destination.options);
  destination.num_options =
      cupsAddOption("printer-make-and-model", "Synthetic PPD",
                    destination.num_options, &destination.options);
  printing::PrinterBasicInfo info;
  Check(printing::PrintBackendCUPS::PrinterBasicInfoFromCUPS(
            destination, &info) == printing::mojom::ResultCode::kSuccess,
        "current PPD backend accepts real CUPS destination metadata");
  Check(info.printer_name == "LegacyFixture" && !info.display_name.empty(),
        "destination names retain their native metadata");
  printing::PrinterSemanticCapsAndDefaults caps;
  const bool parsed =
      printing::ParsePpdCapabilities(&destination, "en-US", kPpd, &caps);
  Check(parsed, "current parser accepts the owned synthetic PPD");
  if (parsed) {
    Check(caps.copies_max == 9999, "legacy default copy limit is retained");
    Check(caps.collate_capable && caps.collate_default,
          "default collation is retained");
    Check(!caps.color_changeable && !caps.color_default,
          "grayscale-only PPD does not advertise unsupported color");
    Check(caps.duplex_default == printing::mojom::DuplexMode::kShortEdge,
          "duplex default is parsed from the PPD");
    for (auto mode : {printing::mojom::DuplexMode::kSimplex,
                      printing::mojom::DuplexMode::kLongEdge,
                      printing::mojom::DuplexMode::kShortEdge}) {
      Check(std::find(caps.duplex_modes.begin(), caps.duplex_modes.end(),
                      mode) != caps.duplex_modes.end(),
            "supported duplex modes retain their capabilities");
    }
    Check(std::find(caps.dpis.begin(), caps.dpis.end(), gfx::Size(600, 600)) !=
              caps.dpis.end(),
          "native PPD resolution is retained");
    Check(caps.papers.size() == 1, "PPD advertises exactly its declared paper");
    if (caps.papers.size() == 1)
      Check(caps.papers.front().size_um() == gfx::Size(215900, 279400),
            "paper points convert to the correct physical dimensions");
  }
  printing::PrinterSemanticCapsAndDefaults invalid;
  Check(!printing::ParsePpdCapabilities(&destination, "en-US", "not a PPD",
                                        &invalid),
        "malformed PPD is rejected");
  cupsFreeOptions(destination.num_options, destination.options);
#endif
  std::cout << checks << " printing checks, " << failures << " failures\n";
  return failures ? 1 : 0;
}

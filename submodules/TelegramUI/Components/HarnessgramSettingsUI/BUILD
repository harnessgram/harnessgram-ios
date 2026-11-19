load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

swift_library(
    name = "HarnessgramSettingsUI",
    module_name = "HarnessgramSettingsUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/TelegramAudio",
        "//submodules/TelegramPresentationData",
        "//submodules/AccountContext",
        "//submodules/ItemListUI",
        "//submodules/PresentationDataUtils",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        "//submodules/HarnessgramAgent:HarnessgramAgent",
        "//submodules/TelegramUI/Components/HarnessgramCockpitSync",
        "//submodules/HarnessgramCockpitKit",
        "//submodules/HarnessgramFonts:HarnessgramFonts",
        "//submodules/HarnessgramHouseCore:HarnessgramHouseCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Build 23: the pages' copy and rules (the Cockpit tab, the settings rows), unit tested; this target also compiles the
# module on its own, without the app.
swift_library(
    name = "HarnessgramSettingsUITestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":HarnessgramSettingsUI",
        "//submodules/TelegramUI/Components/HarnessgramCockpitSync",
        "//submodules/Display",
        "//submodules/HarnessgramHouseCore:HarnessgramHouseCore",
        "//submodules/HarnessgramCockpitKit:HarnessgramCockpitKit",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
    ],
)

ios_test_runner(
    name = "HarnessgramSettingsUITestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "HarnessgramSettingsUITests",
    minimum_os_version = "15.0",
    runner = ":HarnessgramSettingsUITestRunner",
    deps = [
        ":HarnessgramSettingsUITestsLib",
    ],
)

# Read by the source check //submodules/TelegramUI/Components/HarnessgramSettingsUI:NoBorderedProminentTest.
filegroup(
    name = "HarnessgramSwiftSources",
    srcs = glob(["Sources/**/*.swift"]),
    visibility = ["//visibility:public"],
)

# Source check: no Harnessgram UI module uses the system bordered-prominent button style (unreadable inside List rows);
# the house style `.harnessgramFilled` (HarnessgramFilledButtonStyle) is the one filled button.
sh_test(
    name = "NoBorderedProminentTest",
    srcs = ["Tests/no_bordered_prominent.sh"],
    args = [
        "$(rootpaths :HarnessgramSwiftSources)",
        "$(rootpaths //submodules/TelegramUI/Components/HarnessgramHouseUI:HarnessgramSwiftSources)",
        "$(rootpaths //submodules/HarnessgramWidgetsUI:HarnessgramSwiftSources)",
        "$(rootpaths //submodules/HarnessgramHouseKit:HarnessgramSwiftSources)",
    ],
    data = [
        ":HarnessgramSwiftSources",
        "//submodules/TelegramUI/Components/HarnessgramHouseUI:HarnessgramSwiftSources",
        "//submodules/HarnessgramWidgetsUI:HarnessgramSwiftSources",
        "//submodules/HarnessgramHouseKit:HarnessgramSwiftSources",
    ],
)

# Source check (build 31, light and dark): the Cockpit tower and Live Activity views take every colour from their
# palettes (light and dark values); no fixed colour and no forced dark appearance.
sh_test(
    name = "TowerPaletteOnlyTest",
    srcs = ["Tests/tower_palette_only.sh"],
    args = [
        "$(rootpaths :HarnessgramSwiftSources)",
        "$(rootpaths //submodules/HarnessgramWidgetsUI:HarnessgramSwiftSources)",
    ],
    data = [
        ":HarnessgramSwiftSources",
        "//submodules/HarnessgramWidgetsUI:HarnessgramSwiftSources",
    ],
)

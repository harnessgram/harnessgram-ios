load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# The House's shared building blocks (SwiftUI and UIKit, used by the app and the widget extension): the tokens
# (colours, spacing, radii, motion), the type scale through UIFontMetrics, and the few shapes Telegram has no
# equivalent for (the arch, the lit window, the progress ruler, the lantern badge). Screens that Telegram already
# has a component for use Telegram's own (the "native first" rule); this module only holds what it lacks.
swift_library(
    name = "HarnessgramHouseKit",
    module_name = "HarnessgramHouseKit",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/HarnessgramFonts:HarnessgramFonts",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        "//submodules/HarnessgramHouseCore:HarnessgramHouseCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# The House art catalog (default art; the owner's replacements live in the app group), rebuilt by
# Resources/make-house-assets.sh. The app links all of it; the widget extension only the 44 pt windows.
filegroup(
    name = "HouseAssets",
    srcs = glob(["Resources/HarnessgramHouse.xcassets/**/*"], exclude = ["Resources/HarnessgramHouse.xcassets/**/.*"]),
    visibility = ["//visibility:public"],
)

filegroup(
    name = "HouseWidgetAssets",
    srcs = glob(["Resources/HarnessgramHouseWidget.xcassets/**/*"], exclude = ["Resources/HarnessgramHouseWidget.xcassets/**/.*"]),
    visibility = ["//visibility:public"],
)

# tokens.json is the design's machine-readable source; a copy rides in the test bundle and a test holds the
# hand-written HouseTokens equal to it, so drift fails the build.
filegroup(
    name = "TestData",
    srcs = glob(["Tests/Resources/*"]),
)

swift_library(
    name = "HarnessgramHouseKitTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    data = [
        ":TestData",
        "//submodules/HarnessgramFonts:FontFiles",
    ],
    deps = [
        ":HarnessgramHouseKit",
        "//submodules/HarnessgramFonts:HarnessgramFonts",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        "//submodules/HarnessgramHouseCore:HarnessgramHouseCore",
    ],
)

ios_test_runner(
    name = "HarnessgramHouseKitTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "HarnessgramHouseKitTests",
    minimum_os_version = "15.0",
    runner = ":HarnessgramHouseKitTestRunner",
    deps = [
        ":HarnessgramHouseKitTestsLib",
    ],
)

# Read by the source check //submodules/TelegramUI/Components/HarnessgramSettingsUI:NoBorderedProminentTest.
filegroup(
    name = "HarnessgramSwiftSources",
    srcs = glob(["Sources/**/*.swift"]),
    visibility = ["//visibility:public"],
)

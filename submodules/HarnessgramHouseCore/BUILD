load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# The House (Harnessgram "The House" redesign): the pure models behind the screens. Foundation only, so the app
# and the widget extension link the same logic and it is unit tested on its own. Rooms, their states, the
# greeting, the waiting list and the summary the widgets read; no UIKit, no SwiftUI, no Telegram modules.
swift_library(
    name = "HarnessgramHouseCore",
    module_name = "HarnessgramHouseCore",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        "//submodules/HarnessgramAgent:HarnessgramAgent",
        "//submodules/HarnessgramCockpitKit:HarnessgramCockpitKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "HarnessgramHouseCoreTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":HarnessgramHouseCore",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        "//submodules/HarnessgramAgent:HarnessgramAgent",
        "//submodules/HarnessgramCockpitKit:HarnessgramCockpitKit",
    ],
)

ios_test_runner(
    name = "HarnessgramHouseCoreTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "HarnessgramHouseCoreTests",
    minimum_os_version = "15.0",
    runner = ":HarnessgramHouseCoreTestRunner",
    deps = [
        ":HarnessgramHouseCoreTestsLib",
    ],
)

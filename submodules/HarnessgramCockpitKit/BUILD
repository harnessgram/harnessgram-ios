load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# Harnessgram Cockpit kit: what the home and lock-screen widgets, the widget buttons and the agent Live
# Activity know about the bridge's Cockpit (the snapshot, its parser, the request shapes, the answer rule
# and the shared store). Foundation only, so the app and the widget extension link the same logic and
# it is unit tested on its own; Telegram's modules never import it except through thin hooks.
swift_library(
    name = "HarnessgramCockpitKit",
    module_name = "HarnessgramCockpitKit",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/HarnessgramSettings:HarnessgramSettings",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "HarnessgramCockpitKitTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        ":HarnessgramCockpitKit",
    ],
)

ios_test_runner(
    name = "HarnessgramCockpitKitTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "HarnessgramCockpitKitTests",
    minimum_os_version = "15.0",
    runner = ":HarnessgramCockpitKitTestRunner",
    deps = [
        ":HarnessgramCockpitKitTestsLib",
    ],
)

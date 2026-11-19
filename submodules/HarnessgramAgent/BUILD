load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# Harnessgram agent features (quick-action ribbon, topic status dots, owner confirmation of sensitive
# buttons): the decisions live here, free of Telegram's UI modules, so they are unit tested on their own
# and upstream merges only touch the thin hooks that call them.
swift_library(
    name = "HarnessgramAgent",
    module_name = "HarnessgramAgent",
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
    name = "HarnessgramAgentTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":HarnessgramAgent",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
    ],
)

ios_test_runner(
    name = "HarnessgramAgentTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "HarnessgramAgentTests",
    minimum_os_version = "15.0",
    runner = ":HarnessgramAgentTestRunner",
    deps = [
        ":HarnessgramAgentTestsLib",
    ],
)

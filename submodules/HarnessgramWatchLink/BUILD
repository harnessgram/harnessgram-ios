load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# HarnessGram watch link: the approved-chats list the iPhone sends to the watch app (WatchConnectivity application
# context). Foundation + WatchConnectivity only; the payload and the chat id rule are unit tested on their own.
swift_library(
    name = "HarnessgramWatchLink",
    module_name = "HarnessgramWatchLink",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "HarnessgramWatchLinkTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        ":HarnessgramWatchLink",
    ],
)

ios_test_runner(
    name = "HarnessgramWatchLinkTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "HarnessgramWatchLinkTests",
    minimum_os_version = "15.0",
    runner = ":HarnessgramWatchLinkTestRunner",
    deps = [
        ":HarnessgramWatchLinkTestsLib",
    ],
)

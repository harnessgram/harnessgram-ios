load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

# Message fonts (SIL OFL 1.1, see Resources/README.md). The app bundles them through
# //Telegram:Telegram resources; the test bundle through the tests library's data.
filegroup(
    name = "FontFiles",
    srcs = glob(["Resources/*.ttf"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "HarnessgramFonts",
    module_name = "HarnessgramFonts",
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
    name = "HarnessgramFontsTestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    data = [
        ":FontFiles",
    ],
    deps = [
        ":HarnessgramFonts",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
    ],
)

ios_test_runner(
    name = "HarnessgramFontsTestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "HarnessgramFontsTests",
    minimum_os_version = "15.0",
    runner = ":HarnessgramFontsTestRunner",
    deps = [
        ":HarnessgramFontsTestsLib",
    ],
)

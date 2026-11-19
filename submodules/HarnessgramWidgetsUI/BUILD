load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# Harnessgram widgets: the "waiting for you" home and lock-screen widget, its Approve / Decline buttons
# (App Intents) and the agent task Live Activity. Linked only into the widget extension (and listed in its
# app_intents so the intents' metadata is bundled); the data and the rules live in HarnessgramCockpitKit.
swift_library(
    name = "HarnessgramWidgetsUI",
    module_name = "HarnessgramWidgetsUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    linkopts = [
        "-Wl,-framework,AppIntents",
        "-Wl,-framework,WidgetKit",
        "-Wl,-weak_framework,ActivityKit",
    ],
    deps = [
        "//submodules/HarnessgramCockpitKit:HarnessgramCockpitKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

swift_library(
    name = "HarnessgramWidgetsUITestsLib",
    testonly = True,
    srcs = glob([
        "Tests/**/*.swift",
    ]),
    deps = [
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        ":HarnessgramWidgetsUI",
        "//submodules/HarnessgramCockpitKit:HarnessgramCockpitKit",
    ],
)

ios_test_runner(
    name = "HarnessgramWidgetsUITestRunner",
    device_type = "iPhone 17",
    os_version = "26.5",
)

ios_unit_test(
    name = "HarnessgramWidgetsUITests",
    minimum_os_version = "17.0",
    runner = ":HarnessgramWidgetsUITestRunner",
    deps = [
        ":HarnessgramWidgetsUITestsLib",
    ],
)

# Read by the source check //submodules/TelegramUI/Components/HarnessgramSettingsUI:NoBorderedProminentTest.
filegroup(
    name = "HarnessgramSwiftSources",
    srcs = glob(["Sources/**/*.swift"]),
    visibility = ["//visibility:public"],
)

# Source check: a widget or Live Activity view that draws a white label (a filled control) also has a variant for the
# accented and vibrant looks (it reads widgetRenderingMode); otherwise the tinted look shows a blank white pill.
sh_test(
    name = "FilledWidgetControlsTest",
    srcs = ["Tests/filled_widget_controls.sh"],
    args = ["$(rootpaths :HarnessgramSwiftSources)"],
    data = [":HarnessgramSwiftSources"],
)

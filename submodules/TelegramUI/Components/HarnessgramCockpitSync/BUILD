load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# Harnessgram: the app side of the widgets and the agent task Live Activity. It mints the Cockpit login
# from the Cockpit bot's web app, refreshes the shared snapshot, reloads the widgets, answers widget
# decide links (Face ID for sensitive ones) and runs the Live Activity while the app is open.
swift_library(
    name = "HarnessgramCockpitSync",
    module_name = "HarnessgramCockpitSync",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    linkopts = [
        "-Wl,-framework,WidgetKit",
        "-Wl,-weak_framework,ActivityKit",
    ],
    deps = [
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/AccountContext",
        "//submodules/HarnessgramCockpitKit:HarnessgramCockpitKit",
        "//submodules/HarnessgramAgent:HarnessgramAgent",
    ],
    visibility = [
        "//visibility:public",
    ],
)

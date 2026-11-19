load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# HarnessGram App Intents for the main app (Siri and CarPlay through Siri): App Shortcuts must be declared in the app
# (or an App Intents extension), so this module is linked into the Telegram app and named in its app_intents.
swift_library(
    name = "HarnessgramAppIntents",
    module_name = "HarnessgramAppIntents",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    # The app_intents aspect needs the AppIntents framework declared (as HarnessgramWidgetsUI does).
    linkopts = [
        "-Wl,-framework,AppIntents",
    ],
    deps = [
        "//submodules/HarnessgramCockpitKit:HarnessgramCockpitKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)

load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "HarnessgramButtonGate",
    module_name = "HarnessgramButtonGate",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        "//submodules/HarnessgramAgent:HarnessgramAgent",
    ],
    visibility = [
        "//visibility:public",
    ],
)

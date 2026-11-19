load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# The House's app-only screens (Harnessgram "The House" redesign). One subfolder of Sources per lane: Home, Room,
# Knock, Waiting, Radio, Connect, Onboarding, Settings and Shared. Dependencies are frozen in step 0 so the lanes
# never edit this file. Native first: screens are built from Telegram's own components (ItemListController lists,
# chat-list nodes, sheets, context menus); SwiftUI only where Telegram has no equivalent, through
# HouseHostingController.
swift_library(
    name = "HarnessgramHouseUI",
    module_name = "HarnessgramHouseUI",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit",
        "//submodules/AccountContext",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/ChatListUI",
        "//submodules/HarnessgramHouseKit:HarnessgramHouseKit",
        "//submodules/HarnessgramHouseCore:HarnessgramHouseCore",
        "//submodules/HarnessgramCockpitKit:HarnessgramCockpitKit",
        "//submodules/TelegramUI/Components/HarnessgramCockpitSync",
        "//submodules/TelegramUI/Components/HarnessgramSettingsUI",
        "//submodules/HarnessgramSettings:HarnessgramSettings",
        "//submodules/HarnessgramAgent:HarnessgramAgent",
    ],
    visibility = [
        "//visibility:public",
    ],
)

# Read by the source check //submodules/TelegramUI/Components/HarnessgramSettingsUI:NoBorderedProminentTest.
filegroup(
    name = "HarnessgramSwiftSources",
    srcs = glob(["Sources/**/*.swift"]),
    visibility = ["//visibility:public"],
)

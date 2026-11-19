"""Source-level guards for the offline sample, including release-only boundaries."""

from pathlib import Path
import re
import unittest


SUBMODULES = Path(__file__).resolve().parents[2]
SIMULATOR = "targetEnvironment(simulator)"


def without_comments(source):
    return re.sub(r"(?m)^\s*//[^\n]*|/\*.*?\*/", "", source, flags=re.DOTALL)


def device_lines(source):
    """Yield branches which could be compiled for a non-simulator target."""
    excluded = []
    for line in without_comments(source).splitlines():
        directive, _, condition = line.strip().partition(" ")
        if directive == "#if":
            excluded.append(condition == SIMULATOR)
        elif directive == "#elseif":
            excluded[-1] = condition == SIMULATOR
        elif directive == "#else":
            excluded[-1] = False
        elif directive == "#endif":
            excluded.pop()
        elif not any(excluded):
            yield line


class SampleReleaseGuards(unittest.TestCase):
    def test_no_screenshot_switch_can_compile_into_device_build(self):
        sources = set(SUBMODULES.glob("**/Harnessgram*.swift"))
        sources.add(SUBMODULES / "TelegramUI/Sources/AppDelegate.swift")
        switch = re.compile(r"HARNESSGRAM_DEMO_[A-Z_]+|--harnessgram-(?:demo|test-dc)")
        guarded_files = set()
        for path in sorted(sources):
            if "Tests" in path.parts:
                continue
            source = path.read_text(encoding="utf-8")
            if not switch.search(without_comments(source)):
                continue
            guarded_files.add(path.name)
            with self.subTest(file=path.name):
                self.assertNotRegex("\n".join(device_lines(source)), switch)
        self.assertIn("HarnessgramSimDemo.swift", guarded_files)
        self.assertIn("AppDelegate.swift", guarded_files)

    def test_entry_only_uses_the_offline_account_constructor(self):
        app = (SUBMODULES / "TelegramUI/Sources/AppDelegate.swift").read_text(encoding="utf-8")
        entry = app.split("private func openHarnessgramSample()", 1)[1].split("private func openUrl(", 1)[0]
        self.assertIn("HarnessgramDemoSeed.openOfflineAccount(directory: store.directory)", entry)
        self.assertIn("auth.setWelcomeConnectionPaused(true)", entry)
        seed = (SUBMODULES / "TelegramCore/Sources/HarnessgramDemoSeed.swift").read_text(encoding="utf-8")
        offline = seed.split("public static func openOfflineAccount", 1)[1].split("#if targetEnvironment(simulator)", 1)[0]
        self.assertIn("openPostbox(", offline)
        self.assertNotRegex(without_comments(entry + offline), r"\b(?:accountWithId|initializedNetwork|NetworkInitializationArguments|MTProto|URLSession|HarnessgramCockpitClient)\b")
        self.assertEqual(app.count("openHarnessgramSample()"), 2)


if __name__ == "__main__":
    unittest.main()

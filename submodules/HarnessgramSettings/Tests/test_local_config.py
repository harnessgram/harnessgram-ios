"""Host-side checks for the optional build resource; no iOS build required."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "Telegram/Harnessgram/prepare_config.py"
DEFAULT = ROOT / "Telegram/Harnessgram/approved.json"
spec = importlib.util.spec_from_file_location("harnessgram_config", SCRIPT)
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class LocalConfigTests(unittest.TestCase):
    def test_public_defaults_are_empty_and_have_no_endpoints(self):
        default = json.loads(DEFAULT.read_text())
        config.validate_public_defaults(default)
        result = config.merge_config(default, {})
        self.assertEqual(result["agentProjectGroups"], [])
        self.assertEqual(result["peerIds"], [])
        self.assertEqual(result["usernames"], [])

    def test_generator_preserves_new_empty_fields_in_committed_defaults(self):
        default = json.loads(DEFAULT.read_text(encoding="utf-8"))
        default.update(bridgeHostSuffixes=[], futureApprovalList=[], futureApprovalMap={})
        with tempfile.TemporaryDirectory() as directory:
            public = Path(directory) / "defaults.json"
            output = Path(directory) / "approved.json"
            public.write_text(json.dumps(default), encoding="utf-8")
            subprocess.run([sys.executable, str(SCRIPT), "--default", str(public), "--output", str(output)], check=True)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), default)

    def test_committed_defaults_require_existing_fields_with_their_expected_types(self):
        default = json.loads(DEFAULT.read_text(encoding="utf-8"))
        for invalid in ([], {**default, "usernames": {}}, {**default, "mediaLevels": []}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                config.validate_public_defaults(invalid)
        del default["agentProjectGroups"]
        with self.assertRaises(ValueError):
            config.validate_public_defaults(default)

    def test_generator_rejects_private_values_in_committed_defaults(self):
        default = json.loads(DEFAULT.read_text(encoding="utf-8"))
        for field, value in {
            "relayHost": "mac.example-tailnet.ts.net",
            "relayPort": 1080,
            "bridgeBotUsername": "ExamplePersonalBot",
            "bridgeHostSuffixes": [".example-tailnet.ts.net"],
            "usernames": ["ExamplePersonalUser"],
            "peerIds": ["-100900000001"],
            "agentProjectGroups": ["-100900000001"],
            "futurePublicList": ["ExamplePersonalUser"],
            "futurePublicMap": {"ExamplePersonalUser": []},
            "futurePublicScalar": "ExamplePersonalUser",
        }.items():
            with self.subTest(field=field), self.assertRaises(ValueError):
                config.validate_public_defaults({**default, field: value})

    def test_optional_override_is_merged_without_editing_public_source(self):
        original = DEFAULT.read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            local = folder / "override.json"
            output = folder / "approved.json"
            override = {
                "agentProjectGroups": ["-100900000001"],
                "bridgeOrigin": "https://bridge.private.example.test:8443",
                "bridgeHostSuffixes": [".private.example.test"],
                "bridgeBotUsername": "ExampleBridgeBot",
                "relayHost": "relay.private.example.test",
                "relayPort": 1080,
                "roomArtAliases": {"room-project-a": ["example workspace"]},
                "roomArtStorageKeys": {"room-project-a": "room-previous-a"},
            }
            local.write_text(json.dumps(override))
            subprocess.run([sys.executable, str(SCRIPT), "--default", str(DEFAULT), "--override", str(local), "--output", str(output)], check=True)
            self.assertEqual(json.loads(output.read_text()), {**json.loads(original), **override})
            # Removing the optional input produces public defaults on the next build action.
            subprocess.run([sys.executable, str(SCRIPT), "--default", str(DEFAULT), "--output", str(output)], check=True)
            self.assertEqual(json.loads(output.read_text()), json.loads(original))
        self.assertEqual(DEFAULT.read_bytes(), original)

    def test_invalid_override_stops_without_echoing_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            local = folder / "override.json"
            output = folder / "approved.json"
            local.write_text('{"unexpected-private-field": "do-not-echo"}')
            result = subprocess.run([sys.executable, str(SCRIPT), "--default", str(DEFAULT), "--override", str(local), "--output", str(output)], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
            self.assertNotIn("do-not-echo", result.stdout + result.stderr)
            local.write_text("not JSON")
            self.assertNotEqual(subprocess.run([sys.executable, str(SCRIPT), "--default", str(DEFAULT), "--override", str(local), "--output", str(output)], capture_output=True).returncode, 0)

    def test_wrong_types_paths_and_broad_suffixes_are_rejected(self):
        for override in [[], {"agentProjectGroups": [12]}, {"relayPort": True}, {"relayPort": 65536}, {"bridgeHostSuffixes": [".example.test"]}, {"bridgeOrigin": "http://bridge.example.test"}, {"relayHost": "relay.example.test/path"}, {"bridgeBotUsername": "bad/name"}, {"roomArtAliases": {"unknown": ["example"]}}, {"roomArtStorageKeys": {"room-project-a": "../../outside"}}]:
            with self.subTest(override=override), self.assertRaises(ValueError):
                config.merge_config({}, override)


    def test_ipv6_brackets_and_shared_room_files_are_refused(self):
        with self.assertRaises(ValueError):
            config.merge_config({}, {"relayHost": "[fd00::1]"})
        with self.assertRaises(ValueError):
            config.merge_config({}, {"roomArtStorageKeys": {"room-project-a": "same", "room-project-b": "same"}})

    def test_hebrew_aliases_survive_an_ascii_locale(self):
        import os
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            override = folder / "local.json"
            out = folder / "out.json"
            override.write_text(json.dumps({"roomArtAliases": {"room-project-a": ["חדר"]}}, ensure_ascii=False), encoding="utf-8")
            env = dict(os.environ, LC_ALL="C", LANG="C", PYTHONUTF8="0", PYTHONIOENCODING="ascii")
            subprocess.run([sys.executable, "-I", str(SCRIPT), "--default", str(DEFAULT), "--override", str(override), "--output", str(out)], check=True, env=env)
            self.assertEqual(json.loads(out.read_text(encoding="utf-8"))["roomArtAliases"]["room-project-a"], ["חדר"])

if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Merge a non-secret, local build configuration into the public resource."""
import argparse
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

KEYS = {"agentProjectGroups", "bridgeOrigin", "bridgeHostSuffixes", "bridgeBotUsername", "relayHost", "relayPort", "roomArtAliases", "roomArtStorageKeys"}

PUBLIC_DEFAULT_TYPES = {
    "usernames": list,
    "peerIds": list,
    "stickerPackIds": list,
    "stickerPackShortNames": list,
    "linkPreviewDomains": list,
    "mediaLevels": dict,
    "agentProjectGroups": list,
}


def validate_public_defaults(default):
    if not isinstance(default, dict) or any(
        not isinstance(default.get(key), expected_type)
        for key, expected_type in PUBLIC_DEFAULT_TYPES.items()
    ):
        raise ValueError("committed defaults must contain the expected approval fields")
    if any(not isinstance(value, (list, dict)) or value for value in default.values()):
        raise ValueError("committed defaults must contain only empty arrays and objects")


def merge_config(default, override):
    if not isinstance(default, dict) or not isinstance(override, dict):
        raise ValueError("configuration must be an object")
    if set(override) - KEYS:
        raise ValueError("unknown local configuration key")
    result = {**default, **override}
    groups = result.get("agentProjectGroups", [])
    if not isinstance(groups, list) or any(not isinstance(x, str) or not re.fullmatch(r"(?:-100)?[1-9][0-9]*", x) for x in groups):
        raise ValueError("agentProjectGroups must contain decimal chat ID strings")
    for key in ("bridgeOrigin", "bridgeBotUsername", "relayHost"):
        if key in result and not isinstance(result[key], str):
            raise ValueError(key + " must be a string")
    if "bridgeOrigin" in result:
        origin = urlsplit(result["bridgeOrigin"])
        if origin.scheme != "https" or not origin.hostname or origin.username is not None or origin.password is not None or origin.path not in ("", "/") or origin.query or origin.fragment or (origin.port is not None and not 1 <= origin.port <= 65535):
            raise ValueError("bridgeOrigin must be an HTTPS origin")
    if "bridgeBotUsername" in result and not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{4,31}", result["bridgeBotUsername"]):
        raise ValueError("bridgeBotUsername must be a Telegram username without @")
    if "relayHost" in result and not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*", result["relayHost"]):
        raise ValueError("relayHost must be a host name or IPv4 address without a path or port")
    suffixes = result.get("bridgeHostSuffixes", [])
    if not isinstance(suffixes, list) or any(not isinstance(x, str) or not re.fullmatch(r"\.[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+){2,}", x) for x in suffixes):
        raise ValueError("bridgeHostSuffixes must contain private network suffixes")
    port = result.get("relayPort", 1080)
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError("relayPort must be between 1 and 65535")
    aliases = result.get("roomArtAliases", {})
    if not isinstance(aliases, dict) or any(k not in ("room-gesher", "room-project-a", "room-project-b", "room-project-c") or not isinstance(v, list) or any(not isinstance(x, str) or not x.strip() for x in v) for k, v in aliases.items()):
        raise ValueError("roomArtAliases must map known art keys to nonempty name lists")
    storage = result.get("roomArtStorageKeys", {})
    if not isinstance(storage, dict) or any(k not in ("room-project-a", "room-project-b", "room-project-c") or not isinstance(v, str) or not re.fullmatch(r"[a-z0-9-]{1,40}", v) for k, v in storage.items()):
        raise ValueError("roomArtStorageKeys must contain safe local file stems")
    if len(set(storage.values())) != len(storage):
        raise ValueError("roomArtStorageKeys must name a different file for each room")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--default", required=True, type=Path)
    parser.add_argument("--override", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        public = json.loads(args.default.read_text(encoding="utf-8"))
        validate_public_defaults(public)
        local = json.loads(args.override.read_text(encoding="utf-8")) if args.override else {}
        merged = merge_config(public, local)
    except (ValueError, OSError):
        parser.exit(1, "Invalid Harnessgram configuration; no resource generated.\n")
    args.output.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

# Local build configuration

Public source ships no Telegram group IDs, bot username, bridge address, relay address or personal project aliases.
The public approval lists in `Telegram/Harnessgram/approved.json` are empty.

## Private build input

Before invoking the existing build command, copy your non-secret configuration to
`Telegram/Harnessgram/local-config.json`. This exact path is ignored by the adjacent `.gitignore`.
Build scripts may copy it into each checkout at that same relative path. Do not edit the public default.

`//Telegram:HarnessgramConfig` reads that optional file as a declared build input and merges its keys into a generated
`approved.json` resource. The app bundles only the generated resource. App extensions find it in their containing app,
just as they find the approval list. Changing or removing the override invalidates the build input; a missing file
produces the empty public defaults, while invalid JSON or an unsupported key stops resource generation.

All values below are **synthetic examples**, not working endpoints or real Telegram identities:

```json
{
  "agentProjectGroups": ["-100900000001", "-100900000002"],
  "bridgeBotUsername": "ExampleBridgeBot",
  "bridgeOrigin": "https://bridge.private.example.test:8443",
  "bridgeHostSuffixes": [".private.example.test"],
  "relayHost": "relay.private.example.test",
  "relayPort": 1080,
  "roomArtAliases": {
    "room-project-a": ["example workspace", "מרחב לדוגמה"],
    "room-project-b": ["example content", "תוכן לדוגמה"],
    "room-project-c": ["example shop", "חנות לדוגמה"]
  },
  "roomArtStorageKeys": {
    "room-project-a": "room-previous-a",
    "room-project-b": "room-previous-b",
    "room-project-c": "room-previous-c"
  }
}
```

Every key is optional. An omitted group list stays empty. `agentProjectGroups` contains decimal strings in Bot API
`-100` format, or positive channel IDs; these enable agent UI and do not approve chats or grant bridge privileges.
`bridgeBotUsername` selects the bot for pairing; bridge privileges still require the bot ID reported by the
authenticated panel, and a changed bot ID still needs device-owner confirmation.

Prefer `bridgeOrigin`, the exact HTTPS origin including its port. Initial pairing accepts the bot menu/Main App only
at that origin. A deployment that intentionally uses several hosts in one private network may instead set
`bridgeHostSuffixes` to that network's specific suffix (at least three labels); leave it empty otherwise. Never use a
shared hosting suffix. No network suffix or hostname is built into the public client.

Pairing checks the signed Web App URL against the menu origin before accepting a credential. The authorized origin
is saved with the credential in protected, account-scoped storage. Radio links accept that paired host, an explicitly
configured host/network, or the exact previously saved trusted host. Another stream still requires confirmation;
missing host configuration refuses new links and shows a Hebrew explanation. Disconnect/account pause removes the
paired origin from the UI along with the credential. No new shared file or login secret is introduced.

`relayHost` is a hostname or IP address, without scheme, path or port. The relay is an independently configured SOCKS5
endpoint on your computer; its port defaults to 1080. The HTTPS pairing port is never guessed to be a SOCKS5 port.
Without a valid relay host, the app installs no relay proxy and probes no address. Settings explains the missing
configuration in Hebrew. With an endpoint, the existing reachability, direct fallback and no-proxy-for-calls rules
remain in effect.

`roomArtAliases` maps project names to generic bundled art keys. `roomArtStorageKeys` optionally preserves the old
local file stems of user-replaced room images after a catalog rename. It never changes bundled image names and only
accepts safe file stems, not paths. Omit it for a new installation.

This file is ignored by Git, **not secret storage**: its values are embedded in the built app. Never put tokens,
passwords, signed login data, signing identities or provisioning information here. Build public release artifacts from
a clean checkout without this file, and inspect the generated resource before distribution. Remote build caches may
contain generated private configuration; use the project's private build/cache policy for personal builds.

## Bridge integration contract

A bridge exposes its authenticated panel at the configured HTTPS origin. The app uses `POST /api/state`
(`decisions`, `sessions`, `cards`), optional `POST /api/radio-player`, and `POST /api/decide`.
The Telegram-signed Mini App login travels only in `X-Telegram-Init-Data`; redirects are refused and a request may only
target its credential's exact origin. Read and answer windows remain bounded by the credential policy.

Decision IDs are 16 lowercase hexadecimal characters. Sensitive inline callback data starts with `hg!`; sensitive
non-callback buttons start with U+1F510. Missing sensitivity information remains sensitive. Device-owner confirmation
is required before sensitive actions. Topic status prefixes are `⚙️` (working), `❓` (waiting), and `✅` (done).

The reply keyboard must match the app's exact Hebrew button text, including emoji variation selectors:
`▶️ המשך`, `📋 מצב`, `⏹️ עצור`. Summary is a plain message rather than a bridge command.
The radio uses HTTPS `/listen/<token>/live.m3u8`; listen links and credentials stay in protected device storage and
are never build inputs.

## Artwork sources

Normal app builds use the checked-in catalog. Optional artwork regeneration takes an explicit source-art directory:
`make-house-assets.sh <source-art-directory>`. Masters use the generic `room-project-a`, `room-project-b`,
`room-project-c` names. The square radio master is `radio-tower.png` in that directory, or the explicitly supplied
`HOUSE_RADIO_TOWER` path. No personal source directory or agent-state path is assumed.

## Verification

Run the HarnessgramSettings, HarnessgramAgent, HarnessgramCockpitKit, HarnessgramHouseCore, HarnessgramHouseKit and
TelegramCore test targets through the repository's documented test command. They cover empty defaults, explicit
pairing trust, foreign-host refusal, missing relay configuration and synthetic room aliases. Resource merging can be
checked separately with the Python tests under `submodules/HarnessgramSettings/Tests/test_local_config.py`.

## Keeping private settings out of public builds

Keep the real file outside the source tree. Private build scripts copy it to
`Telegram/Harnessgram/local-config.json` for one build and delete it when the build ends (also on failure).
A public release build must start from a tree without that file; the owner's scripts refuse to start a
public build (`HG_PUBLIC=1`) while a copy is present. An app built without relay settings switches off and
removes a relay remembered from an earlier configured build, so no unmanaged proxy stays active.

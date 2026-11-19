# HarnessGram for iOS

HarnessGram is an unofficial messaging client for the Telegram network, a fork of
[Telegram-iOS](https://github.com/TelegramMessenger/Telegram-iOS), licensed under the GNU GPL v2 like the code it is
based on (see `LICENSE`). It is not affiliated with or endorsed by Telegram.

It adds a personal content filter (approved chats, per-chat media levels) and a native Cockpit for the HarnessGram
bridge, an open-source program that runs on your own computer: https://github.com/harnessgram/harnessgram

## Building

Follow Telegram-iOS's build instructions in `README.md`, with these differences:

1. Bring your own API credentials: get an `api_id` and `api_hash` at https://my.telegram.org and put them in your
   build configuration (`build-system/template_minimal_development_configuration.json` shows the fields). Never
   commit them.
2. Use your own bundle id, team id and provisioning profiles; the profiles in `build-system/example-configuration`
   and `build-system/fake-codesigning` are upstream examples only.
3. Optional personal settings (bridge bot, relay, agent groups) go in `Telegram/Harnessgram/local-config.json`,
   which is git-ignored; without it the app uses neutral defaults.

## Licence and notices

The source code is licensed under the GNU General Public License, version 2 (see `LICENSE`), like Telegram-iOS, which
it is based on. Upstream copyright and licence notices are kept as they are in the source files; bundled third-party
libraries keep their own licences in their folders.

## Name and logo

The "HarnessGram" name and logo are not licensed under the GPL. You may build and share your own version of this
code under the GPL, but give it a different name and icon, and do not present it as HarnessGram or as endorsed by it.
"Telegram" is a trademark of its owner; this project is not affiliated with Telegram.

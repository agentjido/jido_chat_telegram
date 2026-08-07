# Changelog

## 1.0.0

Initial Hex release of `jido_chat_telegram`.

### Features

- Adds the Telegram adapter package for `jido_chat`.
- Provides the canonical `Jido.Chat.Telegram.Adapter` implementation backed by `ExGram`.
- Supports Telegram-specific extensions, streaming responses, and ingress helpers.

<!-- changelog -->

## [v1.2.1](https://github.com/agentjido/jido_chat_telegram/compare/v1.2.0...v1.2.1) (2026-08-07)




### Bug Fixes:

* remove Req dependency override by mikehostetler

## [v1.2.0](https://github.com/agentjido/jido_chat_telegram/compare/v1.1.0...v1.2.0) (2026-08-06)




### Features:

* telegram: expose fetch_media/2 and read photo captions as message text (#31) by Jad Tarabay

* telegram: add rich message support via sendRichMessage (#28) by Jad Tarabay

* support Telegram file downloads (#26) by mikehostetler

## [v1.1.0](https://github.com/agentjido/jido_chat_telegram/compare/v1.0.0...v1.1.0) (2026-05-28)




### Features:

* support Telegram ingress subscriptions by mikehostetler

### Bug Fixes:

* refresh jido_chat dependency and tests by mikehostetler

* infer telegram parse_mode from canonical format (#15) by Julien

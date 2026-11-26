---
id: I399
title: Revise the wording of every context's log lines in one pass
category: refactor
severity: low
platform: domain
status: open
last_verified: 2026-11-26
related: [I398]
---

## Symptom

What an app can read in `bluey.logEvents` (the context, the message, the data keys and their values) was frozen while each context moves into the target layout, because an app may filter on any of it. So Connection's lines still speak the old words: a state is `ConnectionState.disconnecting` although the domain says closing, an operation is the platform's method name (`requestMtu`, `getMaximumWriteLength`), the MTU request and the two readings log under `bluey.gatt` although they are Connection's, and the data keys name a device both `address` and `deviceId`.

## Location

- `bluey/lib/src/features/connection/application/connection_log_words.dart`: every frozen word of Connection's logs (contexts, state words, operation words, failure codes), and nothing else. Its library doc says the pass that revises the wording deletes it.
- Message endings, data keys and detail templates stay beside the line that logs them (`link_session.dart`, `link_registry.dart`, `link_operation_log.dart`, the adapters).
- The other contexts' lines, still in the old folders, until their slices move them.

## Root cause

A rename of a log word is a public change. Making it one context at a time would change what an app reads six times, so slice 1 froze the words instead (design `docs/superpowers/specs/2026-11-18-link-lifecycle-design.md`, section 13, ruling 46).

## Notes

- Proposed timing: one pass over every context's logs after slice 6, once the last context has moved. Joel has not confirmed it.
- The pass decides one vocabulary (contexts by context, operations and states in each context's words, one key for a device), writes it in each context's application, deletes `connection_log_words.dart`, updates every log expectation in the tests as the deliberate change it is, and lists every changed line in the changelog.
- `LinkHadEnded`'s message names a radio outage by its enum value; the pass words it too.

# Bluey Backlog

This directory holds **one file per known bug, no-op stub, and unimplemented
feature** in the Bluey library — the detailed technical record (symptom, root
cause, `file:line`, fix sketch) behind each roadmap item.

> **The index lives in [`../roadmap.md`](../roadmap.md).** That top-level
> roadmap is the source of truth for what exists and what to work on next —
> priority, status, and ordering, grouped by bounded context. **This README
> documents how the backlog itself is structured** (entry schema, scope, ID
> allocation); it is no longer an index. When priority or status changes, edit
> the roadmap, not the entry file.

This backlog supersedes the January 2026 historical docs now kept in [`../old/`](../old/) — `BUGS_ANALYSIS.md`, `ANDROID_IMPLEMENTATION_COMPARISON.md`, and `IOS_IMPLEMENTATION_COMPARISON.md`. Those files were written pre-Phase-2a and many of their findings are already fixed; they remain as historical context. Entries here link back to them via `historical_ref:` where relevant.

## Scope

An entry belongs here if any of these is true:

- **Bug** — code does the wrong thing or nothing when it should do something.
- **No-op stub** — an API is exposed but its implementation is empty or returns a hardcoded value.
- **Unimplemented feature** — a capability is missing entirely (no API, no native wiring).
- **Wontfix limitation** — a capability is impossible on a platform; recorded so it's not rediscovered.

A documented, worked-around workaround is not on its own a backlog entry. Only track it here if there's still unfinished work or a decision to revisit.

## Entry schema

Every entry file has YAML frontmatter followed by prose. Required fields:

```yaml
---
id: I001                          # globally unique, monotonically assigned
title: Short imperative title
category: bug | no-op | unimplemented | limitation
severity: critical | high | medium | low
platform: domain | android | ios | both | platform-interface
status: open | fixed | wontfix
last_verified: YYYY-MM-DD
fixed_in: <commit-sha>            # optional, only if status=fixed
historical_ref: BUGS-ANALYSIS-#7  # optional, link to predecessor doc
related: [I005, I012]             # optional
---
```

Prose sections (in this order, any may be omitted if empty):

- **Symptom** — user-observable effect.
- **Location** — current `file:line` reference(s).
- **Root cause** — why it happens.
- **Notes** — fix sketch, links to specs/plans, constraints.

> **On the `status:` / `severity:` fields:** the roadmap is authoritative for an
> item's live status and priority. These per-file fields are a convenience
> mirror kept roughly in sync — if one drifts from the roadmap, the roadmap
> wins. (`severity` here maps to roadmap `priority`; the roadmap's `☐/◐/☑` maps
> to `open`/in-progress/`fixed`.)

## Status legend

| Status | Meaning |
|---|---|
| `open` | Still present in HEAD. Needs work. |
| `fixed` | Verified resolved in HEAD. Entry kept so we know the claim was tracked. |
| `wontfix` | Intentional — platform limit, out-of-scope, or superseded. |

## How to work with this index

- **To see what to work on next**, read [`../roadmap.md`](../roadmap.md) — it carries current priority, status, and grouping.
- **Before starting work**, grep here for the affected subsystem. Don't start on a bug that's already been traced to a root cause in an existing entry without updating the entry.
- **When an entry is fixed**, don't delete it — set `status: fixed`, fill in `fixed_in`, update `last_verified`, and flip the item's line in the roadmap to `☑`.
- **When a new bug/stub/gap is discovered**, create a new numbered entry (don't reuse retired IDs) and add a line for it to the roadmap under the right track.
- **Re-verify periodically**. Entries accumulate false certainty over time. Bulk re-verification against HEAD is a valid maintenance task.

## ID allocation

- `I001–I009` — domain layer
- `I010–I019` — Android native bugs (non-stub)
- `I020–I029` — Android GATT server stubs
- `I030–I039` — Android connection-level stubs / missing APIs
- `I040–I049` — iOS stubs / no-ops
- `I050–I099` — cross-platform features
- `I100–I199` — fixed
- `I200–I299` — wontfix
- `I300–I399` — DDD / architectural refinement (bounded-context boundaries, value objects, ubiquitous language)

Gaps in the numbering are intentional — they reserve space for follow-up entries in the same cluster.

**Cluster deviations.** A handful of entries from the 2026-04-26 deep review (I016 iOS server, I017 domain) landed in the I010–I019 range because the cross-platform cluster (I050–I099) was nearly full. The convention is "by content, not by ID" — refer to the section the entry appears under in the roadmap, not its numeric range. When new IDs are assigned going forward, prefer fresh numbers in the I100s+ if all relevant cluster ranges are saturated, rather than overflowing into a sibling cluster.

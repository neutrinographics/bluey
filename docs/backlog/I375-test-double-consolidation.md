---
id: I375
title: Consolidate test doubles onto FakeBlueyPlatform and finish the SUT sweeps
category: refactor
severity: medium
platform: domain
status: open
last_verified: 2026-07-10
related: [I329, I330]
---

## Symptom

Test-discipline debt the audits recorded (DA-38, DA-39 remainder,
NT-13, NT-14, O5/O6):

- four hand-rolled ~52-override `MockBlueyPlatform` doubles
  (`bluey_test`, `bluey_connect_test`, `bluey_connection_test`,
  `bluey_server_test`) bypass the mandated fake and have diverged
- `error_scenarios_test.dart` still asserts on the fake instead of the
  domain in two places
- the legacy `simulateWrite*` boolean seams remain alongside the
  fault-rule queue (leak-prone set/reset pattern)
- the ~20-line heart-rate fixture literal is copy-pasted across
  integration files despite `TestServiceBuilder` existing

## Notes

Migrate the four suites onto `FakeBlueyPlatform` (extend it with any
missing seams), sweep the remaining SUT bypasses, migrate boolean-seam
call sites to `enqueueFault` and delete the booleans, and swap inline
fixtures for the builders. Behavior-preserving; the full suite is the
net.

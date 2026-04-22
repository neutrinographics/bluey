# bluey_example

A demo Flutter app showcasing the bluey BLE library: scanner, connection, GATT service explorer, peripheral server, and stress tests.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Stress tests

When connected to a peer running this example app's server, a "Stress Tests" button appears beneath Disconnect on the connection screen. Seven tests are available:

- **Burst write** — N parallel writes; measures success rate and latency
- **Mixed ops** — concurrent write/read/discoverServices/requestMtu cycles
- **Soak** — sustained writes over a duration
- **Timeout probe** — deliberately triggers GattTimeoutException via `delayAck`
- **Failure injection** — server drops one write via `dropNext`; verifies recovery
- **MTU probe** — negotiates MTU then writes/reads payloads at the new size
- **Notification throughput** — server bursts N notifications; verifies all received

Each card has its own configuration form. While one test runs, the Run buttons on other cards disable (one-test-at-a-time invariant).

Tests are isolated by sending a `Reset` command before each run; this clears any state left by a prior cancelled test.

The tests rely on a custom stress service (`b1e7a001-...`) hosted by this app's own server. When running against a peer that doesn't host this service (e.g. a custom bluey-based app), the Stress Tests button is hidden.

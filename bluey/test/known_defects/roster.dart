/// The known defects this package's run must find, each by its full test
/// name, group and test together, so a known defect cannot be deleted or
/// added without this list saying so.
///
/// A roster only shrinks. A name leaves in the commit that fixes its defect
/// and moves its test into the normal suite; nothing is ever added.
/// docs/ARCHITECTURE.md says how the Known defects job reads it.
library;

/// The full names of the known defects, in the order the run meets them.
const knownDefects = <String>[
  'H3 (I381): remote disconnect never finalises the Connection stateChanges closes after the peer drops the link',
  'H3 (I381): remote disconnect never finalises the Connection disconnect() after a remote drop still releases resources',
  'H2 (I380): peer discovery probes tear down live connections discoverPeers leaves an existing peer connection intact',
  'M4 (I336): scan restart without awaiting cancel second scan delivers results',
  'M4 (I336): scan restart without awaiting cancel platform scan is not left running while scanner says stopped',
  'M5 (I382): dispose while scanning dispose stops the platform scan',
  'L1 (I386): advertising state desync a rejected re-start does not make stopAdvertising a no-op',
  'M7 (I384): server request with no handler attached a read with no readRequests listener is answered',
  'M6 (I383): control-service registration failure a transient addService failure does not brick the server',
];

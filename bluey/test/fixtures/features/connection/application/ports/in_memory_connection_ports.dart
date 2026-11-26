import 'package:bluey/src/features/connection/application/ports/connection_ports.dart';

import 'in_memory_links.dart';

/// Every port as its in-memory double, for tests of the edge that need no
/// platform.
ConnectionPorts inMemoryConnectionPorts({InMemoryLinks? links}) =>
    ConnectionPorts(links: links ?? InMemoryLinks());

import 'package:flutter/material.dart';
import 'package:bluey/bluey.dart';

import 'features/scanner/scanner_screen.dart';
import 'features/server/server_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlueyExampleApp());
}

class BlueyExampleApp extends StatefulWidget {
  const BlueyExampleApp({super.key});

  @override
  State<BlueyExampleApp> createState() => _BlueyExampleAppState();
}

class _BlueyExampleAppState extends State<BlueyExampleApp> {
  late final Bluey _bluey;

  @override
  void initState() {
    super.initState();
    _bluey = Bluey();
  }

  @override
  void dispose() {
    _bluey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlueyProvider(
      bluey: _bluey,
      child: MaterialApp(
        title: 'Bluey Example',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

/// Provides Bluey instance to descendant widgets
class BlueyProvider extends InheritedWidget {
  final Bluey bluey;

  const BlueyProvider({super.key, required this.bluey, required super.child});

  static Bluey of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<BlueyProvider>();
    assert(provider != null, 'No BlueyProvider found in context');
    return provider!.bluey;
  }

  @override
  bool updateShouldNotify(BlueyProvider oldWidget) => bluey != oldWidget.bluey;
}

/// Home screen with navigation to Scanner and Server
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [ScannerScreen(), ServerScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Icon(Icons.cell_tower_outlined),
            selectedIcon: Icon(Icons.cell_tower),
            label: 'Server',
          ),
        ],
      ),
    );
  }
}

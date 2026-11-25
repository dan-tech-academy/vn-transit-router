import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'ui/nearby_screen.dart';
import 'ui/planner_screen.dart';
import 'ui/routes_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..load(),
      child: const TransitApp(),
    ),
  );
}

class TransitApp extends StatelessWidget {
  const TransitApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0E9F6E);
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: b),
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    return MaterialApp(
      title: 'Lộ Trình Việt',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Không tải được dữ liệu tuyến: ${app.loadError}'),
          ),
        ),
      );
    }
    if (!app.ready) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang tải dữ liệu tuyến...'),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [PlannerScreen(), RoutesScreen(), NearbyScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.alt_route_rounded),
            label: 'Tìm đường',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bus_rounded),
            label: 'Tuyến',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_rounded),
            label: 'Trạm gần đây',
          ),
        ],
      ),
    );
  }
}

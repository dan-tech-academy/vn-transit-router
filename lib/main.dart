import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'l10n.dart';
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
    const seed = Color(0xFF84CC16);
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: b,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      ),
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
    final app = context.watch<AppState>();
    return MaterialApp(
      title: 'Ghee',
      themeMode: app.themeMode,
      locale: Locale(app.lang),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '${tr('Không tải được dữ liệu tuyến', 'Could not load route data')}: ${app.loadError}',
            ),
          ),
        ),
      );
    }
    if (!app.ready) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(tr('Đang tải dữ liệu tuyến...', 'Loading route data...')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: IndexedStack(
        index: app.tab,
        children: const [PlannerScreen(), RoutesScreen(), NearbyScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: app.tab,
        onDestinationSelected: app.setTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.alt_route_rounded),
            label: tr('Tìm đường', 'Plan'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.directions_bus_rounded),
            label: tr('Tuyến', 'Routes'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.place_rounded),
            label: tr('Trạm gần đây', 'Nearby'),
          ),
        ],
      ),
    );
  }
}

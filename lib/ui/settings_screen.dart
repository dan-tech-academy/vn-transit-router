import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';
import 'common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = Theme.of(context);
    Widget section(IconData icon, String title, List<Widget> children) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: t.colorScheme.surfaceContainerLow,
            elevation: 1,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: t.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          size: 18,
                          color: t.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        title,
                        style: t.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...children,
                ],
              ),
            ),
          ),
        );
    Widget note(String s) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        s,
        style: t.textTheme.bodySmall?.copyWith(
          color: t.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return pageStatusBar(
      context,
      Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  const BackButton(),
                  Text(
                    tr('Cài đặt', 'Settings'),
                    style: t.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              section(Icons.palette_outlined, tr('Giao diện', 'Appearance'), [
                SegmentedButton<ThemeMode>(
                  key: const Key('theme'),
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(tr('Hệ thống', 'System')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(tr('Sáng', 'Light')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(tr('Tối', 'Dark')),
                    ),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.setThemeMode(s.first),
                ),
              ]),
              section(Icons.translate_rounded, tr('Ngôn ngữ', 'Language'), [
                SegmentedButton<String>(
                  key: const Key('lang'),
                  segments: const [
                    ButtonSegment(value: 'vi', label: Text('Tiếng Việt')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {app.lang},
                  onSelectionChanged: (s) => app.setLang(s.first),
                ),
              ]),
              section(Icons.alt_route_rounded, tr('Tìm đường', 'Routing'), [
                SwitchListTile(
                  key: const Key('street-walking'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tr('Đường đi bộ theo phố', 'Street walking paths'),
                  ),
                  value: app.streetWalking,
                  onChanged: (v) => app.setRouting(streetWalking: v),
                ),
                note(
                  tr(
                    'Tự tải khi mở lộ trình. Cần mạng và gửi toạ độ hai đầu chặng đi bộ (có thể gồm vị trí của bạn) đến routing.openstreetmap.de. Khi tắt, bạn vẫn tải được cho từng lộ trình.',
                    'Loads automatically when a trip is opened. Needs a connection and sends the walk end points (which may include your location) to routing.openstreetmap.de. When off, you can still load them per trip.',
                  ),
                ),
              ]),
              section(Icons.map_outlined, tr('Bản đồ offline', 'Offline map'), [
                Text(
                  tr(
                    'Vùng bản đồ bạn đã xem được lưu trên máy trong 30 ngày (dọn về khoảng 300 MB mỗi lần mở app) và hiện lại khi mất mạng.',
                    'Map areas you have viewed are kept on this device for 30 days (trimmed to about 300 MB at app start) and shown again when offline.',
                  ),
                ),
                note(
                  tr(
                    'Tìm đường giữa các trạm luôn chạy offline. OpenStreetMap không cho tải sẵn cả thành phố.',
                    'Routing between stops always works offline. OpenStreetMap does not allow downloading whole cities.',
                  ),
                ),
              ]),
              section(Icons.info_outline, tr('Dữ liệu', 'Data'), [
                Text(
                  tr(
                    'Tuyến và trạm © OpenStreetMap contributors (ODbL). Giờ chạy bổ sung từ xe-buyt.com.',
                    'Routes and stops © OpenStreetMap contributors (ODbL). Extra schedules from xe-buyt.com.',
                  ),
                ),
                note(
                  tr(
                    'Vị trí xe và giờ đến thực tế chưa có vì chưa có nguồn dữ liệu công khai.',
                    'Live vehicle positions and arrivals are unavailable: no open feed exists.',
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../l10n.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = Theme.of(context);
    Widget header(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        s,
        style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.primary),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Cài đặt', 'Settings'))),
      body: ListView(
        children: [
          header(tr('Giao diện', 'Appearance')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
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
          ),
          header(tr('Ngôn ngữ', 'Language')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              key: const Key('lang'),
              segments: const [
                ButtonSegment(value: 'vi', label: Text('Tiếng Việt')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {app.lang},
              onSelectionChanged: (s) => app.setLang(s.first),
            ),
          ),
          header(tr('Tìm đường', 'Routing')),
          SwitchListTile(
            key: const Key('street-walking'),
            title: Text(tr('Đường đi bộ theo phố', 'Street walking paths')),
            subtitle: Text(
              tr(
                'Tự tải khi mở lộ trình. Cần mạng và gửi toạ độ hai đầu chặng đi bộ (có thể gồm vị trí của bạn) đến routing.openstreetmap.de. Khi tắt, bạn vẫn tải được cho từng lộ trình.',
                'Loads automatically when a trip is opened. Needs a connection and sends the walk end points (which may include your location) to routing.openstreetmap.de. When off, you can still load them per trip.',
              ),
            ),
            value: app.streetWalking,
            onChanged: (v) => app.setRouting(streetWalking: v),
          ),
          header(tr('Bản đồ offline', 'Offline map')),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: Text(
              tr(
                'Vùng bản đồ bạn đã xem được lưu trên máy trong 30 ngày (dọn về khoảng 300 MB mỗi lần mở app) và hiện lại khi mất mạng.',
                'Map areas you have viewed are kept on this device for 30 days (trimmed to about 300 MB at app start) and shown again when offline.',
              ),
            ),
            subtitle: Text(
              tr(
                'Tìm đường giữa các trạm luôn chạy offline. OpenStreetMap không cho tải sẵn cả thành phố.',
                'Routing between stops always works offline. OpenStreetMap does not allow downloading whole cities.',
              ),
            ),
          ),
          header(tr('Dữ liệu', 'Data')),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(
              tr(
                'Tuyến và trạm © OpenStreetMap contributors (ODbL). Giờ chạy bổ sung từ xe-buyt.com.',
                'Routes and stops © OpenStreetMap contributors (ODbL). Extra schedules from xe-buyt.com.',
              ),
            ),
            subtitle: Text(
              tr(
                'Vị trí xe và giờ đến thực tế chưa có vì chưa có nguồn dữ liệu công khai.',
                'Live vehicle positions and arrivals are unavailable: no open feed exists.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

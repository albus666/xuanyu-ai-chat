import 'package:flutter/material.dart';
import 'package:xuanyu/shared/widgets/account_session_guard.dart';
import 'package:xuanyu/features/merit/models/merit_models.dart';
import 'package:xuanyu/features/merit/services/merit_auto_knock.dart';
import 'package:xuanyu/features/merit/services/merit_storage_service.dart';

class MeritSettingsPage extends StatefulWidget {
  const MeritSettingsPage(
      {super.key, required this.data, required this.onChanged});

  final MeritSaveData data;
  final VoidCallback onChanged;

  @override
  State<MeritSettingsPage> createState() => _MeritSettingsPageState();
}

class _MeritSettingsPageState extends State<MeritSettingsPage>
    with AccountSessionGuard<MeritSettingsPage> {
  MeritSaveData get d => widget.data;

  Future<void> _save() async {
    if (!accountSession.current) return;
    await MeritStorageService.save(d);
    if (!mounted || !accountSession.current) return;
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (!accountSession.current) return accountChangedPage;
    return Scaffold(
      backgroundColor: MeritColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('木鱼设置',
            style: TextStyle(color: MeritColors.textPrimary)),
        iconTheme: const IconThemeData(color: MeritColors.textPrimary),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('敲击音效',
                style: TextStyle(color: MeritColors.textPrimary)),
            subtitle: const Text('柔和木质音，连续敲击会自动变轻',
                style: TextStyle(color: MeritColors.textSecondary)),
            value: d.soundEnabled,
            activeThumbColor: MeritColors.gold,
            onChanged: (v) async {
              d.soundEnabled = v;
              await _save();
            },
          ),
          if (d.soundEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.volume_down_outlined,
                      color: MeritColors.textSecondary),
                  Expanded(
                    child: Slider(
                      value: d.soundVolume,
                      min: 0.2,
                      max: 1.0,
                      divisions: 8,
                      activeColor: MeritColors.gold,
                      label: '${(d.soundVolume * 100).round()}%',
                      onChanged: (value) {
                        setState(() => d.soundVolume = value);
                      },
                      onChangeEnd: (_) => _save(),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${(d.soundVolume * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: MeritColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            title: const Text('震动反馈',
                style: TextStyle(color: MeritColors.textPrimary)),
            value: d.vibrationEnabled,
            activeThumbColor: MeritColors.gold,
            onChanged: (v) async {
              d.vibrationEnabled = v;
              await _save();
            },
          ),
          ListTile(
            title: const Text('自动敲击速度',
                style: TextStyle(color: MeritColors.textPrimary)),
            subtitle: const Text('按自己的节奏调节，默认每秒约 3.6 次',
                style: TextStyle(color: MeritColors.textSecondary)),
            trailing: Text(
              '${meritKnocksPerSecond(d).toStringAsFixed(1)} 次/秒',
              style: const TextStyle(color: MeritColors.gold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Text('慢',
                    style: TextStyle(color: MeritColors.textSecondary)),
                Expanded(
                  child: Slider(
                    value: meritKnocksPerSecond(d).clamp(1.5, 6.0),
                    min: 1.5,
                    max: 6,
                    divisions: 18,
                    activeColor: MeritColors.gold,
                    label: '${meritKnocksPerSecond(d).toStringAsFixed(1)} 次/秒',
                    onChanged: (value) {
                      setState(() => setMeritKnocksPerSecond(d, value));
                    },
                    onChangeEnd: (_) => _save(),
                  ),
                ),
                const Text('快',
                    style: TextStyle(color: MeritColors.textSecondary)),
              ],
            ),
          ),
          const Divider(color: MeritColors.card),
          ListTile(
            title: const Text('累计总敲击',
                style: TextStyle(color: MeritColors.textSecondary)),
            trailing: Text('${d.totalTaps}',
                style: const TextStyle(color: MeritColors.gold)),
          ),
          ListTile(
            title: const Text('今日敲击',
                style: TextStyle(color: MeritColors.textSecondary)),
            trailing: Text('${d.todayTaps}',
                style: const TextStyle(color: MeritColors.gold)),
          ),
        ],
      ),
    );
  }
}

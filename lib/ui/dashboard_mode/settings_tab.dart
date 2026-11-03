import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../providers/app_state_provider.dart';
import '../../services/music_player_service.dart';
import '../../services/txt_logger_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final TextEditingController _focusCtrl = TextEditingController();
  final TextEditingController _shortCtrl = TextEditingController();
  final TextEditingController _longCtrl = TextEditingController();
  final TextEditingController _gcalTokenCtrl = TextEditingController();
  String _txtPreview = '';

  @override
  void initState() {
    super.initState();
    final p = context.read<AppStateProvider>();
    _focusCtrl.text = p.focusDurationMinutes.toString();
    _shortCtrl.text = p.shortBreakDurationMinutes.toString();
    _longCtrl.text = p.longBreakDurationMinutes.toString();
    _gcalTokenCtrl.text = p.gcalToken;
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final c = await TxtLoggerService.instance.readLogFileContent();
    if (mounted) setState(() => _txtPreview = c);
  }

  @override
  void dispose() {
    _focusCtrl.dispose();
    _shortCtrl.dispose();
    _longCtrl.dispose();
    _gcalTokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final music = context.watch<MusicPlayerService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ۱. زمان‌بندی پومودورو
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('زمان‌بندی پومودورو Freedium',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _focusCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'تمرکز (دقیقه)',
                              border: OutlineInputBorder(),
                              isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _shortCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'استراحت ۵ دقیقه‌ای',
                              border: OutlineInputBorder(),
                              isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _longCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'استراحت ۶۰ دقیقه‌ای زندگی',
                              border: OutlineInputBorder(),
                              isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          await provider.updateTimerSettings(
                            focusMinutes: int.tryParse(_focusCtrl.text) ?? 25,
                            shortBreakMinutes:
                                int.tryParse(_shortCtrl.text) ?? 5,
                            longBreakMinutes:
                                int.tryParse(_longCtrl.text) ?? 60,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تنظیمات زمان ذخیره شد.')),
                            );
                          }
                        },
                        child: const Text('ذخیره زمان'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ۲. پلیر موسیقی تمرکز ADHD
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('موسیقی تمرکز ویژه ADHD',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('تعداد ترک‌های بارگذاری‌شده: ${music.tracks.length}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('انتخاب پوشه موسیقی از هارد'),
                        onPressed: () async {
                          final selectedFolder =
                              await FilePicker.platform.getDirectoryPath();
                          if (selectedFolder != null) {
                            final count = await music
                                .loadTracksFromFolder(selectedFolder);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          '$count فایل صوتی بارگذاری شد.')));
                            }
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SwitchListTile(
                          dense: true,
                          title: const Text(
                              'پخش موسیقی در زمان استراحت (پیش‌فرض: خاموش)',
                              style: TextStyle(fontSize: 12)),
                          value: music.playDuringBreaks,
                          onChanged: music.setPlayDuringBreaks,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ۳. تنظیمات تقویم گوگل
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اتصال به Google Calendar API v3',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _gcalTokenCtrl,
                          decoration: const InputDecoration(
                              labelText: 'OAuth 2.0 Access Token گوگل',
                              border: OutlineInputBorder(),
                              isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          await provider.updateGCalToken(_gcalTokenCtrl.text);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('توکن گوگل ذخیره شد.')),
                            );
                          }
                        },
                        child: const Text('ذخیره توکن'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ۴. فایل لاگ متنی
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('فایل متنی خودکار ChronoFlow_WorkLog.txt',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('مسیر: ${provider.txtLogPath}',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 11, color: AppColors.focus)),
                  const SizedBox(height: 8),
                  Container(
                    height: 120,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6)),
                    child: SingleChildScrollView(
                      child: Text(_txtPreview,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 10.5, color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

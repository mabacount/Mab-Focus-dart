// تنظیمات تایمرها، مسیر فایل متنی و همگام‌سازی تقویم
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../providers/app_state_provider.dart';
import '../../services/txt_logger_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController _focusCtrl;
  late TextEditingController _shortBreakCtrl;
  late TextEditingController _longBreakCtrl;
  late TextEditingController _gcalTokenCtrl;
  String _syncLevel = 'task';
  String _txtPreviewContent = '';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final provider = context.read<AppStateProvider>();
      _focusCtrl =
          TextEditingController(text: provider.focusDurationMinutes.toString());
      _shortBreakCtrl = TextEditingController(
          text: provider.shortBreakDurationMinutes.toString());
      _longBreakCtrl = TextEditingController(
          text: provider.longBreakDurationMinutes.toString());
      _gcalTokenCtrl = TextEditingController(text: provider.gcalToken);
      _syncLevel = provider.gcalSyncLevel;
      _loadTxtPreview();
      _initialized = true;
    }
  }

  Future<void> _loadTxtPreview() async {
    final content = await TxtLoggerService.instance.readLogFileContent();
    if (mounted) {
      setState(() {
        _txtPreviewContent = content;
      });
    }
  }

  @override
  void dispose() {
    _focusCtrl.dispose();
    _shortBreakCtrl.dispose();
    _longBreakCtrl.dispose();
    _gcalTokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ۱. تنظیمات زمان‌بندی چرخه پومودورو
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تنظیمات زمان‌بندی موتور پومودورو (Freedium)',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _focusCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'مدت تمرکز (دقیقه - پیش‌فرض ۲۵)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _shortBreakCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'استراحت کوتاه (دقیقه - پیش‌فرض ۵)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _longBreakCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText:
                                    'استراحت طولانی ست چهارم (دقیقه - پیش‌فرض ۶۰)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('ذخیره زمان‌بندی'),
                            onPressed: () async {
                              final f = int.tryParse(_focusCtrl.text) ?? 25;
                              final s = int.tryParse(_shortBreakCtrl.text) ?? 5;
                              final l = int.tryParse(_longBreakCtrl.text) ?? 60;
                              await provider.updateTimerSettings(
                                focusMinutes: f.clamp(1, 240),
                                shortBreakMinutes: s.clamp(1, 120),
                                longBreakMinutes: l.clamp(1, 240),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('تنظیمات تایمر ذخیره شد.')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ۲. تنظیمات فایل متنی خودکار (.txt) و پیش‌نمایش زنده
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'فایل گزارش متنی خودکار (ChronoFlow_WorkLog.txt)',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'مسیر فعلی ذخیره خودکار: ${provider.txtLogPath}',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 12, color: AppColors.focus),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('تغییر مسیر فایل .txt'),
                            onPressed: () async {
                              final selected = await FilePicker.saveFile(
                                dialogTitle: 'انتخاب مسیر فایل لاگ متنی خودکار',
                                fileName: AppDefaults.defaultTxtFileName,
                                type: FileType.custom,
                                allowedExtensions: ['txt'],
                              );
                              if (selected != null) {
                                await provider.updateTxtLogPath(selected);
                                await _loadTxtPreview();
                              }
                            },
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.refresh_rounded),
                            label:
                                const Text('به‌روزرسانی پیش‌نمایش فایل متنی'),
                            onPressed: () async {
                              await TxtLoggerService.instance.syncTxtFile();
                              await _loadTxtPreview();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 180,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _txtPreviewContent,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ۳. تنظیمات همگام‌سازی با تقویم گوگل
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'همگام‌سازی خودکار با تقویم گوگل (Google Calendar API)',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _gcalTokenCtrl,
                              decoration: const InputDecoration(
                                labelText: 'OAuth 2.0 Access Token تقویم گوگل',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _syncLevel,
                              decoration: const InputDecoration(
                                labelText: 'سطح همگام‌سازی',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              dropdownColor: AppColors.surfaceElevated,
                              items: const [
                                DropdownMenuItem(
                                    value: 'task',
                                    child: Text('سطح تسک (Task-Level)')),
                                DropdownMenuItem(
                                    value: 'pomodoro',
                                    child: Text('سطح پومودورو')),
                                DropdownMenuItem(
                                    value: 'both', child: Text('هر دو (Both)')),
                                DropdownMenuItem(
                                    value: 'disabled', child: Text('غیرفعال')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _syncLevel = val);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.cloud_sync_rounded),
                            label: const Text('ذخیره تنظیمات تقویم'),
                            onPressed: () async {
                              await provider.updateGCalSettings(
                                token: _gcalTokenCtrl.text,
                                syncLevel: _syncLevel,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('تنظیمات تقویم گوگل ذخیره شد.')),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

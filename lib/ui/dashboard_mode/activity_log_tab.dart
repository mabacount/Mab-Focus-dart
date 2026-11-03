import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../models/task_log_entry.dart';
import '../../providers/app_state_provider.dart';

class ActivityLogTab extends StatefulWidget {
  const ActivityLogTab({super.key});

  @override
  State<ActivityLogTab> createState() => _ActivityLogTabState();
}

class _ActivityLogTabState extends State<ActivityLogTab> {
  String _filterType = 'all'; // all | work | break | stopwatch
  bool _onlyToday = false;

  String _formatDuration(int seconds) {
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<TaskLogEntry> _filter(List<TaskLogEntry> list) {
    final now = DateTime.now();
    return list.where((l) {
      if (_onlyToday) {
        if (l.startTime.year != now.year ||
            l.startTime.month != now.month ||
            l.startTime.day != now.day) {
          return false;
        }
      }
      if (_filterType == 'work') {
        return l.isWork;
      }
      if (_filterType == 'break') {
        return l.isBreakEntry;
      }
      if (_filterType == 'stopwatch') {
        return l.isStopwatch;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final filtered = _filter(provider.taskLogs);
    final totalSec = filtered.fold<int>(0, (sum, i) => sum + i.durationSeconds);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('امروز'),
                    selected: _onlyToday,
                    onSelected: (v) => setState(() => _onlyToday = v),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _filterType,
                    isExpanded: false,
                    dropdownColor: AppColors.surfaceElevated,
                    items: const [
                      DropdownMenuItem(
                          value: 'all', child: Text('همه رکوردها')),
                      DropdownMenuItem(
                          value: 'work', child: Text('فقط کارکرد')),
                      DropdownMenuItem(
                          value: 'break', child: Text('فقط استراحت‌ها')),
                      DropdownMenuItem(
                          value: 'stopwatch',
                          child: Text('فقط کرنومتر (خواب)')),
                    ],
                    onChanged: (v) => setState(() => _filterType = v ?? 'all'),
                  ),
                  const Spacer(),
                  Text('مجموع: ${_formatDuration(totalSec)}',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.breakTime),
                    icon: const Icon(Icons.table_view_rounded, size: 16),
                    label: const Text('خروجی اکسل ۱۵ ستونی (.xlsx)'),
                    onPressed: () async {
                      final path = await provider.exportLogsToExcel(filtered);
                      if (context.mounted && path != null) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('فایل در مسیر زیر ذخیره شد: $path')));
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('هیچ رکوردی یافت نشد.',
                        style: TextStyle(color: AppColors.textMuted)))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final log = filtered[i];
                      return Card(
                        child: ListTile(
                          dense: true,
                          title: Row(
                            children: [
                              Text(log.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              if (log.isEdited) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message:
                                      'زمان اولیه: ${_formatDuration(log.originalDurationSeconds ?? log.durationSeconds)}',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: AppColors.edited.withAlpha(40),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Text('[Edited]',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.edited,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${DateFormat('yyyy/MM/dd HH:mm').format(log.startTime)} | نوع: ${log.entryType}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_formatDuration(log.durationSeconds),
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 16, color: Colors.redAccent),
                                onPressed: () => provider.deleteTaskLog(log.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

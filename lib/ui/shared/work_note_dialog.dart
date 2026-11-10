import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/constants.dart';
import '../../core/jalali_date.dart';
import '../../core/platform_helper.dart';
import '../../models/pomodoro_state.dart';
import '../../models/session_note.dart';
import '../../providers/app_state_provider.dart';

class WorkNoteDialog extends StatefulWidget {
  final bool asBottomSheet;
  const WorkNoteDialog({super.key, this.asBottomSheet = false});

  /// باز کردن پنجره مستقل روی دسکتاپ یا ModalBottomSheet روی اندروید با اتصال سه‌گانه
  static Future<void> openStandalone(BuildContext context) async {
    final provider = context.read<AppStateProvider>();
    final active = provider.activeRecord;
    final outcome = provider.activeOutcome;
    final project = provider.getProjectById(active?.projectId);

    if (PlatformHelper.isDesktop) {
      try {
        final window = await WindowController.create(
          WindowConfiguration(
            hiddenAtLaunch: true,
            arguments: jsonEncode({
              'type': 'work_note',
              'realm': (active?.realm ?? provider.pomodoroState.realm).dbValue,
              'timeRecordId': active?.id,
              'outcomeId': active?.outcomeId,
              'projectId': active?.projectId,
              'taskTitle': outcome?.title ??
                  (active?.titleSnapshot.isNotEmpty == true
                      ? active!.titleSnapshot
                      : AppDefaults.untitledTaskTitle),
              'projectName': project?.name,
              'projectColorHex': project?.colorHex,
            }),
          ),
        );
        await window.show();
        return;
      } catch (e) {
        debugPrint('Failed to open standalone multi-window: $e');
      }
    }

    // در اندروید (چالش ۳): نمایش به صورت ModalBottomSheet زیبا و واکنش‌گرا
    if (context.mounted && !PlatformHelper.isDesktop) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const WorkNoteDialog(asBottomSheet: true),
      );
      return;
    }

    if (context.mounted) {
      await show(context);
    }
  }

  static Future<void> show(BuildContext context) async {
    final provider = context.read<AppStateProvider>();
    final posture = provider.pomodoroState.windowPosture;
    final isCompactWindow = posture != WindowPosture.dashboard;

    Size? originalSize;
    Offset? originalPos;

    if (isCompactWindow && PlatformHelper.isDesktop) {
      try {
        originalSize = await windowManager.getSize();
        originalPos = await windowManager.getPosition();

        const double targetW = 420.0;
        const double targetH = 540.0;

        final double cx = originalPos.dx + (originalSize.width / 2.0);
        final double cy = originalPos.dy + (originalSize.height / 2.0);

        final display = await screenRetriever.getPrimaryDisplay();
        final screenLeft = display.visiblePosition?.dx ?? 0.0;
        final screenTop = display.visiblePosition?.dy ?? 0.0;
        final screenWidth = display.size.width;
        final screenHeight = display.size.height;

        double targetX = cx - (targetW / 2.0);
        double targetY = cy - (targetH / 2.0);

        targetX = targetX.clamp(screenLeft, screenLeft + screenWidth - targetW);
        targetY = targetY.clamp(screenTop, screenTop + screenHeight - targetH);

        await windowManager.setSize(const Size(targetW, targetH));
        await windowManager.setPosition(Offset(targetX, targetY));
      } catch (_) {}
    }

    if (!context.mounted) return;

    provider.setWorkNoteOpen(true);

    try {
      await showDialog(
        context: context,
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        builder: (_) => const WorkNoteDialog(),
      );
    } finally {
      provider.setWorkNoteOpen(false);
      if (isCompactWindow && PlatformHelper.isDesktop) {
        try {
          if (originalSize != null && originalPos != null) {
            await windowManager.setSize(originalSize);
            await windowManager.setPosition(originalPos);
          } else {
            await PlatformHelper.updateFloatingSheetExpansion(
                provider.isQuickMenuExpanded);
          }
        } catch (_) {}
      }
    }
  }

  @override
  State<WorkNoteDialog> createState() => _WorkNoteDialogState();
}

class _WorkNoteDialogState extends State<WorkNoteDialog> {
  final TextEditingController _contentController = TextEditingController();
  final List<String> _attachedImagePaths = [];
  SessionNoteType _noteType = SessionNoteType.report;
  bool _isSaving = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<String> _getMediaDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final mediaDir =
        Directory(p.join(supportDir.path, 'MabFocus', 'work_notes_media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir.path;
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final mediaDir = await _getMediaDir();
        final filename =
            'note_paste_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = p.join(mediaDir, filename);
        await File(filePath).writeAsBytes(imageBytes);

        setState(() {
          _attachedImagePaths.add(filePath);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تصویر از کلیپ‌بورد الصاق شد.'),
              duration: Duration(seconds: 2),
              backgroundColor: AppColors.lifeGreen,
            ),
          );
        }
        return;
      }

      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        final validImageExtensions = [
          '.png',
          '.jpg',
          '.jpeg',
          '.webp',
          '.bmp',
          '.gif'
        ];
        int added = 0;
        for (final path in files) {
          final ext = p.extension(path).toLowerCase();
          if (validImageExtensions.contains(ext)) {
            _attachedImagePaths.add(path);
            added++;
          }
        }
        if (added > 0) {
          setState(() {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$added فایل تصویر از کلیپ‌بورد الصاق شد.'),
                duration: const Duration(seconds: 2),
                backgroundColor: AppColors.lifeGreen,
              ),
            );
          }
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'تصویری در کلیپ‌بورد یافت نشد. می‌توانید از دکمه انتخاب عکس استفاده کنید.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در الصاق از کلیپ‌بورد: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickImageFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.paths.isNotEmpty) {
        setState(() {
          for (final path in result.paths) {
            if (path != null && path.isNotEmpty) {
              _attachedImagePaths.add(path);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در انتخاب فایل: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _saveNote() async {
    final text = _contentController.text.trim();
    if (text.isEmpty && _attachedImagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً متن یادداشت یا حداقل یک تصویر وارد کنید.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final provider = context.read<AppStateProvider>();
      final active = provider.activeRecord;
      final now = DateTime.now();

      final note = SessionNote(
        id: const Uuid().v4(),
        realm: active?.realm ?? provider.pomodoroState.realm,
        noteType: _noteType,
        timeRecordId: active?.id,
        outcomeId: active?.outcomeId,
        projectId: active?.projectId,
        content: text,
        imagePaths: List.from(_attachedImagePaths),
        createdAt: now,
      );

      await provider.saveSessionNote(note);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('یادداشت با اتصال سه‌گانه ثبت شد.'),
            backgroundColor: AppColors.lifeGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Color _parseHex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.workBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppStateProvider>();
    final active = provider.activeRecord;
    final outcome = provider.activeOutcome;
    final activeRealm = active?.realm ?? provider.pomodoroState.realm;
    final realmColor = activeRealm == AppRealm.life
        ? AppColors.lifeGreen
        : AppColors.workBlue;
    final project = provider.getProjectById(active?.projectId);

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dateStr = JalaliDate.formatWithWeekDay(now);

    final displayTitle = outcome?.title ??
        (active?.titleSnapshot.isNotEmpty == true
            ? active!.titleSnapshot
            : AppDefaults.untitledTaskTitle);

    final contentBody = Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: widget.asBottomSheet
            ? (16 + MediaQuery.of(context).viewInsets.bottom)
            : 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) {
              if (!widget.asBottomSheet && PlatformHelper.isDesktop) {
                windowManager.startDragging();
              }
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: realmColor.withAlpha(32),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: realmColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ثبت یادداشت حین فعالیت (${activeRealm.labelFa})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dateStr — ساعت $timeStr',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'بستن',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // کپسول کانتکست سه‌گانه
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link_rounded, size: 14, color: realmColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayTitle,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (project != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _parseHex(project.colorHex).withAlpha(40),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              project.name,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: _parseHex(project.colorHex),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // نوع یادداشت (Plan | Challenge | Report | Idea | General)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: SessionNoteType.values.map((t) {
                      final isSelected = _noteType == t;
                      return ChoiceChip(
                        avatar: Icon(t.icon,
                            size: 14,
                            color: isSelected ? Colors.white : t.color),
                        label: Text(t.labelFa,
                            style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textPrimary)),
                        selected: isSelected,
                        selectedColor: t.color,
                        backgroundColor: AppColors.surfaceElevated,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _noteType = t),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _contentController,
                    maxLines: 4,
                    minLines: 3,
                    style:
                        const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText:
                          'برنامه، چالش، گزارش پیشرفت یا ایده لحظه‌ای را بنویسید...',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: realmColor),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (PlatformHelper.isDesktop)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                          ),
                          icon: Icon(Icons.paste_rounded,
                              size: 15, color: realmColor),
                          label: const Text('الصاق تصویر (Ctrl+V)',
                              style: TextStyle(fontSize: 11)),
                          onPressed: _pasteFromClipboard,
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                        ),
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 15, color: AppColors.textSecondary),
                        label: const Text('انتخاب عکس',
                            style: TextStyle(fontSize: 11)),
                        onPressed: _pickImageFile,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_attachedImagePaths.isNotEmpty)
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _attachedImagePaths.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 8),
                        itemBuilder: (ctx, idx) {
                          final path = _attachedImagePaths[idx];
                          final file = File(path);
                          return Stack(
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border),
                                  color: Colors.black26,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: file.existsSync()
                                    ? Image.file(file, fit: BoxFit.cover)
                                    : const Icon(
                                        Icons.broken_image_rounded,
                                        size: 24,
                                        color: AppColors.textMuted),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _attachedImagePaths.removeAt(idx);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.black87,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close_rounded,
                                        size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('انصراف',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: realmColor,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: const Text('ثبت یادداشت',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _isSaving ? null : _saveNote,
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.asBottomSheet) {
      return Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.border, width: 1.2)),
        ),
        child: contentBody,
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _pasteFromClipboard,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: AppColors.surface,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border, width: 1.2),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
            child: contentBody,
          ),
        ),
      ),
    );
  }
}

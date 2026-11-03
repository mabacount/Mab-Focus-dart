// مدیریت درختی پروژه‌ها و کلیدهای احتساب استراحت
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants.dart';
import '../../providers/app_state_provider.dart';

class ProjectStudioTab extends StatefulWidget {
  const ProjectStudioTab({super.key});

  @override
  State<ProjectStudioTab> createState() => _ProjectStudioTabState();
}

class _ProjectStudioTabState extends State<ProjectStudioTab> {
  final TextEditingController _macroNameCtrl = TextEditingController();
  final TextEditingController _subNameCtrl = TextEditingController();
  final TextEditingController _tagNameCtrl = TextEditingController();

  bool _newMacroCountShortBreak = false;
  bool _newMacroCountLongBreak = false;
  String? _selectedMacroForSub;

  @override
  void dispose() {
    _macroNameCtrl.dispose();
    _subNameCtrl.dispose();
    _tagNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final macros = provider.macroProjects;
        final tags = provider.phaseTags;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ۱. کارت تعریف پروژه کلان و قوانین احتساب استراحت
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تعریف پروژه کلان جدید و سیاست محاسبه زمان استراحت',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _macroNameCtrl,
                              decoration: const InputDecoration(
                                labelText:
                                    'نام پروژه کلان (مثلاً: سامانه مالی کارفرما الف)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('افزودن پروژه کلان'),
                            onPressed: () async {
                              if (_macroNameCtrl.text.trim().isEmpty) return;
                              await provider.saveProject(
                                name: _macroNameCtrl.text.trim(),
                                countShortBreaksAsWork:
                                    _newMacroCountShortBreak,
                                countLongBreaksAsWork: _newMacroCountLongBreak,
                              );
                              _macroNameCtrl.clear();
                              setState(() {
                                _newMacroCountShortBreak = false;
                                _newMacroCountLongBreak = false;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'محاسبه استراحت‌های کوتاه (۵ دقیقه‌ای) جزو ساعت کاری این پروژه',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: _newMacroCountShortBreak,
                        onChanged: (val) =>
                            setState(() => _newMacroCountShortBreak = val),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'محاسبه استراحت‌های طولانی (۶۰ دقیقه‌ای پایان چرخه) جزو ساعت کاری این پروژه',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: _newMacroCountLongBreak,
                        onChanged: (val) =>
                            setState(() => _newMacroCountLongBreak = val),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ۲. کارت افزودن زیرپروژه به پروژه‌های کلان
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تعریف پروژه زیرمجموعه (Sub-Project)',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: macros
                                      .any((m) => m.id == _selectedMacroForSub)
                                  ? _selectedMacroForSub
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'انتخاب پروژه کلان مادر',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              dropdownColor: AppColors.surfaceElevated,
                              items: macros
                                  .map((m) => DropdownMenuItem<String?>(
                                      value: m.id, child: Text(m.name)))
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedMacroForSub = val),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _subNameCtrl,
                              decoration: const InputDecoration(
                                labelText:
                                    'نام زیرپروژه (مثلاً: ماژول احراز هویت)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            icon: const Icon(
                                Icons.subdirectory_arrow_left_rounded),
                            label: const Text('افزودن زیرپروژه'),
                            onPressed: () async {
                              if (_selectedMacroForSub == null ||
                                  _subNameCtrl.text.trim().isEmpty) {
                                return;
                              }
                              await provider.saveProject(
                                name: _subNameCtrl.text.trim(),
                                parentId: _selectedMacroForSub,
                              );
                              _subNameCtrl.clear();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ۳. درخت پروژه‌های کلان و ویرایش زنده قانون استراحت هر پروژه
              const Text(
                'فهرست پروژه‌های کلان و زیرمجموعه‌ها',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...macros.map((macro) {
                final subProjects = provider.getSubProjects(macro.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    title: Text(macro.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'زیرپروژه‌ها: ${subProjects.length}  |  استراحت کوتاه جزو کار: ${macro.countShortBreaksAsWork ? 'بله' : 'خیر'}  |  استراحت طولانی جزو کار: ${macro.countLongBreaksAsWork ? 'بله' : 'خیر'}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.redAccent),
                      onPressed: () => provider.deleteProject(macro.id),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            SwitchListTile(
                              dense: true,
                              title: const Text(
                                  'احتساب استراحت ۵ دقیقه‌ای جزو کارکرد این پروژه'),
                              value: macro.countShortBreaksAsWork,
                              onChanged: (val) {
                                provider.saveProject(
                                  id: macro.id,
                                  name: macro.name,
                                  countShortBreaksAsWork: val,
                                  countLongBreaksAsWork:
                                      macro.countLongBreaksAsWork,
                                  colorHex: macro.colorHex,
                                );
                              },
                            ),
                            SwitchListTile(
                              dense: true,
                              title: const Text(
                                  'احتساب استراحت ۶۰ دقیقه‌ای جزو کارکرد این پروژه'),
                              value: macro.countLongBreaksAsWork,
                              onChanged: (val) {
                                provider.saveProject(
                                  id: macro.id,
                                  name: macro.name,
                                  countShortBreaksAsWork:
                                      macro.countShortBreaksAsWork,
                                  countLongBreaksAsWork: val,
                                  colorHex: macro.colorHex,
                                );
                              },
                            ),
                            if (subProjects.isNotEmpty)
                              const Divider(color: AppColors.border),
                            ...subProjects.map(
                              (sub) => ListTile(
                                dense: true,
                                leading: const Icon(
                                    Icons.subdirectory_arrow_left_rounded,
                                    size: 18),
                                title: Text(sub.name),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close,
                                      size: 16, color: Colors.redAccent),
                                  onPressed: () =>
                                      provider.deleteProject(sub.id),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),

              // ۴. مدیریت تگ‌های فاز کاری
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'مدیریت تگ‌های فاز کاری و وضعیت',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tagNameCtrl,
                              decoration: const InputDecoration(
                                labelText:
                                    'عنوان تگ جدید (مثلاً: تست و بررسی کیفیت)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.label_outline_rounded),
                            label: const Text('افزودن تگ'),
                            onPressed: () async {
                              if (_tagNameCtrl.text.trim().isEmpty) return;
                              await provider.savePhaseTag(
                                  name: _tagNameCtrl.text.trim());
                              _tagNameCtrl.clear();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tags
                            .map(
                              (t) => Chip(
                                label: Text(t.name),
                                backgroundColor: AppColors.surfaceElevated,
                                onDeleted: () => provider.deletePhaseTag(t.id),
                              ),
                            )
                            .toList(),
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

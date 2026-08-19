import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../models/period_report.dart';

class ReportArchiveScreen extends ConsumerStatefulWidget {
  const ReportArchiveScreen({super.key});

  @override
  ConsumerState<ReportArchiveScreen> createState() =>
      _ReportArchiveScreenState();
}

class _ReportArchiveScreenState extends ConsumerState<ReportArchiveScreen> {
  String _query = '';
  String? _type;

  @override
  Widget build(BuildContext context) {
    ref.watch(dataRevisionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('أرشيف التقارير')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'بحث بالتاريخ أو النطاق',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: _type,
                  decoration: const InputDecoration(labelText: 'نوع التقرير'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('كل الأنواع')),
                    DropdownMenuItem(value: 'daily', child: Text('يومي')),
                    DropdownMenuItem(value: 'weekly', child: Text('أسبوعي')),
                    DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                    DropdownMenuItem(value: 'term', child: Text('فصل دراسي')),
                    DropdownMenuItem(value: 'custom', child: Text('مخصص')),
                  ],
                  onChanged: (value) => setState(() => _type = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<ReportArchiveEntry>>(
              future: ref
                  .read(reportRepositoryProvider)
                  .archives(query: _query, reportType: _type),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'لا توجد ملفات مؤرشفة. يتم حفظ PDF دائمًا عند إنشائه من التقارير.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final exists = File(entry.filePath).existsSync();
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE7F2F7),
                          child: Icon(
                            Icons.archive_outlined,
                            color: AppColors.blue,
                          ),
                        ),
                        title: Text(
                          '${_typeLabel(entry.reportType)} — ${entry.periodStart}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${entry.periodStart} إلى ${entry.periodEnd}\nأنشئه ${entry.createdBy} في ${DateFormat('dd/MM/yyyy hh:mm a', 'ar').format(entry.createdAt.toLocal())}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: exists ? 'مشاركة الملف' : 'الملف غير موجود',
                          onPressed: !exists
                              ? null
                              : () => SharePlus.instance.share(
                                  ShareParams(files: [XFile(entry.filePath)]),
                                ),
                          icon: const Icon(Icons.share_outlined),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(String value) => switch (value) {
    'daily' => 'يومي',
    'weekly' => 'أسبوعي',
    'monthly' => 'شهري',
    'term' => 'فصل دراسي',
    _ => 'مخصص',
  };
}

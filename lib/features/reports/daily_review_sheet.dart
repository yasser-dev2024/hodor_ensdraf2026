import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/daily_preparation.dart';

class DailyReviewSheet extends StatelessWidget {
  const DailyReviewSheet({
    required this.result,
    required this.onIssueTap,
    super.key,
  });

  final DailyReviewResult result;
  final ValueChanged<DailyReviewIssue> onIssueTap;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: .88,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade200,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color:
                        (result.isClean ? AppColors.present : AppColors.excused)
                            .withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    result.isClean
                        ? Icons.verified_rounded
                        : Icons.fact_check_outlined,
                    color: result.isClean
                        ? AppColors.present
                        : AppColors.excused,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'راجع لي اليوم',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE d MMMM y', 'ar').format(result.date),
                        style: const TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F7FA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.visibility_outlined, color: AppColors.blue),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'فحص وتنبيه فقط — لم يتم تعديل أو حذف أي سجل.',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            if (result.isClean)
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 28,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F7F1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.present.withValues(alpha: .28),
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.task_alt_rounded,
                          color: AppColors.present,
                          size: 58,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'تمت مراجعة بيانات اليوم — لا توجد تعارضات',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.present,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'نتائج المراجعة (${result.issues.length})',
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Text(
                    'اضغط للانتقال',
                    style: TextStyle(fontSize: 10, color: Colors.blueGrey),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: result.issues.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final issue = result.issues[index];
                    final (color, icon) = _appearance(issue.kind);
                    return Material(
                      color: color.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: issue.canNavigate
                            ? () => onIssueTap(issue)
                            : null,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: color.withValues(alpha: .25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 39,
                                height: 39,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(icon, color: color, size: 21),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      issue.title,
                                      style: const TextStyle(
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      issue.details,
                                      style: const TextStyle(
                                        color: Colors.blueGrey,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (issue.canNavigate)
                                Icon(Icons.chevron_left_rounded, color: color),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  static (Color, IconData) _appearance(DailyReviewIssueKind kind) =>
      switch (kind) {
        DailyReviewIssueKind.incompleteClass => (
          AppColors.excused,
          Icons.meeting_room_outlined,
        ),
        DailyReviewIssueKind.unresolvedStudent => (
          AppColors.excused,
          Icons.person_search_rounded,
        ),
        DailyReviewIssueKind.conflictingStatuses => (
          AppColors.absent,
          Icons.compare_arrows_rounded,
        ),
        DailyReviewIssueKind.duplicateRecord => (
          AppColors.absent,
          Icons.content_copy_rounded,
        ),
        DailyReviewIssueKind.missingBasicData => (
          AppColors.absent,
          Icons.assignment_late_outlined,
        ),
        DailyReviewIssueKind.illogicalData => (
          AppColors.absent,
          Icons.warning_amber_rounded,
        ),
      };
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';

class WeeklyHealthReport {
  const WeeklyHealthReport({
    required this.headline,
    required this.level,
    required this.score,
    required this.trend,
    required this.keywords,
    required this.overview,
    required this.focuses,
    required this.plan,
    required this.boundary,
  });

  final String headline;
  final String level;
  final int score;
  final String trend;
  final List<String> keywords;
  final String overview;
  final List<Map<String, String>> focuses;
  final List<String> plan;
  final String boundary;

  factory WeeklyHealthReport.fromMap(Map<String, dynamic> map) {
    final rawFocuses = map['focuses'];
    return WeeklyHealthReport(
      headline: map['headline']?.toString().trim() ?? '本周状态总结',
      level: map['level']?.toString().trim() ?? '待观察',
      score: int.tryParse(map['score']?.toString() ?? '') ?? 0,
      trend: map['trend']?.toString().trim() ?? '首次周度记录',
      keywords: (map['keywords'] is List ? map['keywords'] as List : const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      overview: map['overview']?.toString().trim() ?? '',
      focuses: (rawFocuses is List ? rawFocuses : const [])
          .whereType<Map>()
          .map((item) => item
              .map((key, value) => MapEntry(key.toString(), value.toString())))
          .toList(growable: false),
      plan: (map['plan'] is List ? map['plan'] as List : const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      boundary: map['boundary']?.toString().trim() ?? '',
    );
  }
}

class _WeeklyQuestion {
  const _WeeklyQuestion(this.key, this.title, this.hint, this.icon);

  final String key;
  final String title;
  final String hint;
  final IconData icon;
}

const _questions = <_WeeklyQuestion>[
  _WeeklyQuestion(
      'sleep', '这一周，睡眠恢复得怎么样？', '留意入睡、夜醒和醒后的精神感受', Icons.bedtime_outlined),
  _WeeklyQuestion(
      'energy', '白天精力有没有明显下降？', '留意疲劳、注意力和忙碌后的恢复速度', Icons.bolt_outlined),
  _WeeklyQuestion(
      'digestion', '消化状态有没有反复波动？', '留意食欲、餐后感受与排便节律', Icons.spa_outlined),
  _WeeklyQuestion(
      'mood', '压力或情绪紧绷出现得多吗？', '留意低落、易怒、担忧与放松难度', Icons.waves_outlined),
  _WeeklyQuestion('discomfort', '身体不适对生活有影响吗？', '留意疼痛、头晕、心悸或其他持续不适',
      Icons.monitor_heart_outlined),
  _WeeklyQuestion('recovery', '活动或劳累后恢复得慢吗？', '留意运动、久坐和连续忙碌后的反馈',
      Icons.directions_walk_outlined),
];

const _optionLabels = <String>['没有变化', '偶尔出现', '反复出现', '明显影响'];

class WeeklyHealthCheckPage extends StatefulWidget {
  const WeeklyHealthCheckPage({super.key});

  @override
  State<WeeklyHealthCheckPage> createState() => _WeeklyHealthCheckPageState();
}

class _WeeklyHealthCheckPageState extends State<WeeklyHealthCheckPage> {
  static const _ink = Color(0xFF172A2C);
  static const _jade = Color(0xFF19BBB5);

  final Map<String, int> _answers = {};
  int _index = 0;
  bool _submitting = false;
  WeeklyHealthReport? _report;

  Future<void> _submit() async {
    if (_answers.length != _questions.length || _submitting) return;
    setState(() => _submitting = true);
    try {
      final response = await apiClient.post(
        '/api/fortune/health-archive/weekly',
        data: {'answers': _answers, 'checkInVersion': '1'},
      );
      final data = response.data is Map ? response.data['data'] : null;
      final report = data is Map ? data['report'] : null;
      if (mounted && report is Map) {
        setState(() => _report =
            WeeklyHealthReport.fromMap(Map<String, dynamic>.from(report)));
      }
    } on DioException catch (error) {
      final body = error.response?.data;
      final message = body is Map && body['message'] != null
          ? body['message'].toString()
          : '提交失败，请稍后重试';
      if (mounted) showAppToast(context, message);
    } catch (_) {
      if (mounted) showAppToast(context, '提交失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _select(int value) {
    final question = _questions[_index];
    setState(() => _answers[question.key] = value);
    if (_index < _questions.length - 1) {
      Future<void>.delayed(const Duration(milliseconds: 170), () {
        if (mounted && _questions[_index].key == question.key) {
          setState(() => _index++);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_report != null) {
      return WeeklyHealthReportView(
        report: _report!,
        onDone: () => Navigator.pop(context, true),
      );
    }
    final question = _questions[_index];
    final selected = _answers[question.key];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F9),
        elevation: 0,
        centerTitle: true,
        title: Text('本周状态', style: AppTextStyles.titleMedium),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${_index + 1}'.padLeft(2, '0'),
                          style: const TextStyle(
                              color: _ink,
                              fontSize: 30,
                              fontWeight: FontWeight.w800)),
                      Text(' / ${_questions.length.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: AppColors.textHint, fontSize: 14)),
                      const Spacer(),
                      const Text('约 30 秒',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (_index + 1) / _questions.length,
                      minHeight: 4,
                      color: _jade,
                      backgroundColor: const Color(0xFFE2E9E9),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: ListView(
                  key: ValueKey(question.key),
                  padding: const EdgeInsets.fromLTRB(22, 42, 22, 24),
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(question.icon, color: Colors.white, size: 26),
                    ),
                    const SizedBox(height: 24),
                    Text(question.title,
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            height: 1.35)),
                    const SizedBox(height: 10),
                    Text(question.hint,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.55)),
                    const SizedBox(height: 34),
                    ...List.generate(_optionLabels.length, (value) {
                      final active = selected == value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: active ? _ink : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            onTap: () => _select(value),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 17),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color:
                                      active ? _ink : const Color(0xFFE3E8E8),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(_optionLabels[value],
                                        style: TextStyle(
                                            color: active ? Colors.white : _ink,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  Icon(
                                    active
                                        ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: active
                                        ? const Color(0xFF75E3DC)
                                        : const Color(0xFFBEC8C8),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
              child: Row(
                children: [
                  if (_index > 0)
                    TextButton.icon(
                      onPressed: () => setState(() => _index--),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('上一项'),
                      style: TextButton.styleFrom(foregroundColor: _ink),
                    ),
                  const Spacer(),
                  if (_index == _questions.length - 1)
                    FilledButton(
                      onPressed:
                          selected == null || _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _ink,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 15),
                      ),
                      child: Text(_submitting ? '生成中…' : '生成本周总结'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WeeklyHealthReportView extends StatelessWidget {
  const WeeklyHealthReportView({
    super.key,
    required this.report,
    required this.onDone,
  });

  final WeeklyHealthReport report;
  final VoidCallback onDone;

  static const _ink = Color(0xFF172A2C);
  static const _jade = Color(0xFF24C2BA);

  Widget _sectionTitle(String index, String title) {
    return Row(
      children: [
        Text(index,
            style: const TextStyle(
                color: _jade, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                color: _ink, fontSize: 18, fontWeight: FontWeight.w800)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6F5),
        elevation: 0,
        centerTitle: true,
        title: Text('本周状态总结', style: AppTextStyles.titleMedium),
        actions: [
          TextButton(onPressed: onDone, child: const Text('完成')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('WEEKLY STATE',
                                style: TextStyle(
                                    color: _jade,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.7)),
                            const SizedBox(height: 13),
                            Text(report.headline,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    height: 1.35,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 9),
                            Text('${report.level} · ${report.trend}',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    height: 1.45)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .08),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _jade.withValues(alpha: .65), width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${report.score}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w800)),
                            const Text('状态分',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (report.keywords.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: report.keywords
                          .map((word) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .09),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(word,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12)),
                              ))
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 15),
            _ReportSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('01', '本周结论'),
                  const SizedBox(height: 12),
                  Text(report.overview,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.75)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ReportSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('02', '变化聚焦'),
                  const SizedBox(height: 14),
                  ...report.focuses.asMap().entries.map((entry) {
                    final focus = entry.value;
                    return Padding(
                      padding: EdgeInsets.only(
                          bottom:
                              entry.key == report.focuses.length - 1 ? 0 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(focus['title'] ?? '',
                                    style: const TextStyle(
                                        color: _ink,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE4F8F5),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(focus['status'] ?? '',
                                    style: const TextStyle(
                                        color: Color(0xFF087B78),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(focus['insight'] ?? '',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  height: 1.65)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ReportSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('03', '未来 7 天'),
                  const SizedBox(height: 14),
                  ...report.plan.asMap().entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 25,
                              height: 25,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                  color: _ink, shape: BoxShape.circle),
                              child: Text('${entry.key + 1}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(entry.value,
                                  style: const TextStyle(
                                      color: _ink,
                                      fontSize: 14,
                                      height: 1.55,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(report.boundary,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textHint, fontSize: 11, height: 1.5)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('完成并更新今日养生'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8ECEB)),
      ),
      child: child,
    );
  }
}

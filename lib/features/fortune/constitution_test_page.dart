import 'package:xuanyu/shared/widgets/bottom_footer_scroll_view.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide FormData;
import '../../app/common/routers/names.dart';
import '../../core/widgets/app_gpt_markdown.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/widgets/ai_generated_badge.dart';
import '../../shared/widgets/app_button.dart';
import 'ai_pulse_page.dart';
import 'constitution_test_data.dart';
import 'tongue_archive_page.dart';
import 'weekly_health_check_page.dart';

class ConstitutionTestPage extends StatefulWidget {
  const ConstitutionTestPage({super.key});

  @override
  State<ConstitutionTestPage> createState() => _ConstitutionTestPageState();
}

class _ConstitutionTestPageState extends State<ConstitutionTestPage> {
  bool _loading = true;
  Map<String, dynamic> _entries = {};
  Map<String, dynamic> _weeklyRefresh = {};

  @override
  void initState() {
    super.initState();
    _loadArchive();
  }

  Future<void> _loadArchive() async {
    try {
      final response = await apiClient.get('/api/fortune/health-archive');
      final data = response.data is Map ? response.data['data'] : null;
      if (mounted && data is Map) {
        setState(() {
          _entries =
              Map<String, dynamic>.from(data['entries'] as Map? ?? const {});
          _weeklyRefresh = Map<String, dynamic>.from(
              data['weeklyRefresh'] as Map? ?? const {});
        });
      }
    } catch (_) {
      // 首次进入或旧服务端尚无档案时仍允许开始任一测量。
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget page) async {
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => page));
    if (changed == true) await _loadArchive();
  }

  @override
  Widget build(BuildContext context) {
    final completed = ['questionnaire', 'tongue', 'pulse']
        .where((key) => _entries[key] != null)
        .length;
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6FBFC),
        elevation: 0,
        centerTitle: true,
        title: Text('体质档案', style: AppTextStyles.titleMedium),
      ),
      body: RefreshIndicator(
        onRefresh: _loadArchive,
        child: BottomFooterScrollView(
          footer: Text(
            '体质档案用于日常生活养护参考，不用于疾病筛查、诊断或治疗。出现持续或明显不适时，请及时到正规医疗机构就诊。',
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textHint, height: 1.55),
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFDBF7F4), Color(0xFFEDEBFF)]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('完成任意一项，即可建立档案',
                        style: AppTextStyles.titleSmall.copyWith(fontSize: 18)),
                    const SizedBox(height: 8),
                    Text('三项分别记录、清楚标明来源；完成越多，今日养生参考越完整。',
                        style: AppTextStyles.bodySmall.copyWith(height: 1.5)),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            minHeight: 7,
                            value: completed / 3,
                            backgroundColor: Colors.white.withValues(alpha: .7),
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$completed/3',
                          style: AppTextStyles.titleSmall
                              .copyWith(color: AppColors.primary)),
                    ]),
                  ]),
            ),
            const SizedBox(height: 22),
            if (_weeklyRefresh['due'] == true) ...[
              _weeklyRefreshCard(),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()))
            else ...[
              _archiveCard(
                keyName: 'questionnaire',
                icon: Icons.fact_check_outlined,
                title: '体质问卷',
                duration: '约 4 分钟',
                onTap: () => _open(const ConstitutionQuestionnairePage()),
              ),
              _archiveCard(
                keyName: 'tongue',
                icon: Icons.camera_alt_outlined,
                title: '舌象分析',
                duration: '约 1 分钟',
                onTap: () => _open(const TongueArchivePage()),
              ),
              _archiveCard(
                keyName: 'pulse',
                icon: Icons.monitor_heart_outlined,
                title: 'AI把脉',
                duration: '约 1 分钟',
                onTap: () => _open(const AiPulsePage()),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _archiveCard({
    required String keyName,
    required IconData icon,
    required String title,
    required String duration,
    required VoidCallback onTap,
  }) {
    final entry = _entries[keyName];
    final done = entry is Map;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: const Color(0xFFE9F8F7),
                    borderRadius: BorderRadius.circular(15)),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(title, style: AppTextStyles.titleSmall)),
              Text(done ? '已建档' : duration,
                  style: AppTextStyles.bodySmall.copyWith(
                      color: done ? AppColors.primary : AppColors.textHint)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textHint),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _weeklyRefreshCard() {
    final message = (_weeklyRefresh['message'] ?? '').toString().trim();
    return Material(
      color: const Color(0xFF172A2C),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(const WeeklyHealthCheckPage()),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.refresh_rounded, color: Color(0xFF7DE1D9)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本周状态待更新',
                        style: AppTextStyles.titleSmall
                            .copyWith(color: Colors.white)),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(message,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: Colors.white70, height: 1.4)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class ConstitutionQuestionnairePage extends StatefulWidget {
  const ConstitutionQuestionnairePage({super.key});

  @override
  State<ConstitutionQuestionnairePage> createState() =>
      _ConstitutionQuestionnairePageState();
}

class _ConstitutionQuestionnairePageState
    extends State<ConstitutionQuestionnairePage> {
  /// 0 性别 → 1 年龄 → 2 问卷
  int _step = 0;
  int _questionIndex = 0;
  int? _gender;
  int _age = 25;

  /// 键为题号 "1"…"21"；单选/开放题为 String；多选题为 List<String>。
  final Map<String, dynamic> _answers = {};
  final TextEditingController _complaintController = TextEditingController();
  final TextEditingController _otherCauseController = TextEditingController();

  String? _report;
  bool _loading = false;

  @override
  void dispose() {
    _complaintController.dispose();
    _otherCauseController.dispose();
    super.dispose();
  }

  List<ConstitutionQuestion> get _visibleQuestions {
    final out = <ConstitutionQuestion>[];
    for (final q in constitutionQuestions) {
      if (q.id == 3 && !showQuestion3(_answers['2'] as String?)) continue;
      if (q.id == 18 || q.id == 19) {
        if (_gender != 1) continue;
      }
      if (q.id == 20 && _gender != 0) continue;
      out.add(q);
    }
    return out;
  }

  ConstitutionQuestion? get _currentQuestion {
    final v = _visibleQuestions;
    if (_questionIndex < 0 || _questionIndex >= v.length) return null;
    return v[_questionIndex];
  }

  void _clampQuestionIndex() {
    final n = _visibleQuestions.length;
    if (n == 0) return;
    if (_questionIndex >= n) _questionIndex = n - 1;
    if (_questionIndex < 0) _questionIndex = 0;
  }

  void _syncFieldControllersForQuestion() {
    final q = _currentQuestion;
    if (q?.id == 1) {
      _complaintController.text = (_answers['1'] as String?) ?? '';
    }
    if (q?.id == 21) {
      _otherCauseController.text = (_answers['21_other'] as String?) ?? '';
    }
  }

  void _onQ2Changed(String key) {
    setState(() {
      _answers['2'] = key;
      if (!showQuestion3(key)) _answers.remove('3');
      _clampQuestionIndex();
    });
  }

  Map<String, dynamic> _mergedAnswersForSubmit() {
    final merged = Map<String, dynamic>.from(_answers);
    if (merged['8'] == 'B' && merged['8h'] != null) {
      merged['8'] = 'B${merged['8h']}';
    }
    merged.remove('8h');
    return merged;
  }

  String _labelForOption(List<ConstitutionOption> options, String key) {
    for (final o in options) {
      if (o.key == key) return o.label;
    }
    return '';
  }

  String _formatAnswerLine(ConstitutionQuestion q, dynamic raw) {
    switch (q.type) {
      case ConstitutionQuestionType.text:
        return '答：${raw ?? ''}';
      case ConstitutionQuestionType.single:
        final s = raw as String? ?? '';
        if (q.id == 8 && s.startsWith('B') && s.length >= 2 && s != 'B') {
          final subKey = s.substring(1);
          final mainLabel = _labelForOption(q.options, 'B');
          final subLabel = _labelForOption(headacheSubOptions, subKey);
          final subPart = subLabel.isNotEmpty ? subLabel : subKey;
          return '答：B $mainLabel（头痛类型：$subPart）';
        }
        final lb = _labelForOption(q.options, s);
        return lb.isNotEmpty ? '答：$s $lb' : '答：$s';
      case ConstitutionQuestionType.multi:
        final keys = (raw is List) ? raw.cast<String>() : <String>[];
        if (keys.isEmpty) return '答：（未选）';
        final parts = <String>[];
        for (final key in keys) {
          final lb = _labelForOption(q.options, key);
          parts.add(lb.isNotEmpty ? '$key $lb' : key);
        }
        return '答：${parts.join('；')}';
    }
  }

  /// 供大模型阅读的问卷全文（与 v2 responses 一致，由客户端生成避免服务端重复维护题面）。
  String _buildClientQaText() {
    final merged = _mergedAnswersForSubmit();
    final buf = StringBuffer();
    String? lastSection;
    for (final q in _visibleQuestions) {
      final k = '${q.id}';
      if (!merged.containsKey(k)) continue;
      if (q.section != null && q.section != lastSection) {
        buf.writeln();
        buf.writeln(q.section);
        lastSection = q.section;
      }
      buf.writeln('【$k】${q.title}');
      buf.writeln('  ${_formatAnswerLine(q, merged[k])}');
    }
    final other = (merged['21_other'] as String?)?.trim();
    if (other != null && other.isNotEmpty) {
      buf.writeln();
      buf.writeln('【诱因·其他补充】');
      buf.writeln('  $other');
    }
    return buf.toString().trim();
  }

  Map<String, dynamic> _buildAnswersPayload() {
    final merged = _mergedAnswersForSubmit();
    final responses = <String, dynamic>{};
    for (final q in _visibleQuestions) {
      final k = '${q.id}';
      if (merged.containsKey(k)) responses[k] = merged[k];
    }
    return {
      'schemaVersion': 2,
      'responses': responses,
      'clientQaText': _buildClientQaText(),
      if ((merged['21_other'] as String?)?.trim().isNotEmpty ?? false)
        'causeOtherNote': (merged['21_other'] as String).trim(),
    };
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final formData = FormData.fromMap({
        'gender': _gender == 0 ? '男' : '女',
        'age': _age.toString(),
        'questionnaireVersion': '2',
        'healthConsentVersion': '2026-08-27-v1',
        'answers': jsonEncode(_buildAnswersPayload()),
      });
      final res = await apiClient.post('/api/fortune/constitution-test',
          data: formData);
      if (res.data != null && mounted) {
        setState(() => _report = res.data['data']['content']);
      }
    } on DioException catch (e) {
      var msg = '提交失败，请检查网络后重试';
      final body = e.response?.data;
      if (body is Map && body['message'] != null) {
        final m = body['message'].toString().trim();
        if (m.isNotEmpty) msg = m;
      }
      if (mounted) showAppToast(context, msg);
    } catch (_) {
      if (mounted) showAppToast(context, '提交失败，请检查网络后重试');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_report != null) return _buildReportView();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Text(_stepTitle, style: AppTextStyles.titleMedium),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_step == 2) _buildProgressBar(),
                Expanded(child: _buildStepBody()),
              ],
            ),
    );
  }

  String get _stepTitle {
    if (_step == 0) return '第一步：选择性别';
    if (_step == 1) return '第二步：选择年龄';
    if (_step == 2) return '第三步：问卷调研';
    return '体质问卷';
  }

  Widget _buildProgressBar() {
    final total = _visibleQuestions.length;
    if (total == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          value: (_questionIndex + 1) / total,
          minHeight: 6,
          backgroundColor: AppColors.divider,
          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return _buildGenderStep();
      case 1:
        return _buildAgeStep();
      case 2:
        return _buildQuestionStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildGenderStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('您的性别是？',
              style: AppTextStyles.displayLarge.copyWith(fontSize: 24)),
          const SizedBox(height: 8),
          Text('将用于显示与性别相关的题目',
              style:
                  AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
          const SizedBox(height: 40),
          Row(
            children: [
              _genderCard(0, Icons.male_rounded, '男士', const Color(0xFFEFF6FF),
                  const Color(0xFF2563EB)),
              const SizedBox(width: 24),
              _genderCard(1, Icons.female_rounded, '女士',
                  const Color(0xFFFFF1F2), const Color(0xFFE11D48)),
            ],
          ),
          const SizedBox(height: 64),
          AppButton(
            label: '确定',
            onPressed: _gender == null
                ? null
                : () => setState(() {
                      _step = 1;
                    }),
          ),
        ],
      ),
    );
  }

  Widget _genderCard(
      int val, IconData icon, String label, Color bg, Color active) {
    final isSelected = _gender == val;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            color: isSelected ? active : bg,
            borderRadius: BorderRadius.circular(24),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: active.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8))
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 48, color: isSelected ? Colors.white : active),
              const SizedBox(height: 12),
              Text(label,
                  style: AppTextStyles.titleSmall
                      .copyWith(color: isSelected ? Colors.white : active)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgeStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('您的真实年龄？',
              style: AppTextStyles.displayLarge.copyWith(fontSize: 24)),
          const SizedBox(height: 20),
          Text('$_age 岁',
              style: AppTextStyles.displayLarge
                  .copyWith(fontSize: 48, color: AppColors.primary)),
          const SizedBox(height: 40),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
              valueIndicatorTextStyle: const TextStyle(color: Colors.white),
            ),
            child: Slider(
              value: _age.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              label: '$_age',
              onChanged: (v) => setState(() => _age = v.round()),
            ),
          ),
          const SizedBox(height: 64),
          AppButton(
            label: '下一步',
            onPressed: () => setState(() {
              _questionIndex = 0;
              _step = 2;
              _complaintController.text = (_answers['1'] as String?) ?? '';
            }),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(() => _step = 0),
            child: const Text('返回上一步',
                style: TextStyle(color: AppColors.textHint)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionStep() {
    _clampQuestionIndex();
    final q = _currentQuestion;
    if (q == null) {
      return const Center(child: Text('暂无题目'));
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (q.section != null) ...[
                  Text(q.section!,
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
                Text(
                  '第 ${_questionIndex + 1} / ${_visibleQuestions.length} 题',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textHint),
                ),
                const SizedBox(height: 12),
                Text(q.title,
                    style: AppTextStyles.titleMedium
                        .copyWith(fontSize: 18, height: 1.45)),
                const SizedBox(height: 24),
                _buildQuestionContent(q),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Row(
            children: [
              if (_questionIndex > 0)
                Expanded(
                  child: AppButton(
                    label: '上一题',
                    outline: true,
                    onPressed: () => setState(() {
                      _questionIndex--;
                      _syncFieldControllersForQuestion();
                    }),
                  ),
                ),
              if (_questionIndex > 0) const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: _questionIndex >= _visibleQuestions.length - 1
                      ? '生成问卷报告'
                      : '下一题',
                  onPressed: _canProceed(q) ? _goNext : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _canProceed(ConstitutionQuestion q) {
    switch (q.type) {
      case ConstitutionQuestionType.text:
        return _complaintController.text.trim().isNotEmpty;
      case ConstitutionQuestionType.single:
        final v = _answers['${q.id}'] as String?;
        if (v == null) return false;
        if (q.id == 8 && v == 'B') {
          final sub = _answers['8h'] as String?;
          return sub != null && sub.isNotEmpty;
        }
        return true;
      case ConstitutionQuestionType.multi:
        final list = (_answers['${q.id}'] as List?)?.cast<String>() ?? [];
        if (q.id == 17 || q.id == 20) return true;
        if (list.isEmpty) return false;
        if (q.id == 21 && list.contains('F')) {
          return _otherCauseController.text.trim().isNotEmpty;
        }
        return true;
    }
  }

  void _goNext() {
    final q = _currentQuestion;
    if (q == null || !_canProceed(q)) return;

    if (q.type == ConstitutionQuestionType.text) {
      _answers['${q.id}'] = _complaintController.text.trim();
    }
    if (q.type == ConstitutionQuestionType.multi) {
      _answers['${q.id}'] = List<String>.from(
        (_answers['${q.id}'] as List?)?.cast<String>() ?? const [],
      );
    }
    if (q.id == 21) {
      final list = (_answers['21'] as List?)?.cast<String>() ?? [];
      if (list.contains('F')) {
        _answers['21_other'] = _otherCauseController.text.trim();
      } else {
        _answers.remove('21_other');
      }
    }

    if (_questionIndex >= _visibleQuestions.length - 1) {
      _submit();
    } else {
      setState(() => _questionIndex++);
    }
  }

  Widget _buildQuestionContent(ConstitutionQuestion q) {
    switch (q.type) {
      case ConstitutionQuestionType.text:
        return TextField(
          controller: _complaintController,
          maxLines: 5,
          minLines: 3,
          decoration: InputDecoration(
            hintText: '请简要描述您最希望改善的不适…',
            hintStyle: AppTextStyles.hint,
            filled: true,
            fillColor: AppColors.cardBackground,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(16),
          ),
          onChanged: (_) => setState(() {}),
        );
      case ConstitutionQuestionType.single:
        return _buildSingleQuestion(q);
      case ConstitutionQuestionType.multi:
        return _buildMultiQuestion(q);
    }
  }

  Widget _buildSingleQuestion(ConstitutionQuestion q) {
    final selected = _answers['${q.id}'] as String?;
    final showHeadache = q.id == 8 && selected == 'B';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...q.options.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _choiceTile(
                label: '${o.key}. ${o.label}',
                selected: selected == o.key,
                onTap: () {
                  setState(() {
                    if (q.id == 2) {
                      _onQ2Changed(o.key);
                    } else {
                      _answers['${q.id}'] = o.key;
                    }
                    if (q.id == 8 && o.key != 'B') _answers.remove('8h');
                  });
                },
              ),
            )),
        if (showHeadache) ...[
          const SizedBox(height: 8),
          Text('请选择头痛类型：',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ...headacheSubOptions.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _choiceTile(
                  label: '${o.key}. ${o.label}',
                  selected: _answers['8h'] == o.key,
                  onTap: () => setState(() => _answers['8h'] = o.key),
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildMultiQuestion(ConstitutionQuestion q) {
    final list =
        Set<String>.from((_answers['${q.id}'] as List?)?.cast<String>() ?? []);
    final showOther = q.id == 21 && list.contains('F');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...q.options.map((o) {
          final on = list.contains(o.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _choiceTile(
              label: '${o.key}. ${o.label}',
              selected: on,
              onTap: () => setState(() {
                if (on) {
                  list.remove(o.key);
                } else {
                  list.add(o.key);
                }
                _answers['${q.id}'] = list.toList()..sort();
                if (q.id == 21 && !list.contains('F')) {
                  _otherCauseController.clear();
                }
              }),
            ),
          );
        }),
        if (showOther) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _otherCauseController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: '请补充说明「其他」原因',
              hintStyle: AppTextStyles.hint,
              filled: true,
              fillColor: AppColors.cardBackground,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(14),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
    );
  }

  Widget _choiceTile(
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTextStyles.bodyLarge.copyWith(
            color: selected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  /// 去掉模型可能包在外层的 ```markdown / ``` 代码块，便于 Markdown 解析标题、列表等
  String _stripReportMarkdownFence(String raw) {
    if (raw.isEmpty) return raw;
    String s = raw.trim();
    if (s.startsWith('```')) {
      final firstLineEnd = s.indexOf('\n');
      if (firstLineEnd != -1) {
        s = s.substring(firstLineEnd + 1);
      } else {
        s = s.replaceFirst(RegExp(r'^```\w*\s*'), '');
      }
    }
    if (s.trimRight().endsWith('```')) {
      s = s.trimRight();
      final lastFence = s.lastIndexOf('```');
      if (lastFence != -1) s = s.substring(0, lastFence).trimRight();
    }
    return s.trim();
  }

  Widget _buildReportView() {
    final md = _stripReportMarkdownFence(_report!)
        .replaceFirst(RegExp(r'^#\s*体质状态画像\s*'), '')
        .trim();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('体质分析报告'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完成'))
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF172A2C),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CONSTITUTION PROFILE',
                      style: TextStyle(
                          color: Color(0xFF67DCD4),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5)),
                  SizedBox(height: 13),
                  Text('体质状态画像',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text('体质底色 · 本次信号 · 7 日行动',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13, height: 1.45)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: AiGeneratedBadge(compact: true),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20)
                ],
              ),
              child: AppGptMarkdown(
                selectionArea: true,
                data: md,
                bodyStyle: AppTextStyles.bodyMedium.copyWith(
                    height: 1.65, fontSize: 15, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F8F6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日养生已同步', style: AppTextStyles.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    '体质结果已保存，可在今日养生查看饮食、茶饮与作息建议。',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Get.toNamed(RouteNames.homeTodayHealth),
                      child: const Text('查看今日养生'),
                    ),
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

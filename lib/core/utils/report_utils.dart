import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'app_toast.dart';

const int minimumReportReasonCharacters = 10;

int reportReasonCharacterCount(String value) =>
    value.replaceAll(RegExp(r'\s'), '').runes.length;

bool isValidReportReason(String value) =>
    reportReasonCharacterCount(value) >= minimumReportReasonCharacters;

class ReportCategory {
  const ReportCategory({
    required this.code,
    required this.label,
    required this.reasons,
    this.summary = '请选择最符合的具体原因',
  });

  final String code;
  final String label;
  final List<ReportSubReason> reasons;
  final String summary;
}

class ReportSubReason {
  const ReportSubReason(this.code, this.label);

  final String code;
  final String label;
}

const reportCategories = <ReportCategory>[
  ReportCategory(
    code: 'dislike',
    label: '我不喜欢',
    summary: '不喜欢该内容、该作者或其他不喜欢原因',
    reasons: [
      ReportSubReason('dislike_author', '不喜欢该作者'),
      ReportSubReason('dislike_content', '不喜欢该内容'),
      ReportSubReason('too_similar_content', '相似内容过多'),
      ReportSubReason('other_dislike', '其他原因'),
    ],
  ),
  ReportCategory(
    code: 'fraud',
    label: '涉嫌欺诈',
    reasons: [
      ReportSubReason('payment', '诱导转账'),
      ReportSubReason('impersonation', '冒充他人'),
      ReportSubReason('fortune_scam', '付费算命骗局'),
      ReportSubReason('other_fraud', '其他欺诈'),
    ],
  ),
  ReportCategory(
    code: 'politics',
    label: '涉政不当言论',
    reasons: [
      ReportSubReason('political_rumor', '涉政谣言'),
      ReportSubReason('political_attack', '不当政治攻击'),
      ReportSubReason('historical_distortion', '歪曲历史'),
      ReportSubReason('other_politics', '其他涉政问题'),
    ],
  ),
  ReportCategory(
    code: 'illegal_info',
    label: '违法信息',
    reasons: [
      ReportSubReason('illegal_trade', '违法交易'),
      ReportSubReason('gambling_drugs', '赌博或违禁品'),
      ReportSubReason('criminal_guidance', '违法犯罪引导'),
      ReportSubReason('other_illegal_info', '其他违法信息'),
    ],
  ),
  ReportCategory(
    code: 'sexual',
    label: '低俗色情',
    reasons: [
      ReportSubReason('explicit', '色情露骨'),
      ReportSubReason('suggestive', '低俗暗示'),
      ReportSubReason('solicitation', '色情招嫖'),
      ReportSubReason('other_sexual', '其他低俗内容'),
    ],
  ),
  ReportCategory(
    code: 'advertising',
    label: '违规广告',
    reasons: [
      ReportSubReason('external_contact', '站外引流'),
      ReportSubReason('private_trade', '私下交易'),
      ReportSubReason('spam', '重复营销'),
      ReportSubReason('other_ad', '其他广告'),
    ],
  ),
  ReportCategory(
    code: 'safety',
    label: '危害人身安全',
    reasons: [
      ReportSubReason('self_harm', '疑似自伤风险'),
      ReportSubReason('violence', '暴力伤害威胁'),
      ReportSubReason('dangerous_act', '危险行为'),
      ReportSubReason('urgent_other', '其他紧急风险'),
    ],
  ),
  ReportCategory(
    code: 'misinformation',
    label: '谣言不实',
    reasons: [
      ReportSubReason('fabricated', '虚构事实'),
      ReportSubReason('medical', '健康医疗谣言'),
      ReportSubReason('panic', '制造恐慌'),
      ReportSubReason('other_false', '其他不实信息'),
    ],
  ),
  ReportCategory(
    code: 'minor',
    label: '涉未成年人',
    reasons: [
      ReportSubReason('minor_sexual', '涉未成年人色情'),
      ReportSubReason('minor_bullying', '诱导或欺凌未成年人'),
      ReportSubReason('minor_privacy', '泄露未成年人隐私'),
      ReportSubReason('other_minor', '其他未成年人问题'),
    ],
  ),
  ReportCategory(
    code: 'harassment',
    label: '攻击辱骂',
    reasons: [
      ReportSubReason('insult', '侮辱谩骂'),
      ReportSubReason('hate', '歧视仇恨'),
      ReportSubReason('incitement', '煽动围攻'),
      ReportSubReason('threat', '威胁恐吓'),
    ],
  ),
  ReportCategory(
    code: 'public_morality',
    label: '违反公共道德',
    reasons: [
      ReportSubReason('vulgar_behavior', '低俗不雅行为'),
      ReportSubReason('bad_example', '不良价值导向'),
      ReportSubReason('disturbing_order', '扰乱公共秩序'),
      ReportSubReason('other_morality', '其他道德问题'),
    ],
  ),
  ReportCategory(
    code: 'stolen_content',
    label: '搬运盗图',
    reasons: [
      ReportSubReason('repost', '未经授权搬运'),
      ReportSubReason('stolen_image', '盗用图片'),
      ReportSubReason('plagiarism', '抄袭内容'),
      ReportSubReason('other_stolen', '其他搬运行为'),
    ],
  ),
  ReportCategory(
    code: 'infringement',
    label: '侵权行为',
    reasons: [
      ReportSubReason('personal_data', '泄露个人信息'),
      ReportSubReason('portrait', '侵犯肖像权'),
      ReportSubReason('trademark', '侵犯商标专利'),
      ReportSubReason('other_infringement', '其他侵权'),
    ],
  ),
  ReportCategory(
    code: 'other_violation',
    label: '其他违规',
    reasons: [
      ReportSubReason('fake_account', '虚假账号'),
      ReportSubReason('malicious_behavior', '恶意行为'),
      ReportSubReason('platform_abuse', '滥用平台功能'),
      ReportSubReason('other_violation_reason', '其他违规'),
    ],
  ),
];

class _ReportResult {
  const _ReportResult(this.reportId);

  final int? reportId;
}

/// 两步举报：先选违规类型，再补充具体原因、描述与图片证据。
Future<void> showReportSheet(
  BuildContext context, {
  required String targetType,
  required int targetId,
  String title = '举报',
}) async {
  final result = await Navigator.of(context).push<_ReportResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ReportFlowPage(
        targetType: targetType,
        targetId: targetId,
        title: title,
      ),
    ),
  );
  if (result != null && context.mounted) {
    showAppToast(context, '举报已提交，我们将在24小时内审核并采取处理行动');
  }
}

class _ReportFlowPage extends StatefulWidget {
  const _ReportFlowPage({
    required this.targetType,
    required this.targetId,
    required this.title,
  });

  final String targetType;
  final int targetId;
  final String title;

  @override
  State<_ReportFlowPage> createState() => _ReportFlowPageState();
}

class _ReportFlowPageState extends State<_ReportFlowPage> {
  final _reasonDetailController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  ReportCategory? _category;
  ReportSubReason? _subReason;
  final List<XFile> _evidence = [];
  bool _detailsStep = false;
  bool _submitting = false;

  @override
  void dispose() {
    _reasonDetailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    if (_evidence.length >= 4) return;
    try {
      final selected = await _picker.pickMultiImage(
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (!mounted || selected.isEmpty) return;
      setState(() {
        for (final file in selected) {
          if (_evidence.length >= 4) break;
          if (!_evidence.any((item) => item.path == file.path)) {
            _evidence.add(file);
          }
        }
      });
    } catch (_) {
      if (mounted) showAppToast(context, '暂时无法读取图片');
    }
  }

  Future<String> _uploadEvidence(XFile file) async {
    final response = await apiClient.post(
      '/api/config/upload',
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: file.name),
      }),
    );
    final data = (response.data as Map?)?['data'] as Map?;
    final url = data?['url']?.toString().trim() ?? '';
    if (url.isEmpty) throw StateError('图片上传失败');
    return url;
  }

  Future<void> _submit() async {
    final category = _category;
    final subReason = _subReason;
    if (category == null || subReason == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final evidenceUrls = <String>[];
      for (final file in _evidence) {
        evidenceUrls.add(await _uploadEvidence(file));
      }
      final reasonDetail = _reasonDetailController.text.trim();
      final description = _descriptionController.text.trim();
      final combinedDescription = [
        if (reasonDetail.isNotEmpty) '具体原因：$reasonDetail',
        if (description.isNotEmpty) description,
      ].join('\n');
      final legacyReason = [
        category.label,
        subReason.label,
        if (reasonDetail.isNotEmpty) reasonDetail,
        if (description.isNotEmpty) description,
      ].join(' · ');
      final response = await apiClient.post(
        '/api/community/report',
        data: {
          'targetType': widget.targetType,
          'targetId': widget.targetId,
          'categoryCode': category.code,
          'subReasonCode': subReason.code,
          'description': combinedDescription.length > 200
              ? combinedDescription.substring(0, 200)
              : combinedDescription,
          'evidenceUrls': evidenceUrls,
          'reason': legacyReason,
        },
      );
      final data = (response.data as Map?)?['data'] as Map?;
      final reportId = (data?['reportId'] as num?)?.toInt();
      if (!mounted) return;
      Navigator.of(context).pop(_ReportResult(reportId));
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? (error.response!.data as Map)['message']?.toString()
          : null;
      if (mounted) showAppToast(context, message ?? '提交失败，请稍后重试');
    } catch (_) {
      if (mounted) showAppToast(context, '图片上传失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showNotice() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('举报须知'),
        content: const Text(
          '请如实选择问题并提供必要证据。平台会保护举报人信息；恶意或重复举报不会加快处理。遇到正在发生的人身危险，请同时联系当地紧急救助机构。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_detailsStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _detailsStep) setState(() => _detailsStep = false);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 72,
          leading: IconButton(
            onPressed: () {
              if (_detailsStep) {
                setState(() => _detailsStep = false);
              } else {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          centerTitle: true,
          title: Text(
            widget.title == '举报' && widget.targetType == 'post'
                ? '举报帖子'
                : widget.title,
            style: AppTextStyles.titleMedium.copyWith(
              color: const Color(0xFF242529),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(onPressed: _showNotice, child: const Text('举报须知')),
            const SizedBox(width: 4),
          ],
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _detailsStep ? _buildDetails() : _buildCategories(),
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return Column(
      key: const ValueKey('report-categories'),
      children: [
        Expanded(
          child: RadioGroup<String>(
            groupValue: _category?.code,
            onChanged: (code) {
              final item = reportCategories
                  .where((candidate) => candidate.code == code)
                  .firstOrNull;
              if (item == null) return;
              setState(() {
                _category = item;
                _subReason = null;
              });
            },
            child: ListView.separated(
              itemCount: reportCategories.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: AppColors.communityDivider,
              ),
              itemBuilder: (context, index) {
                final item = reportCategories[index];
                return InkWell(
                  onTap: () => setState(() {
                    _category = item;
                    _subReason = null;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontSize: 16,
                              color: AppColors.communityText,
                            ),
                          ),
                        ),
                        Radio<String>(
                          value: item.code,
                          activeColor: AppColors.communityAccent,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _category == null
                    ? null
                    : () => setState(() => _detailsStep = true),
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  backgroundColor: AppColors.communityAccent,
                ),
                child: const Text('下一步'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    final category = _category!;
    return Column(
      key: const ValueKey('report-details'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '举报理由: ${category.label}',
                  style: AppTextStyles.titleSmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonDetailController,
                  maxLength: 80,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: category.summary,
                    hintStyle: const TextStyle(color: AppColors.communityMeta),
                    filled: true,
                    fillColor: AppColors.communityInsetSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('选择具体原因', style: AppTextStyles.titleSmall),
                    const Text(' *', style: TextStyle(color: Colors.red)),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: category.reasons.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 3.25,
                  ),
                  itemBuilder: (context, index) {
                    final item = category.reasons[index];
                    final selected = _subReason?.code == item.code;
                    return InkWell(
                      onTap: () => setState(() => _subReason = item),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primaryLight
                              : AppColors.communityInsetSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? AppColors.communityAccent
                                : AppColors.communityDivider,
                          ),
                        ),
                        child: Text(
                          item.label,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 14,
                            color: selected
                                ? AppColors.primaryDark
                                : AppColors.communityText,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text('举报描述', style: AppTextStyles.titleSmall),
                const SizedBox(height: 10),
                TextField(
                  controller: _descriptionController,
                  maxLength: 200,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: '请您描述作品中存在的问题',
                    hintStyle: const TextStyle(color: AppColors.communityMeta),
                    filled: true,
                    fillColor: AppColors.communityInsetSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('图片证据', style: AppTextStyles.titleSmall),
                const SizedBox(height: 3),
                Text(
                  '请上传相关图片（最多4张）',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.communityMeta,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var index = 0; index < _evidence.length; index++)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_evidence[index].path),
                              width: 78,
                              height: 78,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: -7,
                            right: -7,
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _evidence.removeAt(index)),
                              child: const CircleAvatar(
                                radius: 10,
                                backgroundColor: Color(0xFF303236),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_evidence.length < 4)
                      InkWell(
                        onTap: _pickEvidence,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            color: AppColors.communityInsetSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.communityDivider,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.add_rounded,
                                size: 28,
                                color: AppColors.textHint,
                              ),
                              Text(
                                '${_evidence.length}/4',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.communityMeta,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _subReason == null || _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  backgroundColor: AppColors.communityAccent,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('提交'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

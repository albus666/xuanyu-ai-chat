import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../consultation/teacher_workbench_page.dart';
import 'legal_document_page.dart';
import 'identity_verification_page.dart';

class TeacherApplyPage extends StatefulWidget {
  const TeacherApplyPage({super.key, this.onSuccess});
  final VoidCallback? onSuccess;

  @override
  State<TeacherApplyPage> createState() => _TeacherApplyPageState();
}

class _TeacherApplyPageState extends State<TeacherApplyPage> {
  final _name = TextEditingController();
  final _idCard = TextEditingController();
  final _education = TextEditingController();
  final _experienceYears = TextEditingController();
  final _credentialName = TextEditingController();
  final _credentialNo = TextEditingController();
  final _credentialIssuer = TextEditingController();
  final _credentialExpireDate = TextEditingController();
  final _serviceIntro = TextEditingController();
  final _customCategory = TextEditingController();
  String _serviceType = 'traditional';
  final Set<String> _specialties = {};
  String? _credentialImageUrl;
  Map<String, dynamic> _identity = {};
  String? _status;
  String _remark = '';
  bool _loading = true;
  bool _submitting = false;
  bool _uploading = false;
  bool _agreed = false;
  String? _loadError;

  static const _specialtyOptions = [
    '八字命盘',
    '流年运势',
    '感情关系',
    '事业发展',
    '家庭关系',
    '情绪倾听',
    '压力疏导',
    '个人成长',
    '寻宠经验',
    '线索梳理',
    '行动建议'
  ];

  final _scope = ApiSessionScope();

  void _accountChanged() {
    if (mounted && !_scope.current) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _loadStatus();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    for (final c in [
      _name,
      _idCard,
      _education,
      _experienceYears,
      _credentialName,
      _credentialNo,
      _credentialIssuer,
      _credentialExpireDate,
      _serviceIntro,
      _customCategory
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStatus() async {
    if (!mounted || !_scope.current) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await _scope.get('/api/auth/teacher/status');
      final data = (response.data as Map?)?['data'];
      if (data is! Map) throw const FormatException('入驻状态返回异常');
      final identity =
          identityResponseData((await _scope.get('/api/auth/identity')).data);
      if (!mounted || !_scope.current) return;
      if (mounted && _scope.current) {
        setState(() {
          _identity = identity;
          _status = data['status']?.toString();
          _remark = data['remark']?.toString() ?? '';
        });
      }
    } catch (error) {
      if (mounted && _scope.current) {
        setState(
            () => _loadError = apiSessionFailureMessage(error, '入驻状态加载失败，请重试'));
      }
    }
    if (mounted && _scope.current) setState(() => _loading = false);
  }

  Future<void> _pickCredential() async {
    if (!mounted || !_scope.current || _uploading || _submitting) return;
    setState(() => _uploading = true);
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 2000, imageQuality: 88);
      if (picked == null || !mounted || !_scope.current) return;
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(picked.path, filename: picked.name)
      });
      if (!mounted || !_scope.current) return;
      final response = await _scope.post('/api/config/upload', data: form);
      final url =
          ((response.data as Map?)?['data'] as Map?)?['url']?.toString();
      if (url == null || url.isEmpty) throw const FormatException();
      if (mounted && _scope.current) setState(() => _credentialImageUrl = url);
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '证书上传失败，请重试'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (!mounted ||
        !_scope.current ||
        _submitting ||
        _uploading ||
        _loading ||
        _loadError != null) {
      return;
    }
    if (!['pending', 'approved'].contains(_identity['status'])) {
      showAppToast(context, '请先提交实名认证和身份证正反面');
      return;
    }
    if (_serviceType == 'other' && _customCategory.text.trim().isEmpty) {
      showAppToast(context, '请填写服务类别');
      return;
    }
    if (_serviceIntro.text.trim().length < 20) {
      showAppToast(context, '服务介绍至少填写20个字');
      return;
    }
    if (_specialties.isEmpty) {
      showAppToast(context, '请至少选择一个擅长领域');
      return;
    }
    if (!_agreed) {
      showAppToast(context, '请先阅读并同意入驻承诺');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _scope.post('/api/auth/teacher/apply', data: {
        'serviceType': _serviceType,
        if (_serviceType == 'other')
          'serviceCategoryName': _customCategory.text.trim(),
        'education': _education.text.trim(),
        'experienceYears': int.tryParse(_experienceYears.text) ?? 0,
        'credentialName': _credentialName.text.trim(),
        'credentialNo': _credentialNo.text.trim(),
        'credentialIssuer': _credentialIssuer.text.trim(),
        'credentialExpireDate': _credentialExpireDate.text.trim(),
        'credentialImageUrl': _credentialImageUrl ?? '',
        'specialties': _specialties.toList(),
        'serviceIntro': _serviceIntro.text.trim(),
        'agreementAccepted': true,
      });
      if (!mounted || !_scope.current) return;
      showAppToast(context, '申请已提交，平台将核验身份与资质');
      widget.onSuccess?.call();
      await _loadStatus();
    } catch (e) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(e, '提交失败'));
      }
    }
    if (mounted && _scope.current) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_scope.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('账号已切换')),
        body: const Center(child: Text(apiSessionChangedMessage)),
      );
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('老师入驻')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!),
              TextButton(onPressed: _loadStatus, child: const Text('重新加载')),
            ],
          ),
        ),
      );
    }
    if (_status == 'approved') {
      return Scaffold(
        appBar: AppBar(title: const Text('名师入驻')),
        body: Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_rounded,
                      size: 68, color: Color(0xFF2C7566)),
                  const SizedBox(height: 16),
                  Text('您已通过老师认证', style: AppTextStyles.titleMedium),
                  const SizedBox(height: 8),
                  Text('可以设置服务价格、接听私人专线或创建名师直播。',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textHint)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const TeacherWorkbenchPage())),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF173F3B)),
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const Text('进入老师工作台')),
                ]))),
      );
    }
    if (_status == 'pending') {
      return const _StatusPage(
          icon: Icons.hourglass_top_rounded,
          title: '申请正在审核',
          subtitle: '平台正在核验身份、证书和服务范围，请耐心等待。');
    }
    if (_status == 'rejected') {
      return Scaffold(
          appBar: AppBar(title: const Text('名师入驻')),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.assignment_late_outlined,
                        size: 64, color: AppColors.warning),
                    const SizedBox(height: 15),
                    Text('申请需要补充材料', style: AppTextStyles.titleMedium),
                    const SizedBox(height: 8),
                    Text(_remark.isEmpty ? '请检查填写内容和证书原件后重新提交。' : _remark,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textHint)),
                    const SizedBox(height: 22),
                    OutlinedButton(
                        onPressed: () => setState(() => _status = 'none'),
                        child: const Text('重新申请')),
                  ]))));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('老师入驻')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('实名认证与身份证正反面'),
              subtitle: Text(_identity['status'] == 'approved'
                  ? '实名认证已通过'
                  : _identity['status'] == 'pending'
                      ? '身份材料审核中'
                      : '请先上传身份证正反面并提交实名认证'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const IdentityVerificationPage()));
                if (mounted && _scope.current) _loadStatus();
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
                initialValue: _serviceType,
                decoration: const InputDecoration(
                    labelText: '申请服务类别', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: 'traditional', child: Text('传统文化/八字解读')),
                  DropdownMenuItem(value: 'listening', child: Text('情感倾听与陪伴')),
                  DropdownMenuItem(value: 'psychology', child: Text('专业心理咨询')),
                  DropdownMenuItem(
                      value: 'pet_search', child: Text('寻宠经验与线索梳理')),
                  DropdownMenuItem(value: 'other', child: Text('其它'))
                ],
                onChanged: (v) =>
                    setState(() => _serviceType = v ?? 'traditional')),
            const SizedBox(height: 16),
            if (_serviceType == 'other')
              _field(_customCategory, '服务类别', '请输入服务类别', maxLength: 64),
            _field(_education, '学历及专业', '例如：本科 · 应用心理学', maxLength: 100),
            _field(_experienceYears, '相关服务年限', '填写数字',
                maxLength: 2, keyboard: TextInputType.number),
            Text('擅长领域', style: AppTextStyles.titleSmall),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 7,
                children: _specialtyOptions
                    .map((e) => FilterChip(
                        label: Text(e),
                        selected: _specialties.contains(e),
                        showCheckmark: false,
                        selectedColor: const Color(0xFFE1EEE8),
                        onSelected: (v) => setState(() {
                              if (v) {
                                _specialties.add(e);
                              } else {
                                _specialties.remove(e);
                              }
                            })))
                    .toList()),
            const SizedBox(height: 20),
            Text('资质材料', style: AppTextStyles.titleSmall),
            const SizedBox(height: 5),
            Text(
                _serviceType == 'psychology'
                    ? '证书为选填；提交后可供平台核验相关资质。'
                    : '如有相关证书，提交后会展示对应的已核验标签。',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint)),
            const SizedBox(height: 12),
            _field(_credentialName, '证书名称', '例如：心理咨询相关专业证书', maxLength: 100),
            _field(_credentialNo, '证书编号', '仅用于资质审核，对外脱敏展示', maxLength: 100),
            _field(_credentialIssuer, '发证机构', '请输入发证机构全称', maxLength: 100),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: _credentialExpireDate,
                readOnly: true,
                onTap: _pickCredentialExpireDate,
                decoration: const InputDecoration(
                  labelText: '证书有效期',
                  hintText: '长期有效可不填',
                  suffixIcon: Icon(Icons.calendar_month_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            InkWell(
                onTap: _uploading ? null : _pickCredential,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                    height: 132,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _credentialImageUrl == null
                                ? AppColors.divider
                                : const Color(0xFF2C7566))),
                    child: _uploading
                        ? const Center(child: CircularProgressIndicator())
                        : _credentialImageUrl == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    const Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: AppColors.textHint,
                                        size: 34),
                                    const SizedBox(height: 7),
                                    Text('上传证书原件',
                                        style: AppTextStyles.bodyMedium
                                            .copyWith(
                                                color: AppColors.textHint))
                                  ])
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: Image.network(_credentialImageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.check_circle,
                                            color: Color(0xFF2C7566))))))),
            const SizedBox(height: 18),
            TextField(
                controller: _serviceIntro,
                maxLength: 1000,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(
                    labelText: '个人与服务介绍',
                    hintText: '介绍经历、擅长方向、服务方式和边界，至少20个字',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder())),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(
                value: _agreed,
                onChanged: (value) => setState(() => _agreed = value == true),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(children: [
                    Text('我已阅读并同意', style: AppTextStyles.bodySmall),
                    InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LegalDocumentPage(
                          type: LegalDocumentType.teacherServiceRules,
                        ),
                      )),
                      child: Text('《老师入驻、服务与结算规则》',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: AppColors.primaryDark)),
                    ),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
                onPressed:
                    _submitting || _uploading || !_agreed ? null : _submit,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF173F3B),
                    minimumSize: const Size.fromHeight(50)),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('提交审核')),
          ]),
    );
  }

  Widget _field(TextEditingController controller, String label, String hint,
          {int? maxLength, TextInputType? keyboard}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextField(
              controller: controller,
              maxLength: maxLength,
              keyboardType: keyboard,
              decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: const OutlineInputBorder())));

  Future<void> _pickCredentialExpireDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 1, now.month, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 30),
    );
    if (selected == null || !mounted || !_scope.current) return;
    _credentialExpireDate.text =
        '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
  }
}

class _StatusPage extends StatelessWidget {
  const _StatusPage(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('名师入驻')),
      body: Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text(title, style: AppTextStyles.titleMedium),
                const SizedBox(height: 8),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textHint))
              ]))));
}

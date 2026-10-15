import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';

Map<String, dynamic> identityResponseData(dynamic body) {
  if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
    throw FormatException(
        body is Map ? '${body['message'] ?? '返回数据异常'}' : '返回数据异常');
  }
  return Map<String, dynamic>.from(body['data'] as Map);
}

String identityError(Object error) => error is FormatException
    ? error.message.toString()
    : apiSessionFailureMessage(error, '操作失败，请重试');

class IdentityVerificationPage extends StatefulWidget {
  const IdentityVerificationPage({super.key});

  @override
  State<IdentityVerificationPage> createState() =>
      _IdentityVerificationPageState();
}

class _IdentityVerificationPageState extends State<IdentityVerificationPage> {
  final _scope = ApiSessionScope();
  final _name = TextEditingController();
  final _number = TextEditingController();
  Map<String, dynamic> _application = {};
  final Map<String, String> _documents = {};
  final Map<String, Uint8List> _previews = {};
  bool _loading = true;
  bool _busy = false;
  bool _consent = false;
  String? _error;

  bool get _locked => ['pending', 'approved'].contains(_application['status']);

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (!mounted || _scope.current) return;
    _name.clear();
    _number.clear();
    setState(() {
      _application.clear();
      _documents.clear();
      _previews.clear();
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_scope.current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _scope.get('/api/auth/identity');
      final data = identityResponseData(response.data);
      if (!mounted || !_scope.current) return;
      setState(() => _application = data);
    } catch (error) {
      if (mounted && _scope.current) {
        setState(() => _error = identityError(error));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _loading = false);
    }
  }

  Future<void> _pick(String side) async {
    if (_busy || !_scope.current || _locked) return;
    if (!_consent) {
      showAppToast(context, '请先同意识别和审核身份资料');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: Wrap(children: [
          ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted || !_scope.current) return;
    setState(() => _busy = true);
    try {
      final image = await ImagePicker().pickImage(
          source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 100);
      if (image == null || !mounted || !_scope.current) return;
      final bytes = await image.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw const FormatException('图片不能超过8MB');
      }
      if (!mounted || !_scope.current) return;
      final response = await _scope.post('/api/auth/identity/upload',
          data: FormData.fromMap({
            'side': side,
            'recognitionConsent': 'true',
            'file': MultipartFile.fromBytes(bytes, filename: image.name)
          }),
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 45));
      final data = identityResponseData(response.data);
      final documentId = data['documentId'];
      if (documentId is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(documentId)) {
        throw const FormatException('证件上传返回异常，请重试');
      }
      if (!mounted || !_scope.current) return;
      setState(() {
        _documents[side] = documentId;
        _previews[side] = bytes;
      });
      showAppToast(context, '证件识别通过');
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, identityError(error));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _locked || !_scope.current) return;
    final name = _name.text.trim();
    final number = _number.text.trim().toUpperCase();
    if (name.length < 2 ||
        !RegExp(r'^[1-9][0-9]{16}[0-9X]$').hasMatch(number)) {
      showAppToast(context, '请填写真实姓名和18位身份证号');
      return;
    }
    if (!_consent ||
        !_documents.containsKey('front') ||
        !_documents.containsKey('back')) {
      showAppToast(context, '请同意审核并上传身份证正反面');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await _scope.post('/api/auth/identity', data: {
        'realName': name,
        'idCard': number,
        'frontId': _documents['front'],
        'backId': _documents['back'],
        'consentAccepted': true,
      });
      final data = identityResponseData(response.data);
      if (!mounted || !_scope.current) return;
      _number.clear();
      setState(() {
        _application = data;
        _previews.clear();
        _documents.clear();
      });
      showAppToast(context, '实名认证已提交，等待审核');
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, identityError(error));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _busy = false);
    }
  }

  Widget _photo(String side, String label) => OutlinedButton(
        key: ValueKey('identity-photo-$side'),
        onPressed: _busy ? null : () => _pick(side),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_previews[side] case final bytes?)
            Image.memory(bytes,
                height: 110,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text('预览暂不可用，可重新选择照片'))
          else
            const Icon(Icons.add_a_photo_outlined, size: 36),
          const SizedBox(height: 10),
          Text(label, textAlign: TextAlign.center),
          if (_documents.containsKey(side)) const Text('识别通过 · 点击更换'),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('实名认证')),
        body: !_scope.current
            ? const Center(child: Text(apiSessionChangedMessage))
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        TextButton(onPressed: _load, child: const Text('重新加载')),
                      ]))
                    : ListView(padding: const EdgeInsets.all(20), children: [
                        if (_locked) ...[
                          Icon(
                              _application['status'] == 'approved'
                                  ? Icons.verified_outlined
                                  : Icons.hourglass_top,
                              size: 56,
                              color: AppColors.primary),
                          const SizedBox(height: 16),
                          Text(
                              _application['status'] == 'approved'
                                  ? '实名认证已通过'
                                  : '实名认证审核中',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 20),
                          ListTile(
                              title: Text('${_application['realName'] ?? ''}'),
                              subtitle:
                                  Text('${_application['idCardMask'] ?? ''}')),
                          TextButton(
                              onPressed: _load, child: const Text('刷新审核状态')),
                        ] else ...[
                          if (_application['status'] == 'rejected')
                            Padding(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Text(
                                  '审核未通过：${_application['remark'] ?? '请补充清晰的身份证照片'}',
                                  style:
                                      const TextStyle(color: AppColors.error)),
                            ),
                          TextField(
                              controller: _name,
                              enabled: !_busy,
                              maxLength: 64,
                              decoration: const InputDecoration(
                                  labelText: '真实姓名',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(
                              controller: _number,
                              enabled: !_busy,
                              maxLength: 18,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                  labelText: '身份证号',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            key: const ValueKey('identity-consent'),
                            value: _consent,
                            onChanged: _busy
                                ? null
                                : (value) =>
                                    setState(() => _consent = value == true),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('同意实名认证'),
                          ),
                          const SizedBox(height: 16),
                          const Text('请拍摄证件原件，完整露出四角，避开反光；可从相册选择原件照片。背景颜色不限。'),
                          _photo('front', '上传身份证正面（人像面）'),
                          const SizedBox(height: 12),
                          _photo('back', '上传身份证反面（国徽面）'),
                          const SizedBox(height: 20),
                          if (_busy) const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          FilledButton(
                              key: const ValueKey('identity-submit'),
                              onPressed: _busy ? null : _submit,
                              child: Text(_busy ? '正在处理…' : '提交实名认证')),
                        ],
                      ]),
      );
}

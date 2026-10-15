import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../message/message_tone_preview.dart';

Map<String, dynamic> _relationshipResponseData(dynamic body) {
  if (body is! Map ||
      (body['code'] != null && body['code'] != 0) ||
      body['data'] is! Map) {
    throw const FormatException('设置返回异常');
  }
  return Map<String, dynamic>.from(body['data'] as Map);
}

class UserRemarkPage extends StatefulWidget {
  const UserRemarkPage({
    super.key,
    required this.userId,
    required this.initialData,
  });

  final int userId;
  final Map<String, dynamic> initialData;

  @override
  State<UserRemarkPage> createState() => _UserRemarkPageState();
}

class _UserRemarkPageState extends State<UserRemarkPage> {
  final _scope = ApiSessionScope();
  late final TextEditingController _remarkController;
  late final TextEditingController _descriptionController;
  final _imageUrls = <String>[];
  bool _saving = false;
  bool _uploading = false;
  bool _sessionInvalid = false;

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController(
      text: widget.initialData['remark']?.toString() ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.initialData['remarkDescription']?.toString() ?? '',
    );
    final initialImages = widget.initialData['remarkImageUrls'];
    if (initialImages is List) {
      _imageUrls.addAll(
        initialImages
            .map((value) => value.toString())
            .where((url) => url.isNotEmpty),
      );
    }
    apiSessionChanges.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    setState(() {
      _sessionInvalid = true;
      _saving = false;
      _uploading = false;
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    _remarkController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_sessionInvalid || !_scope.current) {
      if (mounted) showAppToast(context, apiSessionChangedMessage);
      return;
    }
    if (_uploading || _imageUrls.length >= 4) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 88);
    if (picked.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      for (final image in picked.take(4 - _imageUrls.length)) {
        final form = FormData.fromMap({
          'file':
              await MultipartFile.fromFile(image.path, filename: image.name),
        });
        final response = await _scope.post(
          '/api/config/upload',
          data: form,
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        );
        final data = _relationshipResponseData(response.data);
        final url = data['url']?.toString().trim();
        if (url?.isNotEmpty == true) _imageUrls.add(url!);
      }
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(context, apiSessionFailureMessage(error, '图片上传失败'));
      }
    } finally {
      if (mounted && _scope.current) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_sessionInvalid || !_scope.current) {
      if (mounted) showAppToast(context, apiSessionChangedMessage);
      return;
    }
    if (_saving || _uploading) return;
    setState(() => _saving = true);
    try {
      final response = await _scope.patch(
        '/api/community/user/${widget.userId}/remark',
        data: {
          'remark': _remarkController.text.trim(),
          'description': _descriptionController.text.trim(),
          'imageUrls': _imageUrls,
        },
      );
      final data = _relationshipResponseData(response.data);
      if (!mounted || !_scope.current) return;
      Navigator.pop(context, data);
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(
          context,
          apiSessionFailureMessage(error, '保存失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted && _scope.current) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF25272B)),
        ),
        centerTitle: true,
        title: Text(
          '备注和描述',
          style: AppTextStyles.titleLarge.copyWith(
            color: const Color(0xFFB2B1C0),
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('remark-confirm'),
            onPressed: _saving || _uploading || _sessionInvalid ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '确认',
                    style: TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: _sessionInvalid
          ? const Center(child: Text(apiSessionChangedMessage))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('备注'),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('remark-field'),
                    controller: _remarkController,
                    maxLength: 15,
                    style:
                        const TextStyle(fontSize: 17, color: Color(0xFF34363B)),
                    decoration: _fieldDecoration('请填写备注'),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle('描述'),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('remark-description-field'),
                    controller: _descriptionController,
                    maxLength: 200,
                    minLines: 6,
                    maxLines: 8,
                    style:
                        const TextStyle(fontSize: 17, color: Color(0xFF34363B)),
                    decoration: _fieldDecoration('请填写描述'),
                  ),
                  const SizedBox(height: 28),
                  _sectionTitle('添加图片'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ..._imageUrls.indexed
                          .map((entry) => _imageTile(entry.$1, entry.$2)),
                      if (_imageUrls.length < 4)
                        InkWell(
                          key: const ValueKey('remark-add-image'),
                          onTap: _uploading ? null : _pickImages,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 92,
                            height: 112,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F7F8),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFE7E7EA)),
                            ),
                            child: _uploading
                                ? const Center(
                                    child: SizedBox.square(
                                      dimension: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : const Icon(Icons.add_rounded,
                                    size: 44, color: Color(0xFF666978)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: AppTextStyles.titleMedium.copyWith(
          color: const Color(0xFF25272B),
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      );

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8E8E96), fontSize: 17),
        filled: true,
        fillColor: const Color(0xFFF7F7F8),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
        counterStyle: const TextStyle(color: Color(0xFFB7B7BD), fontSize: 14),
      );

  Widget _imageTile(int index, String url) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, width: 92, height: 112, fit: BoxFit.cover),
        ),
        Positioned(
          top: -7,
          right: -7,
          child: InkWell(
            onTap: () => setState(() => _imageUrls.removeAt(index)),
            child: const CircleAvatar(
              radius: 11,
              backgroundColor: Color(0xCC33363C),
              child: Icon(Icons.close_rounded, size: 15, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

Future<Map<String, dynamic>?> showUserStealthSettingsSheet(
  BuildContext context, {
  required int userId,
  required Map<String, dynamic> initialData,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _UserStealthSettingsSheet(
      userId: userId,
      initialData: initialData,
    ),
  );
}

class _UserStealthSettingsSheet extends StatefulWidget {
  const _UserStealthSettingsSheet({
    required this.userId,
    required this.initialData,
  });

  final int userId;
  final Map<String, dynamic> initialData;

  @override
  State<_UserStealthSettingsSheet> createState() =>
      _UserStealthSettingsSheetState();
}

class _UserStealthSettingsSheetState extends State<_UserStealthSettingsSheet> {
  final _scope = ApiSessionScope();
  late bool _profile;
  late bool _moments;
  late bool _chat;
  bool _saving = false;
  bool _sessionInvalid = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialData['stealthProfile'] == true;
    _moments = widget.initialData['stealthMoments'] == true;
    _chat = widget.initialData['stealthChat'] == true;
    apiSessionChanges.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    setState(() {
      _sessionInvalid = true;
      _saving = false;
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    super.dispose();
  }

  Future<void> _save() async {
    if (_sessionInvalid || !_scope.current) {
      if (mounted) showAppToast(context, apiSessionChangedMessage);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final response = await _scope.patch(
        '/api/community/user/${widget.userId}/relationship-preferences',
        data: {
          'stealthProfile': _profile,
          'stealthMoments': _moments,
          'stealthChat': _chat,
        },
      );
      final data = _relationshipResponseData(response.data);
      if (mounted && _scope.current) {
        Navigator.pop(context, data);
      }
    } catch (error) {
      if (mounted && _scope.current) {
        showAppToast(
          context,
          apiSessionFailureMessage(error, '保存失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted && _scope.current) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7E7EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    '对TA隐身访问设置',
                    style: AppTextStyles.titleLarge.copyWith(fontSize: 21),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('stealth-save'),
                        onPressed: _saving || _sessionInvalid ? null : _save,
                        child: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('保存'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                '开启后，你访问相应内容时不会留下访问提示',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB0B0B5), fontSize: 14),
              ),
              const SizedBox(height: 20),
              if (_sessionInvalid) ...[
                const Text(
                  apiSessionChangedMessage,
                  style: TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
              ],
              _switchRow('隐身查看TA的主页', _profile,
                  (value) => setState(() => _profile = value)),
              _switchRow('隐身查看TA的瞬间', _moments,
                  (value) => setState(() => _moments = value)),
              _switchRow('隐身查看与TA的私聊对话', _chat,
                  (value) => setState(() => _chat = value)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      height: 70,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 18, color: Color(0xFF292B30)),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.primary,
            onChanged: _saving || _sessionInvalid ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

class SpecialCareSettingsPage extends StatefulWidget {
  const SpecialCareSettingsPage({
    super.key,
    required this.userId,
    required this.initialData,
  });

  final int userId;
  final Map<String, dynamic> initialData;

  @override
  State<SpecialCareSettingsPage> createState() =>
      _SpecialCareSettingsPageState();
}

class _SpecialCareSettingsPageState extends State<SpecialCareSettingsPage> {
  final _scope = ApiSessionScope();
  late bool _enabled;
  late String _sound;
  bool _saving = false;
  bool _sessionInvalid = false;
  final _tonePreview = MessageTonePreview();

  static const _soundLabels = {
    'default': '默认',
    'gentle': '轻柔',
    'clear': '清脆',
  };

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialData['specialCare'] == true;
    final sound = widget.initialData['specialCareSound']?.toString();
    _sound = _soundLabels.containsKey(sound) ? sound! : 'default';
    apiSessionChanges.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted || _scope.current) return;
    setState(() {
      _sessionInvalid = true;
      _saving = false;
    });
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_onSessionChanged);
    unawaited(_tonePreview.dispose());
    super.dispose();
  }

  Future<void> _previewSound(String sound) async {
    await _tonePreview.play(sound);
    if (sound == 'silent' && mounted) {
      showAppToast(context, '静音模式不会播放提示音');
    }
  }

  Future<void> _update({bool? enabled, String? sound}) async {
    if (_sessionInvalid || !_scope.current) {
      if (mounted) showAppToast(context, apiSessionChangedMessage);
      return;
    }
    if (_saving) return;
    final previousEnabled = _enabled;
    final previousSound = _sound;
    setState(() {
      if (enabled != null) _enabled = enabled;
      if (sound != null) _sound = sound;
      _saving = true;
    });
    try {
      final response = await _scope.patch(
        '/api/community/user/${widget.userId}/relationship-preferences',
        data: {
          if (enabled != null) 'specialCare': enabled,
          if (sound != null) 'specialCareSound': sound,
        },
      );
      final data = _relationshipResponseData(response.data);
      if (enabled != null && data['specialCare'] is! bool) {
        throw const FormatException('特别关心状态返回异常');
      }
      final returnedSound = data['specialCareSound']?.toString();
      if (sound != null && !_soundLabels.containsKey(returnedSound)) {
        throw const FormatException('提示音设置返回异常');
      }
      if (mounted && _scope.current) {
        setState(() {
          if (data['specialCare'] is bool) {
            _enabled = data['specialCare'] == true;
          }
          if (_soundLabels.containsKey(returnedSound)) _sound = returnedSound!;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _enabled = previousEnabled;
        _sound = previousSound;
      });
      if (_scope.current) {
        showAppToast(
          context,
          apiSessionFailureMessage(error, '设置失败，请稍后重试'),
        );
      }
    } finally {
      if (mounted && _scope.current) setState(() => _saving = false);
    }
  }

  Future<void> _chooseSound() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '消息提示音',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ),
            ..._soundLabels.entries.map(
              (entry) => ListTile(
                onTap: () {
                  unawaited(_previewSound(entry.key));
                  Navigator.pop(context, entry.key);
                },
                title: Text(entry.value),
                trailing: Icon(
                  entry.key == _sound
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: entry.key == _sound
                      ? AppColors.primary
                      : const Color(0xFFB8B8BD),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && selected != _sound && mounted && _scope.current) {
      await _update(sound: selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F8F9),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('特别关心设置'),
        ),
        body: Column(
          children: [
            Material(
              color: Colors.white,
              child: SwitchListTile.adaptive(
                key: const ValueKey('special-care-switch'),
                value: _enabled,
                activeTrackColor: AppColors.primary,
                onChanged: _saving || _sessionInvalid
                    ? null
                    : (value) => _update(enabled: value),
                title: const Text('特别关心', style: TextStyle(fontSize: 19)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              ),
            ),
            if (_sessionInvalid)
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 0, 22, 14),
                child: Text(
                  apiSessionChangedMessage,
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            Material(
              color: Colors.white,
              child: ListTile(
                key: const ValueKey('special-care-sound'),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                title: const Text('消息提示音', style: TextStyle(fontSize: 18)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _soundLabels[_sound]!,
                      style: const TextStyle(
                          color: Color(0xFFAAAAAF), fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 18, color: Color(0xFFB8B8BD)),
                  ],
                ),
                onTap: _saving || _sessionInvalid ? null : _chooseSound,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

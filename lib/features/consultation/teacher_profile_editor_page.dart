import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/network/media_review.dart';
import 'teacher_profile_updates.dart';
import '../../core/utils/app_toast.dart';

class TeacherProfileEditorPage extends StatefulWidget {
  const TeacherProfileEditorPage({super.key, required this.profile});
  final Map<String, dynamic> profile;
  @override
  State<TeacherProfileEditorPage> createState() =>
      _TeacherProfileEditorPageState();
}

class _TeacherProfileEditorPageState extends State<TeacherProfileEditorPage> {
  final _scope = ApiSessionScope();
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _intro;
  late final TextEditingController _education;
  late final TextEditingController _experience;
  late final TextEditingController _specialties;
  late String _avatar;
  bool _uploading = false;
  bool _saving = false;
  bool _avatarChanged = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p['nickname']?.toString() ?? '');
    _intro = TextEditingController(text: p['serviceIntro']?.toString() ?? '');
    _education = TextEditingController(text: p['education']?.toString() ?? '');
    _experience =
        TextEditingController(text: p['experienceYears']?.toString() ?? '0');
    _specialties = TextEditingController(
        text: (p['specialties'] as List? ?? []).join('、'));
    _avatar = p['avatarUrl']?.toString() ?? '';
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _intro,
      _education,
      _experience,
      _specialties
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseAvatar() async {
    if (_uploading || _saving || !_scope.current) return;
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1024, imageQuality: 90);
      if (file == null || !mounted || !_scope.current) return;
      setState(() => _uploading = true);
      final response = await _scope.post('/api/config/upload',
          data: FormData.fromMap({
            'file':
                await MultipartFile.fromFile(file.path, filename: file.name),
            'moderationScope': 'profile'
          }));
      final media = await awaitMediaReview(response.data,
          fetchReview: (path) => _scope.get(path));
      final url = media['url']?.toString() ?? '';
      if (url.isEmpty) throw const FormatException();
      if (mounted && _scope.current) {
        setState(() {
          _avatar = url;
          _avatarChanged = true;
        });
      }
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '头像上传失败，请重试');
    } finally {
      if (mounted && _scope.current) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _uploading ||
        !_scope.current ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    final p = widget.profile;
    try {
      final response =
          await _scope.put('/api/consultation/teacher/service', data: {
        for (final key in [
          'displayTitle',
          'voiceIntroUrl',
          'serviceNotice',
          'privatePricePerMin',
          'publicPricePerMin',
          'canPrivate',
          'canLive',
          'serviceStatus'
        ])
          key: p[key],
        'teacherName': _name.text.trim(),
        if (_avatarChanged) 'teacherAvatarUrl': _avatar,
        'serviceIntro': _intro.text.trim(),
        'education': _education.text.trim(),
        'experienceYears': int.parse(_experience.text.trim()),
        'specialties': _specialties.text
            .split(RegExp(r'[、,，\n]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(8)
            .toList(),
      });
      final payload = response.data;
      if (payload is! Map || payload['code'] != 0 || payload['data'] is! Map) {
        throw const FormatException('名师资料保存失败');
      }
      final updated = Map<String, dynamic>.from(payload['data'] as Map);
      if (mounted && _scope.current) {
        teacherProfileUpdates.value = TeacherProfileUpdate(updated);
        Navigator.pop(context, updated);
      }
    } catch (_) {
      if (mounted && _scope.current) showAppToast(context, '名师资料保存失败，请重试');
    } finally {
      if (mounted && _scope.current) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: apiSessionChanges,
        builder: (context, _, __) => _scope.current
            ? _editor(context)
            : Scaffold(
                appBar: AppBar(title: const Text('名师资料')),
                body: const Center(child: Text(apiSessionChangedMessage))),
      );

  Widget _editor(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('名师资料')),
        body: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Center(
                  child: InkWell(
                      onTap: _chooseAvatar,
                      borderRadius: BorderRadius.circular(48),
                      child: Column(children: [
                        CircleAvatar(
                            radius: 42,
                            backgroundImage:
                                _avatar.isEmpty ? null : NetworkImage(_avatar),
                            child: _avatar.isEmpty
                                ? const Icon(Icons.person_outline_rounded,
                                    size: 36)
                                : null),
                        const SizedBox(height: 8),
                        Text(_uploading ? '正在上传…' : '修改名师头像'),
                      ]))),
              const SizedBox(height: 24),
              TextFormField(
                  controller: _name,
                  maxLength: 64,
                  decoration: const InputDecoration(labelText: '名师名称'),
                  validator: (value) =>
                      value?.trim().isNotEmpty == true ? null : '请填写名师名称'),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _specialties,
                  maxLength: 255,
                  decoration: const InputDecoration(
                      labelText: '擅长领域', hintText: '多个领域用顿号分隔')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _intro,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: '名师个人介绍')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _education,
                  maxLength: 255,
                  decoration: const InputDecoration(labelText: '学历')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: _experience,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '相关服务经验（年）'),
                  validator: (value) {
                    final years = int.tryParse(value?.trim() ?? '');
                    return years != null && years >= 0 && years <= 80
                        ? null
                        : '请填写 0 到 80 的年数';
                  }),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: _saving || _uploading ? null : _save,
                  child: Text(_saving ? '正在保存…' : '保存名师资料')),
            ])),
      );
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/media_review.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/image_utils.dart';
import '../../core/utils/report_utils.dart';
import '../../shared/widgets/reference_action_icons.dart';
import '../community/user_profile_page.dart';
import 'voice_room_backgrounds.dart';

class VoiceRoomProfilePage extends StatefulWidget {
  const VoiceRoomProfilePage({
    super.key,
    required this.room,
    required this.isOwner,
  });

  final Map<String, dynamic> room;
  final bool isOwner;

  @override
  State<VoiceRoomProfilePage> createState() => _VoiceRoomProfilePageState();
}

class _VoiceRoomProfilePageState extends State<VoiceRoomProfilePage> {
  static const _categories = [
    '情感倾听',
    '传统文化',
    '事业成长',
    '生活闲聊',
    '兴趣同好',
  ];

  late final TextEditingController _title;
  late final TextEditingController _notice;
  late String _category;
  String _coverUrl = '';
  File? _pickedBackground;
  bool _saving = false;

  bool get _master => widget.room['roomType'] == 'master';

  @override
  void initState() {
    super.initState();
    _title =
        TextEditingController(text: widget.room['title']?.toString() ?? '');
    _notice =
        TextEditingController(text: widget.room['notice']?.toString() ?? '');
    final savedCategory = widget.room['category']?.toString() ?? '';
    _category =
        _categories.contains(savedCategory) ? savedCategory : _categories.first;
    final savedCover = widget.room['coverUrl']?.toString().trim() ?? '';
    _coverUrl =
        savedCover.isEmpty ? voiceRoomDefaultBackground.coverValue : savedCover;
  }

  @override
  void dispose() {
    _title.dispose();
    _notice.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 2) {
      showAppToast(context, '房间名称至少2个字');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_pickedBackground != null) {
        final compressed = await ImageUtils.compressForUpload(
          _pickedBackground!,
          maxSize: 1600,
          quality: 88,
        );
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(compressed.path,
              filename: 'room_background.jpg'),
          'moderationScope': 'public',
        });
        final upload =
            await apiClient.post('/api/config/upload', data: formData);
        final reviewed = await awaitMediaReview(upload.data);
        _coverUrl = reviewed['url']?.toString() ?? _coverUrl;
      }
      final response = await apiClient.put(
        '/api/consultation/rooms/${widget.room['id']}',
        data: {
          'title': _title.text.trim(),
          'notice': _notice.text.trim(),
          'category': _category,
          'coverUrl': _coverUrl,
        },
      );
      final data = (response.data as Map?)?['data'];
      if (!mounted) return;
      showAppToast(context, '房间资料已更新');
      Navigator.pop(
          context, data is Map ? Map<String, dynamic>.from(data) : true);
    } on DioException catch (e) {
      if (mounted) {
        showAppToast(context,
            (e.response?.data as Map?)?['message']?.toString() ?? '保存失败');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickBackground() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (file != null && mounted) {
      setState(() => _pickedBackground = File(file.path));
    }
  }

  void _openOwnerProfile() {
    final owner = widget.room['owner'];
    final id = owner is Map ? (owner['userId'] as num?)?.toInt() : null;
    if (id == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => UserProfilePage(userId: id)));
  }

  Future<void> _reportRoom() async {
    final roomId = (widget.room['id'] as num?)?.toInt();
    if (roomId == null) {
      showAppToast(context, '暂时无法举报该房间');
      return;
    }
    await showReportSheet(
      context,
      targetType: 'voice_room',
      targetId: roomId,
      title: '举报语音房',
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.room['owner'] is Map
        ? widget.room['owner'] as Map
        : const <String, dynamic>{};
    final avatar = owner['avatarUrl']?.toString() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFF132824),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.isOwner ? '房间资料' : '关于房间'),
        actions: [
          if (widget.isOwner)
            TextButton(
              onPressed: _saving ? null : _save,
              child:
                  const Text('保存', style: TextStyle(color: Color(0xFFF0D49B))),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Material(
            color: Colors.white.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: _openOwnerProfile,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFFE8D4A9),
                    backgroundImage:
                        avatar.isNotEmpty ? NetworkImage(avatar) : null,
                    child: avatar.isEmpty
                        ? const Icon(Icons.person_rounded,
                            color: Color(0xFF173F3B))
                        : null,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(owner['nickname']?.toString() ?? '房主',
                            style: AppTextStyles.titleMedium
                                .copyWith(color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(
                          '房间号 ${widget.room['roomNo'] ?? '-'} · 热度 ${widget.room['onlineCount'] ?? 0}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                        if (widget.isOwner)
                          const Padding(
                            padding: EdgeInsets.only(top: 5),
                            child: Text('头像和昵称请在个人主页修改',
                                style: TextStyle(
                                    color: Color(0xFFD9BF86), fontSize: 10)),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colors.white38),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.isOwner) ...[
            VoiceRoomOfficialBackgroundPicker(
              currentValue: _pickedBackground == null ? _coverUrl : '',
              dark: true,
              onSelected: (background) => setState(() {
                _pickedBackground = null;
                _coverUrl = background.coverValue;
              }),
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.white.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: _pickBackground,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 74,
                        height: 52,
                        child: _pickedBackground != null
                            ? Image.file(_pickedBackground!, fit: BoxFit.cover)
                            : voiceRoomBackgroundImage(_coverUrl) != null
                                ? Image(
                                    image: voiceRoomBackgroundImage(_coverUrl)!,
                                    fit: BoxFit.cover,
                                  )
                                : Image.asset(
                                    'images/wish_prayer_heaven_earth.png',
                                    fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('从相册选择',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 4),
                          Text('也可以使用自己的清晰竖图',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 10)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: Colors.white38),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _DarkField(
            controller: _title,
            label: '房间名称',
            enabled: widget.isOwner,
            maxLength: 120,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            dropdownColor: const Color(0xFF223B36),
            style: const TextStyle(color: Colors.white),
            decoration: _decoration('派对类型'),
            items: _categories
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: widget.isOwner
                ? (value) => setState(() => _category = value ?? _category)
                : null,
          ),
          const SizedBox(height: 12),
          _DarkField(
            controller: _notice,
            label: '派对公告',
            enabled: widget.isOwner,
            maxLength: 500,
            maxLines: 4,
          ),
          if (widget.isOwner) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(children: [
                Icon(Icons.public_rounded, color: Color(0xFFF0D49B)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '房间公开进入 · 不设密码 · 麦位随申请动态增加',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 11, height: 1.5),
                  ),
                ),
              ]),
            ),
            if (_master) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(children: [
                  const Text('公开连线价格', style: TextStyle(color: Colors.white70)),
                  const Spacer(),
                  Text(
                    '${(widget.room['pricePerMin'] as num?)?.toStringAsFixed(2) ?? '0.00'}币/分钟',
                    style: const TextStyle(
                      color: Color(0xFFF0D49B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 9),
              Text(
                '公开连线和私人专线价格请在老师工作台设置，修改后仅影响新服务。',
                style: AppTextStyles.bodySmall
                    .copyWith(color: const Color(0xFFD9BF86), height: 1.5),
              ),
            ],
          ],
          const SizedBox(height: 22),
          if (widget.isOwner)
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: const Color(0xFF173F3B),
                backgroundColor: const Color(0xFFF0D49B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存房间资料'),
            ),
          if (!widget.isOwner)
            OutlinedButton.icon(
              onPressed: _reportRoom,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              icon: const ReferenceActionGlyph(
                type: ReferenceActionIconType.report,
                size: 18,
                color: Colors.white70,
              ),
              label: const Text('举报房间'),
            ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withValues(alpha: .06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF0D49B)),
        ),
      );
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.maxLength,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final int? maxLength;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        maxLength: maxLength,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          hintStyle: const TextStyle(color: Colors.white30),
          counterStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .06),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFF0D49B)),
          ),
        ),
      );
}

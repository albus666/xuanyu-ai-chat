import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/network/media_review.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/image_utils.dart';
import 'voice_room_backgrounds.dart';
import 'voice_room_overlay_controller.dart';
import 'voice_room_design.dart';

class CreateVoiceRoomPage extends StatefulWidget {
  const CreateVoiceRoomPage({super.key, required this.roomType});
  final String roomType;

  @override
  State<CreateVoiceRoomPage> createState() => _CreateVoiceRoomPageState();
}

class _CreateVoiceRoomPageState extends State<CreateVoiceRoomPage> {
  static const _categories = [
    '情感倾听',
    '传统文化',
    '事业成长',
    '生活闲聊',
    '兴趣同好',
  ];

  final _title = TextEditingController();
  final _password = TextEditingController();
  double? _publicPrice;
  double? _privatePrice;
  String _category = '情感倾听';
  String _accessType = 'public';
  bool _autonomousMic = false;
  File? _pickedBackground;
  String _existingCoverUrl = voiceRoomDefaultBackground.coverValue;
  Map<String, dynamic>? _lastRoom;
  bool _loadingLastRoom = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.roomType == 'master') _loadTeacherPrices();
    _loadLastRoom();
  }

  Future<void> _loadLastRoom() async {
    try {
      final response = await apiClient.get(
        '/api/consultation/rooms',
        queryParameters: {'type': widget.roomType, 'mine': 'last'},
      );
      final data = (response.data as Map?)?['data'];
      final room = data is Map ? data['room'] : null;
      if (!mounted) return;
      setState(() {
        _lastRoom = room is Map ? Map<String, dynamic>.from(room) : null;
        _loadingLastRoom = false;
      });
    } on DioException catch (_) {
      if (mounted) setState(() => _loadingLastRoom = false);
    } catch (_) {
      if (mounted) setState(() => _loadingLastRoom = false);
    }
  }

  Future<void> _loadTeacherPrices() async {
    try {
      final response = await apiClient.get('/api/consultation/teacher/service');
      final data = (response.data as Map?)?['data'];
      if (!mounted || data is! Map) return;
      setState(() {
        _privatePrice = (data['privatePricePerMin'] as num?)?.toDouble();
        _publicPrice = (data['publicPricePerMin'] as num?)?.toDouble();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickBackground() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (file != null && mounted) {
      setState(() {
        _pickedBackground = File(file.path);
        _existingCoverUrl = '';
      });
    }
  }

  void _applyLastRoom() {
    final room = _lastRoom;
    if (room == null) return;
    _title.text = room['title']?.toString() ?? '';
    final category = room['category']?.toString() ?? '';
    setState(() {
      _category = _categories.contains(category) ? category : _categories.first;
      _pickedBackground = null;
      _existingCoverUrl = room['coverUrl']?.toString() ?? '';
      _accessType = const {'public', 'unlisted', 'password'}
              .contains(room['accessType']?.toString())
          ? room['accessType'].toString()
          : 'public';
      _autonomousMic = room['autonomousMic'] == true;
    });
  }

  Future<void> _openOrRecreateLastRoom() async {
    final room = _lastRoom;
    if (room == null || _submitting) return;
    final status = room['status']?.toString();
    if (const {'scheduled', 'live', 'paused'}.contains(status)) {
      final roomId = (room['roomId'] as num?)?.toInt();
      if (roomId == null) return;
      final opened = VoiceRoomOverlayController.instance.open(roomId);
      if (!opened) {
        if (mounted) showAppToast(context, '请先退出当前语音房');
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    _applyLastRoom();
    await _submit();
  }

  Future<void> _submit() async {
    final master = widget.roomType == 'master';
    if (VoiceRoomOverlayController.instance.hasActiveRoom) {
      showAppToast(context, '请先退出当前语音房');
      return;
    }
    if (_title.text.trim().length < 2) {
      showAppToast(context, '请输入至少2个字的房间标题');
      return;
    }
    if (_accessType == 'password' && _password.text.trim().length < 4) {
      showAppToast(context, '房间口令至少4位');
      return;
    }
    setState(() => _submitting = true);
    try {
      var coverUrl = _existingCoverUrl;
      if (_pickedBackground != null) {
        final compressed = await ImageUtils.compressForUpload(
          _pickedBackground!,
          maxSize: 1600,
          quality: 88,
        );
        final upload = await apiClient.post(
          '/api/config/upload',
          data: FormData.fromMap({
            'file': await MultipartFile.fromFile(
              compressed.path,
              filename: 'room_background.jpg',
            ),
            'moderationScope': 'public',
          }),
        );
        final reviewed = await awaitMediaReview(upload.data);
        coverUrl = reviewed['url']?.toString() ?? '';
      }
      final response = await apiClient.post('/api/consultation/rooms', data: {
        'roomType': widget.roomType,
        'title': _title.text.trim(),
        'notice': '',
        'category': _category,
        'coverUrl': coverUrl,
        'accessType': _accessType,
        if (_accessType == 'password') 'password': _password.text.trim(),
        'autonomousMic': !master && _autonomousMic,
        'recommendEnabled': _accessType != 'unlisted',
      });
      final data = (response.data as Map?)?['data'];
      if (data is! Map || data['id'] is! num) throw const FormatException();
      if (!mounted) return;
      final roomId = (data['id'] as num).toInt();
      Navigator.of(context).pop(true);
      VoiceRoomOverlayController.instance.open(roomId);
    } on DioException catch (e) {
      if (mounted) {
        showAppToast(context,
            (e.response?.data as Map?)?['message']?.toString() ?? '创建房间失败');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final master = widget.roomType == 'master';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(master ? '创建名师房' : '创建聊天房间'),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFCDEBF6),
              Color(0xFFE6F4F8),
              Color(0xFFF1ECF7),
              Colors.white
            ],
            stops: [0, .12, .24, .48],
          ),
        ),
        child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              _RoomTypeBanner(master: master),
              if (_loadingLastRoom) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.primary,
                  backgroundColor: Color(0x337ADDD8),
                ),
              ] else if (_lastRoom != null) ...[
                const SizedBox(height: 12),
                _LastRoomShortcut(
                  room: _lastRoom!,
                  onOpenOrCreate: _openOrRecreateLastRoom,
                  onApply: _submitting ? null : _applyLastRoom,
                  busy: _submitting,
                ),
              ],
              const SizedBox(height: 14),
              InkWell(
                onTap: _submitting ? null : _pickBackground,
                borderRadius: BorderRadius.circular(22),
                child: Ink(
                  height: 190,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    image: _pickedBackground != null
                        ? DecorationImage(
                            image: FileImage(_pickedBackground!),
                            fit: BoxFit.cover,
                          )
                        : voiceRoomBackgroundImage(_existingCoverUrl) != null
                            ? DecorationImage(
                                image: voiceRoomBackgroundImage(
                                    _existingCoverUrl)!,
                                fit: BoxFit.cover,
                              )
                            : null,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x261AC4C4),
                        blurRadius: 22,
                        offset: Offset(0, 9),
                      ),
                    ],
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    if (_pickedBackground == null && _existingCoverUrl.isEmpty)
                      const _AuroraPreview(),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x08000000), Color(0x660A3145)],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 13,
                      bottom: 13,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .9),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.wallpaper_rounded,
                              size: 18, color: AppColors.primaryDark),
                          const SizedBox(width: 6),
                          Text(
                            _pickedBackground == null ? '相册背景' : '更换背景',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              VoiceRoomOfficialBackgroundPicker(
                currentValue:
                    _pickedBackground == null ? _existingCoverUrl : '',
                onSelected: (background) => setState(() {
                  _pickedBackground = null;
                  _existingCoverUrl = background.coverValue;
                }),
              ),
              const SizedBox(height: 18),
              _CreateField(
                icon: Icons.title_rounded,
                label: '房间标题',
                child: TextField(
                  controller: _title,
                  maxLength: 40,
                  textAlign: TextAlign.end,
                  decoration: const InputDecoration(
                    hintText: '给今晚留一点安静',
                    counterText: '',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              _CreateField(
                icon: Icons.visibility_outlined,
                label: '谁可以进入',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<String>(
                    initialValue: _accessType,
                    position: PopupMenuPosition.under,
                    onSelected: (value) => setState(() => _accessType = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'public', child: Text('公开房间')),
                      PopupMenuItem(value: 'unlisted', child: Text('仅邀请可进')),
                      PopupMenuItem(value: 'password', child: Text('口令进入')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(voiceRoomAccessLabel(_accessType)),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded, size: 20),
                      ]),
                    ),
                  ),
                ),
              ),
              if (_accessType == 'password')
                _CreateField(
                  icon: Icons.password_rounded,
                  label: '房间口令',
                  child: TextField(
                    controller: _password,
                    maxLength: 16,
                    obscureText: true,
                    textAlign: TextAlign.end,
                    decoration: const InputDecoration(
                      hintText: '4—16位',
                      counterText: '',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              if (!master)
                _CreateField(
                  icon: Icons.mic_external_on_outlined,
                  label: '自主上麦',
                  child: SwitchListTile.adaptive(
                    value: _autonomousMic,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      _autonomousMic ? '成员可直接上麦' : '上麦需要房主同意',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onChanged: (value) =>
                        setState(() => _autonomousMic = value),
                  ),
                ),
              _CreateField(
                icon: Icons.grid_view_rounded,
                label: '房间分类',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<String>(
                    initialValue: _category,
                    position: PopupMenuPosition.under,
                    constraints:
                        const BoxConstraints(minWidth: 132, maxWidth: 168),
                    onSelected: (value) => setState(() => _category = value),
                    itemBuilder: (_) => _categories
                        .map((item) => PopupMenuItem<String>(
                              value: item,
                              child: Text(item),
                            ))
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_category),
                          const SizedBox(width: 4),
                          const Icon(Icons.expand_more_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (master) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF2FCFB), Color(0xFFF2F7FF)],
                    ),
                    border: Border.all(color: const Color(0x667ADDD8)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('连线方式',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 6),
                        _PriceRow(
                          icon: Icons.call_outlined,
                          label: '公开连线',
                          value:
                              '${_publicPrice?.toStringAsFixed(2) ?? '--'}币/分钟',
                        ),
                        const Divider(height: 1, color: Color(0x557ADDD8)),
                        _PriceRow(
                          icon: Icons.lock_outline_rounded,
                          label: '私密连线',
                          value:
                              '${_privatePrice?.toStringAsFixed(2) ?? '--'}币/分钟',
                        ),
                      ]),
                ),
                const SizedBox(height: 7),
                const Text(
                  '旁听免费；公开连线与私人专线独立计费。付费麦位固定保护，自主上麦不会绕过计费确认。',
                  style: TextStyle(color: AppColors.textHint, fontSize: 11),
                ),
                const SizedBox(height: 18),
              ],
              const SizedBox(height: 22),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _submitting ? null : _submit,
                  borderRadius: BorderRadius.circular(25),
                  child: Ink(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: _submitting ? null : AppColors.primaryGradient,
                      color: _submitting ? AppColors.backgroundDeep : null,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: _submitting
                          ? null
                          : const [
                              BoxShadow(
                                color: Color(0x351AC4C4),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              )
                            ],
                    ),
                    child: Center(
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary),
                            )
                          : const Text(
                              '创建房间',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ]),
      ),
    );
  }
}

class _LastRoomShortcut extends StatelessWidget {
  const _LastRoomShortcut({
    required this.room,
    required this.onOpenOrCreate,
    required this.onApply,
    required this.busy,
  });

  final Map<String, dynamic> room;
  final VoidCallback onOpenOrCreate;
  final VoidCallback? onApply;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final active = const {'scheduled', 'live', 'paused'}
        .contains(room['status']?.toString());
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0FCFA), Color(0xFFF3F0FC)],
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0x667ADDD8)),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(
            active ? Icons.graphic_eq_rounded : Icons.history_rounded,
            color: AppColors.primaryDark,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                active ? '你有一个未结束的房间' : '上次创建',
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                room['title']?.toString() ?? '语音房',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (!active)
          TextButton(
            onPressed: onApply,
            child: const Text('沿用设置'),
          ),
        FilledButton(
          onPressed: busy ? null : onOpenOrCreate,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 13),
          ),
          child: Text(active ? '返回房间' : '一键开房'),
        ),
      ]),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 31,
            height: 31,
            decoration: const BoxDecoration(
              color: Color(0xFFE6FAF7),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 9),
          Text(label, style: AppTextStyles.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFD97706),
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
      );
}

class _RoomTypeBanner extends StatelessWidget {
  const _RoomTypeBanner({required this.master});
  final bool master;

  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white),
        ),
        child: Row(children: [
          _type('在线名师', master),
          _type('免费派对', !master, note: '全程免费'),
        ]),
      );

  Widget _type(String label, bool selected, {String? note}) => Expanded(
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? AppColors.primaryGradient : null,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (note != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: .22)
                      : const Color(0xFFF1ECF7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  note,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF8A6DB2),
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ]),
        ),
      );
}

class _CreateField extends StatelessWidget {
  const _CreateField({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0x337A8794))),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0xFFE6FAF7),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 10),
          Text(label, style: AppTextStyles.bodyMedium),
          const SizedBox(width: 12),
          Expanded(child: child),
        ]),
      );
}

class _AuroraPreview extends StatelessWidget {
  const _AuroraPreview();

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: const Stack(fit: StackFit.expand, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF21D4C5),
                  Color(0xFF88E5FE),
                  Color(0xFF8DA4F1),
                  Color(0xFFC79DEF),
                ],
              ),
            ),
          ),
          Positioned(
            left: -45,
            top: 18,
            child: _GlowCircle(size: 150, color: Color(0x99FFFFFF)),
          ),
          Positioned(
            right: -32,
            bottom: -42,
            child: _GlowCircle(size: 165, color: Color(0x665BE5DD)),
          ),
          Positioned(
            right: 78,
            top: 20,
            child: _GlowCircle(size: 50, color: Color(0x55FFFFFF)),
          ),
        ]),
      );
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      );
}

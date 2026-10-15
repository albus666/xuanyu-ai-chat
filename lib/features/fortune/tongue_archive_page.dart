import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;
import 'package:image_picker/image_picker.dart';

import '../../app/common/routers/names.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import '../../core/utils/image_utils.dart';
import '../../core/widgets/app_gpt_markdown.dart';

class TongueArchivePage extends StatefulWidget {
  const TongueArchivePage({super.key});

  @override
  State<TongueArchivePage> createState() => _TongueArchivePageState();
}

class _TongueArchivePageState extends State<TongueArchivePage> {
  File? _image;
  bool _loading = false;
  String? _report;
  String? _qualityIssue;

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.camera, maxWidth: 1200, imageQuality: 88);
    if (file != null && mounted) {
      setState(() {
        _image = File(file.path);
        _qualityIssue = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_image == null || _loading) return;
    setState(() => _loading = true);
    try {
      final compressed = await ImageUtils.compressPostImage(_image!);
      final response = await apiClient.post(
        '/api/fortune/health-archive/tongue',
        data: FormData.fromMap({
          'healthConsentVersion': '2026-08-27-v1',
          'file': await MultipartFile.fromFile(compressed.path,
              filename: 'tongue.jpg'),
        }),
      );
      final data = response.data is Map ? response.data['data'] : null;
      final content = data is Map ? (data['content'] ?? '').toString().trim() : '';
      if (mounted && content.isNotEmpty) {
        setState(() {
          _report = content;
          _qualityIssue = null;
        });
      } else if (mounted) {
        showAppToast(context, '识别服务未返回报告，请稍后重试');
      }
    } on DioException catch (e) {
      final body = e.response?.data;
      final responseData = body is Map ? body['data'] : null;
      if (mounted &&
          responseData is Map &&
          responseData['needsRetake'] == true) {
        final notes = responseData['qualityNotes'];
        setState(() {
          _qualityIssue = notes is List && notes.isNotEmpty
              ? notes.map((item) => item.toString()).join('；')
              : '舌体、光线或对焦未达到识别要求';
        });
        return;
      }
      final message =
          body is Map ? (body['message'] ?? '提交失败').toString() : '提交失败，请稍后重试';
      if (mounted) showAppToast(context, message);
    } catch (_) {
      if (mounted) showAppToast(context, '提交失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_report != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('舌象特征报告'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('完成'))
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                child: AppGptMarkdown(selectionArea: true, data: _report!),
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
                      '舌象结果已保存，可在今日养生查看饮食、茶饮与作息建议。',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () =>
                            Get.toNamed(RouteNames.homeTodayHealth),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFC),
      appBar: AppBar(
          backgroundColor: const Color(0xFFF7FBFC), title: const Text('舌象分析')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text('在自然光下拍摄舌面', style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text('请关闭美颜和滤镜，舌头自然伸出，不要用力过度。',
                style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Expanded(
              child: GestureDetector(
                onTap: _loading ? null : _pick,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: _image == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                              const Icon(Icons.add_a_photo_outlined,
                                  size: 56, color: AppColors.primary),
                              const SizedBox(height: 12),
                              Text('点击拍摄舌象', style: AppTextStyles.titleSmall),
                            ])
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.file(_image!, fit: BoxFit.cover)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_qualityIssue != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('建议重拍：$_qualityIssue',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: const Color(0xFF9A653B))),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _image == null || _loading ? null : _submit,
                child: Text(_loading ? '正在识别特征…' : '生成舌象特征报告'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '质量合格后将生成中医舌苔分类，并记录舌质、苔色、苔质、厚薄与分布。结果不用于疾病筛查、诊断或治疗。',
              style:
                  AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );
  }
}

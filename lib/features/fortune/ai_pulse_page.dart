import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/common/routers/names.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/app_toast.dart';
import 'pulse_signal_analyzer.dart';

class AiPulsePage extends StatefulWidget {
  const AiPulsePage({super.key});

  @override
  State<AiPulsePage> createState() => _AiPulsePageState();
}

class _AiPulsePageState extends State<AiPulsePage> with WidgetsBindingObserver {
  final PulseSignalAnalyzer _analyzer = PulseSignalAnalyzer();
  CameraController? _camera;
  PulseSignalSnapshot? _snapshot;
  bool _initializing = true;
  bool _processingFrame = false;
  int _lastProcessedFrameMs = 0;
  bool _saving = false;
  bool _torchEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed &&
        mounted &&
        _camera == null) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _torchEnabled = false;
        _error = null;
      });
    }
    try {
      final cameras = await availableCameras();
      final back = cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();
      if (back.isEmpty) throw StateError('未找到可用的后置摄像头');
      CameraController? controller;
      for (final camera in back) {
        final candidate = CameraController(
          camera,
          ResolutionPreset.low,
          enableAudio: false,
          imageFormatGroup: Platform.isIOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.yuv420,
        );
        try {
          await candidate.initialize();
          await candidate.setFlashMode(FlashMode.torch);
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (candidate.value.flashMode != FlashMode.torch) {
            throw StateError('闪光灯未进入常亮状态');
          }
          controller = candidate;
          break;
        } on CameraException catch (error) {
          await candidate.dispose();
          if (error.code == 'CameraAccessDenied' ||
              error.code == 'CameraAccessDeniedWithoutPrompt' ||
              error.code == 'CameraAccessRestricted') {
            rethrow;
          }
        } catch (_) {
          await candidate.dispose();
        }
      }
      if (controller == null) {
        throw StateError('当前设备没有可持续补光的后置摄像头');
      }
      await controller.startImageStream(_processFrame);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _torchEnabled = true;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error =
              e.code == 'CameraAccessDenied' ? '请允许使用相机后再测量' : '相机启动失败，请稍后重试';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  void _processFrame(CameraImage image) {
    if (_processingFrame || !mounted || image.planes.isEmpty) return;
    final frameTimeMs = DateTime.now().millisecondsSinceEpoch;
    if (frameTimeMs - _lastProcessedFrameMs < 80) return;
    _lastProcessedFrameMs = frameTimeMs;
    _processingFrame = true;
    try {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      final rowStride = plane.bytesPerRow;
      final pixelStride = plane.bytesPerPixel ?? 1;
      var sum = 0.0;
      var square = 0.0;
      var count = 0;
      final x0 = image.width ~/ 5;
      final x1 = image.width * 4 ~/ 5;
      final y0 = image.height ~/ 5;
      final y1 = image.height * 4 ~/ 5;
      for (var y = y0; y < y1; y += 12) {
        for (var x = x0; x < x1; x += 12) {
          final index = y * rowStride + x * pixelStride;
          if (index < 0 || index >= bytes.length) continue;
          final colorOffset =
              image.format.group == ImageFormatGroup.bgra8888 ? 2 : 0;
          if (index + colorOffset >= bytes.length) continue;
          final value = bytes[index + colorOffset].toDouble();
          sum += value;
          square += value * value;
          count++;
        }
      }
      if (count < 20) return;
      final mean = sum / count;
      final variance = math.max(0, square / count - mean * mean);
      // 手指覆盖闪光灯后的画面通常亮度适中且纹理较少；过暗、过曝或纹理过多均不计入进度。
      final covered = mean >= 38 && mean <= 245 && variance <= 1800;
      final next = _analyzer.add(
        timeMs: frameTimeMs,
        value: mean,
        fingerCovered: covered,
      );
      if (mounted) setState(() => _snapshot = next);
    } finally {
      _processingFrame = false;
    }
  }

  Future<void> _saveMeasurement() async {
    final measurement = _snapshot?.measurement;
    if (measurement == null || _saving) return;
    setState(() => _saving = true);
    try {
      final response = await apiClient.post(
        '/api/fortune/health-archive/pulse',
        data: {
          ...measurement.toJson(),
          'measuredAt': DateTime.now().toIso8601String(),
          'healthConsentVersion': '2026-08-27-v1',
        },
      );
      if (!mounted) return;
      final data = response.data is Map ? response.data['data'] : null;
      final summary = data is Map ? (data['summary'] ?? '').toString() : '';
      final openDailyHealth = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('脉象参考已建档'),
          content: Text(
            '${summary.isEmpty ? '本次指尖脉搏波已写入体质档案。' : summary}\n\n'
            '结果已保存，可在今日养生查看饮食、茶饮与作息建议。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('完成'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('查看今日养生'),
            ),
          ],
        ),
      );
      if (openDailyHealth == true) {
        await Get.toNamed(RouteNames.homeTodayHealth);
      }
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final body = e.response?.data;
      final message =
          body is Map ? (body['message'] ?? '保存失败').toString() : '保存失败，请稍后重试';
      if (mounted) showAppToast(context, message);
    } catch (_) {
      if (mounted) showAppToast(context, '保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _restart() {
    _analyzer.reset();
    setState(() => _snapshot = null);
  }

  Future<void> _disposeCamera() async {
    final controller = _camera;
    _camera = null;
    _torchEnabled = false;
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    await controller.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7FBFC),
        elevation: 0,
        centerTitle: true,
        title: Text('AI把脉', style: AppTextStyles.titleMedium),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_initializing) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined,
                size: 54, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: _initializeCamera, child: const Text('重新尝试')),
          ]),
        ),
      );
    }

    final snapshot = _snapshot;
    final measuring = snapshot?.stage == PulseCaptureStage.measuring;
    final completed = snapshot?.stage == PulseCaptureStage.completed;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: Column(children: [
        Text(
          completed ? '本次测量完成' : (measuring ? '保持当前姿势' : '轻放手指，等待识别'),
          style: AppTextStyles.titleMedium.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 8),
        Text(
          completed ? '请保存结果，写入你的体质档案' : '使用食指轻轻覆盖后置主摄像头与闪光灯',
          style:
              AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _torchEnabled
                ? const Color(0xFFE7F7F3)
                : const Color(0xFFFFF1EB),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              _torchEnabled
                  ? Icons.flashlight_on_rounded
                  : Icons.flashlight_off_rounded,
              size: 16,
              color: _torchEnabled
                  ? const Color(0xFF168777)
                  : const Color(0xFFC45E45),
            ),
            const SizedBox(width: 5),
            Text(
              _torchEnabled ? '闪光灯已开启 · 可开始采集' : '闪光灯未开启',
              style: AppTextStyles.bodySmall.copyWith(
                color: _torchEnabled
                    ? const Color(0xFF168777)
                    : const Color(0xFFC45E45),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        _buildCameraOrb(snapshot),
        const SizedBox(height: 20),
        Text(
          snapshot?.message ?? '正在检查手指位置',
          style: AppTextStyles.titleSmall.copyWith(
              color: measuring || completed
                  ? AppColors.primary
                  : AppColors.textPrimary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        if (measuring || completed)
          Text(
            '${((snapshot?.progress ?? 0) * 100).round()}%',
            style: AppTextStyles.displayLarge
                .copyWith(color: AppColors.primary, fontSize: 34),
          )
        else
          Text(
            '信号稳定后才会开始计时',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
        const SizedBox(height: 18),
        Container(
          height: 86,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: CustomPaint(
              painter: _PulseWavePainter(snapshot?.waveform ?? const [])),
        ),
        const SizedBox(height: 14),
        if (snapshot?.bpm != null && !completed)
          Text('当前识别 ${snapshot!.bpm!.round()} 次/分 · 信号质量 ${snapshot.quality}%',
              style: AppTextStyles.bodySmall),
        if (completed && snapshot?.measurement != null)
          _buildResult(snapshot!.measurement!),
        const SizedBox(height: 18),
        if (completed)
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: _saving ? null : _restart,
                    child: const Text('重新测量'))),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _saveMeasurement,
                child: Text(_saving ? '保存中…' : '保存到档案'),
              ),
            ),
          ]),
        const SizedBox(height: 18),
        Text(
          '手机指尖光电脉搏波可用于记录脉率、脉律和信号稳定度。浮沉、虚实、弦滑涩紧及寸关尺尚需腕部触诊，本功能不替代中医面诊或医疗检查。',
          style: AppTextStyles.bodySmall
              .copyWith(color: AppColors.textHint, height: 1.55),
        ),
      ]),
    );
  }

  Widget _buildCameraOrb(PulseSignalSnapshot? snapshot) {
    final controller = _camera;
    final active = snapshot?.stage == PulseCaptureStage.measuring ||
        snapshot?.stage == PulseCaptureStage.completed;
    return Container(
      width: 220,
      height: 220,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: active
                ? const [Color(0xFF20C5C5), Color(0xFF76D7CF)]
                : const [Color(0xFFE9B6A9), Color(0xFFD97168)]),
        boxShadow: [
          BoxShadow(
              color: (active ? AppColors.primary : const Color(0xFFD97168))
                  .withValues(alpha: .22),
              blurRadius: 28)
        ],
      ),
      child: ClipOval(
        child: controller == null || !controller.value.isInitialized
            ? const ColoredBox(color: Color(0xFFF1F5F5))
            : Stack(fit: StackFit.expand, children: [
                CameraPreview(controller),
                ColoredBox(
                    color:
                        (active ? AppColors.primary : const Color(0xFFC94C45))
                            .withValues(alpha: .40)),
                Center(
                  child: Icon(
                      active ? Icons.favorite_rounded : Icons.touch_app_rounded,
                      color: Colors.white,
                      size: 60),
                ),
              ]),
      ),
    );
  }

  Widget _buildResult(PulseMeasurement value) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('本次脉象参考', style: AppTextStyles.titleSmall),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xFFE9F8F7),
                borderRadius: BorderRadius.circular(99)),
            child: Text('质量 ${value.qualityGrade}级',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 13),
        Text('${value.traditionalRateReference}（频率类脉象）',
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.primaryDark)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _metric('平均脉率', value.averageBpm.round().toString(), '次/分'),
          _metric('脉率范围',
              '${value.minimumBpm.round()}–${value.maximumBpm.round()}', '次/分'),
          _metric('信号质量', value.signalQuality.toString(), '%'),
        ]),
        const SizedBox(height: 15),
        _profileLine('中医分类', value.traditionalRateReference),
        _profileLine('脉率属性', value.rateAttribute),
        _profileLine('脉律状态', value.rhythmAttribute),
        _profileLine('已识别', '脉率、窗口脉律、信号稳定度'),
        _profileLine('未测维度', '寸关尺、浮沉、虚实、弦滑涩紧'),
      ]),
    );
  }

  Widget _profileLine(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textHint)),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textPrimary, height: 1.4)),
          ),
        ]),
      );

  Widget _metric(String label, String value, String unit) => Column(children: [
        Text(label,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 6),
        Text(value,
            style: AppTextStyles.titleSmall
                .copyWith(color: AppColors.textPrimary)),
        Text(unit,
            style: AppTextStyles.bodySmall
                .copyWith(fontSize: 10, color: AppColors.textHint)),
      ]);
}

class _PulseWavePainter extends CustomPainter {
  const _PulseWavePainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = const Color(0xFFE1EEEE)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, size.height / 2), Offset(size.width, size.height / 2), base);
    if (values.length < 2) return;
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y = size.height / 2 - values[i] * size.height * .38;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PulseWavePainter oldDelegate) =>
      oldDelegate.values != values;
}

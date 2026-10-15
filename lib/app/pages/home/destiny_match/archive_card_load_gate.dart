import 'package:flutter/material.dart';

/// 人物图也就绪后再整体展示卡片；后台换图期间保留上一张完整卡片。
class ArchiveCardLoadGate extends StatefulWidget {
  const ArchiveCardLoadGate({
    super.key,
    required this.assetPath,
    required this.placeholder,
    required this.child,
  });

  final String? assetPath;
  final Widget placeholder;
  final Widget child;

  @override
  State<ArchiveCardLoadGate> createState() => _ArchiveCardLoadGateState();
}

class _ArchiveCardLoadGateState extends State<ArchiveCardLoadGate> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Widget? _visible;
  String? _readyAsset;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ArchiveCardLoadGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assetPath == _readyAsset && _visible != null) {
      _visible = widget.child;
    } else if (widget.assetPath != oldWidget.assetPath) {
      _resolve();
    }
  }

  void _resolve() {
    _unsubscribe();
    final asset = widget.assetPath;
    if (asset == null) {
      _readyAsset = null;
      _visible = widget.child;
      return;
    }
    var resolving = true;
    void ready() {
      if (!mounted) return;
      void apply() {
        _readyAsset = asset;
        _visible = widget.child;
      }

      if (resolving) {
        apply();
      } else {
        setState(apply);
      }
    }

    _stream = AssetImage(asset).resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((image, synchronousCall) {
      image.dispose();
      ready();
    }, onError: (_, __) => ready());
    _stream!.addListener(_listener!);
    resolving = false;
  }

  void _unsubscribe() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _visible ?? widget.placeholder;
}

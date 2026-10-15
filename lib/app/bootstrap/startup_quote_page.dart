import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StartupQuotePage extends StatefulWidget {
  const StartupQuotePage({
    super.key,
    required this.quote,
    required this.onContinue,
    this.onReady,
  });

  final String quote;
  final VoidCallback onContinue;
  final VoidCallback? onReady;

  @override
  State<StartupQuotePage> createState() => _StartupQuotePageState();
}

class _StartupQuotePageState extends State<StartupQuotePage> {
  bool _readyReported = false;
  String get quote => widget.quote;
  VoidCallback get onContinue => widget.onContinue;

  void _reportReady() {
    if (_readyReported) return;
    _readyReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        key: const ValueKey<String>('startup-quote-page'),
        backgroundColor: const Color(0xFFF6FAFF),
        body: Semantics(
          button: true,
          label: '点击进入玄遇',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onContinue,
            child: CustomPaint(
              painter: const _StartupQuoteBackgroundPainter(),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final iconSize = (constraints.maxWidth * .27)
                        .clamp(82.0, 104.0)
                        .toDouble();
                    final decodedIconSize =
                        (iconSize * MediaQuery.devicePixelRatioOf(context))
                            .ceil()
                            .clamp(164, 416);
                    final quoteLength = quote.runes.length;
                    final quoteWidthFactor = quoteLength <= 10
                        ? .88
                        : quoteLength <= 24
                            ? .84
                            : .78;
                    final quoteWidth = (constraints.maxWidth * quoteWidthFactor)
                        .clamp(228.0, 350.0)
                        .toDouble();
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    iconSize * .24,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x18534D8E),
                                      blurRadius: 26,
                                      offset: Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    iconSize * .24,
                                  ),
                                  child: Image.asset(
                                    'assets/app_icon.png',
                                    key: const ValueKey<String>(
                                      'startup-quote-icon',
                                    ),
                                    width: iconSize,
                                    height: iconSize,
                                    cacheWidth: decodedIconSize,
                                    cacheHeight: decodedIconSize,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                    frameBuilder: (_, child, frame, __) {
                                      if (frame != null) _reportReady();
                                      return child;
                                    },
                                    errorBuilder: (_, __, ___) {
                                      _reportReady();
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 34),
                              SizedBox(
                                width: quoteWidth,
                                height: 132,
                                child: Center(
                                  child: _AdaptiveQuoteText(quote: quote),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 28,
                          child: Text(
                            '点击任意位置进入',
                            key: ValueKey<String>('startup-continue-hint'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0x7A516985),
                              fontSize: 13,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdaptiveQuoteText extends StatelessWidget {
  const _AdaptiveQuoteText({required this.quote});

  final String quote;

  double _startingSize() {
    final length = quote.runes.length;
    if (length <= 10) return 24;
    if (length <= 24) return 22;
    return 20;
  }

  int _targetLines() {
    final length = quote.runes.length;
    if (length <= 10) return 1;
    if (length <= 24) return 2;
    return 3;
  }

  double _fittedSize(BuildContext context, double maxWidth) {
    final scaler = MediaQuery.textScalerOf(context);
    final targetLines = _targetLines();
    for (var size = _startingSize(); size >= 17.5; size -= .5) {
      final painter = TextPainter(
        text: TextSpan(text: quote, style: _style(size)),
        maxLines: targetLines,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: maxWidth);
      if (!painter.didExceedMaxLines && painter.height <= 132) return size;
    }
    return 17.5;
  }

  TextStyle _style(double size) {
    return TextStyle(
      color: const Color(0xFF284B77),
      fontFamily: 'serif',
      fontFamilyFallback: const ['STSong', 'SimSun'],
      fontSize: size,
      fontWeight: FontWeight.w500,
      height: 1.45,
      letterSpacing: .1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _fittedSize(context, constraints.maxWidth);
        return Text(
          quote,
          key: const ValueKey<String>('startup-quote-text'),
          maxLines: _targetLines(),
          textAlign: TextAlign.center,
          style: _style(size),
        );
      },
    );
  }
}

class _StartupQuoteBackgroundPainter extends CustomPainter {
  const _StartupQuoteBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const base = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFBFDFF), Color(0xFFF4F6FF), Color(0xFFEDF8FF)],
      stops: [0, .55, 1],
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = base.createShader(Offset.zero & size),
    );
    _drawGlow(
      canvas,
      center: Offset(-size.width * .08, size.height * .3),
      radius: size.width * .78,
      color: const Color(0x2AB6A3F2),
    );
    _drawGlow(
      canvas,
      center: Offset(size.width * 1.02, size.height * .72),
      radius: size.width * .82,
      color: const Color(0x2289D4FF),
    );
  }

  void _drawGlow(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = RadialGradient(
      colors: [color, color.withValues(alpha: 0)],
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'models.dart';
import 'launcher_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RPGApp());
}

class RPGApp extends StatelessWidget {
  const RPGApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAME LAUNCHER',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: Colors.black),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  GameEntry? _currentGame;

  @override
  Widget build(BuildContext context) {
    if (_currentGame == null) {
      return LauncherScreen(onLaunch: (game) {
        setState(() => _currentGame = game);
      });
    }
    return GameScreen(
      game: _currentGame!,
      onBack: () => setState(() => _currentGame = null),
    );
  }
}

// ── Game screen ────────────────────────────────────────────────────────────

const double kScaleStep = 0.1;
const double kScaleMin  = 0.3;
const double kScaleMax  = 3.0;

const String _touchSpoof = '''
(function() {
  const _orig = window.matchMedia.bind(window);
  window.matchMedia = function(q) {
    if (q === '(pointer: coarse)')
      return { matches: true, media: q, onchange: null,
               addListener: ()=>{}, removeListener: ()=>{},
               addEventListener: ()=>{}, removeEventListener: ()=>{} };
    return _orig(q);
  };
})();
''';

class GameScreen extends StatefulWidget {
  final GameEntry game;
  final VoidCallback onBack;
  const GameScreen({super.key, required this.game, required this.onBack});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // null  = follow device orientation automatically
  // true  = force landscape
  // false = force portrait
  bool? _overrideLandscape;
  double _scale = 1.0;

  void _zoomIn()    => setState(() => _scale = (_scale + kScaleStep).clamp(kScaleMin, kScaleMax));
  void _zoomOut()   => setState(() => _scale = (_scale - kScaleStep).clamp(kScaleMin, kScaleMax));
  void _zoomReset() => setState(() => _scale = 1.0);

  /// Toggle orientation: cycles auto → force-flip → auto
  void _toggleOrientation(bool deviceLandscape) {
    setState(() {
      if (_overrideLandscape == null) {
        // Start forcing the opposite of current device orientation
        _overrideLandscape = !deviceLandscape;
      } else {
        // Release override — go back to following the device
        _overrideLandscape = null;
      }
    });
  }

  /// Effective landscape flag: override wins, otherwise follow device.
  bool _isLandscape(Orientation deviceOrientation) =>
      _overrideLandscape ?? (deviceOrientation == Orientation.landscape);

  /// WebView size fitted to the available screen area.
  Size _webViewSize(BuildContext context, bool landscape) {
    final mq      = MediaQuery.of(context);
    final screen  = mq.size;
    final padding = mq.padding;
    final isTablet = screen.shortestSide >= 600;

    final availW = screen.width  - padding.left - padding.right  - 56;
    final availH = screen.height - padding.top  - padding.bottom;

    double w, h;
    if (landscape) {
      w = availW > availH ? availW : availH;
      h = availW < availH ? availW : availH;
      if (isTablet) w = w.clamp(0, 1024);
    } else {
      w = availW < availH ? availW : availH;
      h = availW > availH ? availW : availH;
      if (isTablet) w = w.clamp(0, 768);
    }
    return Size(w, h);
  }

  @override
  Widget build(BuildContext context) {
    // OrientationBuilder rebuilds automatically when the device rotates.
    return OrientationBuilder(
      builder: (context, deviceOrientation) {
        final landscape = _isLandscape(deviceOrientation);
        final size = _webViewSize(context, landscape);
        final isOverriding = _overrideLandscape != null;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // ── WebView ───────────────────────────────────────────────
              Center(
                child: Transform.scale(
                  scale: _scale,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: InAppWebView(
                      key: ValueKey('${widget.game.name}-$landscape'),
                      initialData: widget.game.isUrlBased
                          ? null
                          : InAppWebViewInitialData(
                              data: widget.game.htmlContent!,
                              mimeType: 'text/html',
                              encoding: 'utf-8',
                              baseUrl: WebUri('https://cdn.jsdelivr.net'),
                            ),
                      initialUrlRequest: widget.game.isUrlBased
                          ? URLRequest(url: WebUri(widget.game.url!))
                          : null,
                      initialUserScripts: UnmodifiableListView([
                        UserScript(
                          source: _touchSpoof,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      ]),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        transparentBackground: true,
                        userAgent:
                            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
                            'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                            'Version/17.0 Mobile/15E148 Safari/604.1',
                      ),
                    ),
                  ),
                ),
              ),

              // ── Controls (top-right overlay) ──────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ControlButton(
                        icon: Icons.arrow_back, onTap: widget.onBack),
                    const SizedBox(height: 8),
                    // Orientation toggle: highlighted when overriding
                    _ControlButton(
                      icon: landscape
                          ? Icons.stay_current_portrait
                          : Icons.stay_current_landscape,
                      onTap: () => _toggleOrientation(
                          deviceOrientation == Orientation.landscape),
                      // Glow when manually overriding device orientation
                      highlighted: isOverriding,
                    ),
                    const SizedBox(height: 8),
                    _ControlButton(icon: Icons.add, onTap: _zoomIn),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _zoomReset,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Text(
                          '${(_scale * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _ControlButton(icon: Icons.remove, onTap: _zoomOut),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: highlighted ? Colors.cyan.withOpacity(0.3) : Colors.black54,
          borderRadius: BorderRadius.circular(8),
          border: highlighted
              ? Border.all(color: Colors.cyan, width: 1.5)
              : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(icon,
            color: highlighted ? Colors.cyan : Colors.white70, size: 28),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:image/image.dart' as img;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:archive/archive_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.dark);
final ValueNotifier<String> appBackgroundPath = ValueNotifier('');
final ValueNotifier<double> appBackgroundBlur = ValueNotifier(15);
final ValueNotifier<double> appBackgroundParticlesOpacity = ValueNotifier(1.0);
final ValueNotifier<bool> appDialogBlurEnabled = ValueNotifier(true);
final ValueNotifier<bool> appStartupAnimationEnabled = ValueNotifier(true);

const _fallbackAcrylicColor = Color(0x260A0E14);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.clear();
  imageCache.clearLiveImages();

  // Initialize app data directory structure if running from installed location
  await _initializeAppDataDirectory();

  // Check if another instance is already running
  if (!await _acquireInstanceLock()) {
    print('Another instance of ATLAS Backend is already running.');
    exit(1);
  }

  if (Platform.isWindows) {
    await Window.initialize();
    await Window.setEffect(
      effect: WindowEffect.acrylic,
      color: _fallbackAcrylicColor,
    );
    await Window.makeTitlebarTransparent();
    await Window.enableFullSizeContentView();
  }
  runApp(const AtlasApp());
}

ServerSocket? _instanceLockSocket;

Future<bool> _acquireInstanceLock() async {
  try {
    _instanceLockSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      43621,
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _initializeAppDataDirectory() async {
  final atlasDataDir = Directory(getBackendRoot());
  final requiredDirs = [
    atlasDataDir,
    Directory(joinPath([atlasDataDir.path, 'static', 'profiles'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'ClientSettings'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'athenaprofiles'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'shop'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'discovery'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'hotfixes'])),
    Directory(joinPath([atlasDataDir.path, 'static', 'events'])),
    Directory(joinPath([atlasDataDir.path, 'public', 'gameconfig'])),
    Directory(joinPath([atlasDataDir.path, 'public', 'images'])),
    Directory(joinPath([atlasDataDir.path, 'public', 'items'])),
    Directory(joinPath([atlasDataDir.path, 'public', 'playlists'])),
    Directory(joinPath([atlasDataDir.path, 'responses'])),
    Directory(joinPath([atlasDataDir.path, 'exports'])),
    Directory(joinPath([atlasDataDir.path, 'logs'])),
  ];

  for (final dir in requiredDirs) {
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
  }
}

class AtlasApp extends StatefulWidget {
  const AtlasApp({super.key});

  @override
  State<AtlasApp> createState() => _AtlasAppState();
}

class _AtlasAppState extends State<AtlasApp> {
  int _acrylicToken = 0;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    appBackgroundPath.addListener(_scheduleAcrylicUpdate);
  }

  Future<void> _loadTheme() async {
    final config = await ConfigService.load();
    appThemeMode.value = config.useDarkMode ? ThemeMode.dark : ThemeMode.light;
    appBackgroundPath.value = config.backgroundImagePath;
    appBackgroundBlur.value = config.backgroundBlur;
    appBackgroundParticlesOpacity.value = config.backgroundParticlesOpacity;
    appDialogBlurEnabled.value = config.dialogBlurEnabled;
    appStartupAnimationEnabled.value = config.startupAnimationEnabled;
    _scheduleAcrylicUpdate();
  }

  @override
  void dispose() {
    appBackgroundPath.removeListener(_scheduleAcrylicUpdate);
    super.dispose();
  }

  void _scheduleAcrylicUpdate() {
    if (!Platform.isWindows) return;
    final token = ++_acrylicToken;
    _applyAcrylicForBackground(appBackgroundPath.value).then((_) {
      if (!mounted || token != _acrylicToken) return;
    });
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF64D7FF);
    const accentBlue = Color(0xFF1E88E5);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (_, mode, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ATLAS Backend',
        themeMode: mode,
        scrollBehavior: const _AtlasScrollBehavior(),
        theme: ThemeData(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF2F4F7),
          colorScheme: const ColorScheme.light(
            primary: seed,
            secondary: accentBlue,
            surface: Color(0xFFF7F9FC),
            onSurface: Color(0xFF121724),
          ),
          sliderTheme: SliderThemeData(
            activeTrackColor: accentBlue,
            inactiveTrackColor: accentBlue.withOpacity(0.2),
            thumbColor: accentBlue,
            overlayColor: accentBlue.withOpacity(0.2),
            valueIndicatorColor: accentBlue,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue,
              foregroundColor: Colors.white,
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return accentBlue;
              return Colors.grey.shade400;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return accentBlue.withOpacity(0.55);
              }
              return Colors.black.withOpacity(0.2);
            }),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: accentBlue),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(foregroundColor: accentBlue),
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
            headlineMedium: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            bodyLarge: TextStyle(fontSize: 16, height: 1.4),
            bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0E14),
          colorScheme: const ColorScheme.dark(
            primary: seed,
            secondary: accentBlue,
            surface: Color(0xFF101722),
            onSurface: Color(0xFFE9F1FF),
          ),
          sliderTheme: SliderThemeData(
            activeTrackColor: accentBlue,
            inactiveTrackColor: accentBlue.withOpacity(0.25),
            thumbColor: accentBlue,
            overlayColor: accentBlue.withOpacity(0.25),
            valueIndicatorColor: accentBlue,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentBlue,
              foregroundColor: Colors.white,
            ),
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return accentBlue;
              return Colors.white54;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return accentBlue.withOpacity(0.55);
              }
              return Colors.white24;
            }),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: accentBlue),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(foregroundColor: accentBlue),
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
            headlineMedium: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            bodyLarge: TextStyle(fontSize: 16, height: 1.4),
            bodyMedium: TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        home: const AtlasHomePage(),
      ),
    );
  }
}

class _AtlasScrollBehavior extends MaterialScrollBehavior {
  const _AtlasScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const _SmoothScrollPhysics(
      parent: BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

class _SmoothScrollPhysics extends ScrollPhysics {
  const _SmoothScrollPhysics({super.parent, this.multiplier = 0.35});

  final double multiplier;

  @override
  _SmoothScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SmoothScrollPhysics(
      parent: buildParent(ancestor),
      multiplier: multiplier,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset * multiplier);
  }
}

Future<T?> _showBlurDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final baseTheme = Theme.of(dialogContext);
      final dialogTheme = baseTheme.copyWith(
        dialogTheme: DialogThemeData(
          backgroundColor: _dialogSurfaceColor(dialogContext),
          elevation: 0,
          shadowColor: _dialogShadowColor(dialogContext),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: _onSurface(dialogContext, 0.1)),
          ),
          titleTextStyle: baseTheme.textTheme.headlineSmall?.copyWith(
            color: _onSurface(dialogContext, 0.96),
            fontWeight: FontWeight.w700,
          ),
          contentTextStyle: baseTheme.textTheme.bodyMedium?.copyWith(
            color: _onSurface(dialogContext, 0.9),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: baseTheme.colorScheme.secondary,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
      return SafeArea(
        child: Center(
          child: Theme(
            data: dialogTheme,
            child: Builder(builder: (themeContext) => builder(themeContext)),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final blurEnabled = appDialogBlurEnabled.value;
      return Stack(
        children: [
          Positioned.fill(
            child: blurEnabled
                ? BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 3.2 * curved.value,
                      sigmaY: 3.2 * curved.value,
                    ),
                    child: Container(
                      color: _dialogBarrierColor(dialogContext, curved.value),
                    ),
                  )
                : Container(
                    color: _dialogBarrierColor(dialogContext, curved.value),
                  ),
          ),
          FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.975, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}

class AtlasHomePage extends StatefulWidget {
  const AtlasHomePage({super.key});

  @override
  State<AtlasHomePage> createState() => _AtlasHomePageState();
}

class _AtlasHomePageState extends State<AtlasHomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final BackendController _controller;
  bool _exitInProgress = false;
  bool _checkingUpdate = false;
  bool _showingShareDialog = false;
  bool _loadingReleaseHistory = false;
  List<ReleaseInfo> _releaseHistory = const [];
  String _backendVersionLabel = '1.0.0';
  bool _showStartupAnimation = true;
  bool _revealHomeContent = true;
  late final AnimationController _shellEntranceController;
  late final Animation<double> _shellEntranceFade;
  late final Animation<double> _shellEntranceScale;
  late final VoidCallback _startupAnimationListener;
  final Completer<void> _startupAnimationGate = Completer<void>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = BackendController()..startPolling();
    _shellEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _shellEntranceFade = CurvedAnimation(
      parent: _shellEntranceController,
      curve: const Interval(0.0, 0.92, curve: Curves.easeOutCubic),
    );
    _shellEntranceScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _shellEntranceController,
        curve: Curves.easeOutCubic,
      ),
    );
    _showStartupAnimation = appStartupAnimationEnabled.value;
    _revealHomeContent = !_showStartupAnimation;
    if (!_showStartupAnimation) {
      _shellEntranceController.value = 1.0;
      _startupAnimationGate.complete();
    }
    _startupAnimationListener = () {
      if (!mounted) return;
      if (!appStartupAnimationEnabled.value && _showStartupAnimation) {
        setState(() {
          _showStartupAnimation = false;
          _revealHomeContent = true;
        });
        _shellEntranceController.value = 1.0;
        if (!_startupAnimationGate.isCompleted) {
          _startupAnimationGate.complete();
        }
      }
    };
    appStartupAnimationEnabled.addListener(_startupAnimationListener);
    unawaited(_initStartup());
    unawaited(_loadBackendVersion());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _startupAnimationGate.future;
      if (!mounted) return;
      await _maybeCheckForUpdatesOnLaunch();
      if (!mounted) return;
      await _maybeShowUpdateNotesOnLaunch();
      if (!mounted) return;
      await UpdateBackupService.restoreIfNeeded(context);
    });
  }

  void _finishStartupAnimation() {
    if (!mounted || !_showStartupAnimation) return;
    setState(() {
      _showStartupAnimation = false;
      _revealHomeContent = true;
    });
    _shellEntranceController.forward(from: 0);
    if (!_startupAnimationGate.isCompleted) {
      _startupAnimationGate.complete();
    }
  }

  Future<void> _maybeCheckForUpdatesOnLaunch() async {
    final config = await ConfigService.load();
    if (config.disableBackendUpdateCheck) return;
    await _checkForUpdates(silent: true);
  }

  Future<void> _initStartup() async {
    final config = await ConfigService.load();
    if (config.startBackendOnLaunch) {
      await _controller.ensureStoppedOnLaunch();
      await _controller.startBackend();
    } else {
      await _controller.ensureStoppedOnLaunch();
    }
  }

  Future<void> _loadBackendVersion() async {
    final version = await _readBackendVersion();
    if (version.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _backendVersionLabel = version;
    });
  }

  Future<String> _readBackendVersion() async {
    return _readBackendVersionFromCandidates();
  }

  Future<void> _checkForUpdates({required bool silent}) async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    final info = await UpdateService.checkForUpdate();
    _checkingUpdate = false;
    if (!mounted) return;
    if (info == null) {
      if (!silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No updates available.')));
      }
      return;
    }
    await _showUpdateDialog(info);
  }

  Future<void> _maybeShowUpdateNotesOnLaunch() async {
    final currentVersion = await _readBackendVersion();
    if (currentVersion.isEmpty) return;
    final config = await ConfigService.load();
    final normalizedCurrent = _normalizeVersion(currentVersion);
    final normalizedLast = _normalizeVersion(
      config.lastShownUpdateNotesVersion,
    );
    if (normalizedCurrent.isEmpty || normalizedCurrent == normalizedLast) {
      return;
    }

    final notesPayload = await UpdateNotesService.loadNotes();
    if (notesPayload == null) return;
    if (!mounted) return;
    await _showUpdateNotesDialog(
      normalizedCurrent,
      notesPayload.notes,
      notesPayload.style,
    );
    if (!mounted) return;
    await ConfigService.save(
      config.copyWith(lastShownUpdateNotesVersion: normalizedCurrent),
    );
  }

  Future<void> _showUpdateNotesDialog(
    String version,
    String notes,
    UpdateNotesStyle style,
  ) async {
    await _showBlurDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded),
            const SizedBox(width: 10),
            const Text('What\'s New'),
            const Spacer(),
            _VersionTag(
              label: _formatVersion(version),
              color: Colors.greenAccent,
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: MarkdownBody(
                data: notes,
                styleSheet: MarkdownStyleSheet.fromTheme(
                  Theme.of(dialogContext),
                ).copyWith(p: Theme.of(dialogContext).textTheme.bodyMedium),
                blockSyntaxes: _roundedHrBlockSyntaxes,
                inlineSyntaxes: _roundedHrInlineSyntaxes,
                builders: {
                  'rounded-hr': _MarkdownHrBuilder(
                    color: _onSurface(
                      dialogContext,
                      style.hrOpacity.clamp(0.0, 1.0),
                    ),
                    thickness: style.hrThickness <= 0
                        ? UpdateNotesService._defaultStyle.hrThickness
                        : style.hrThickness,
                    verticalPadding: 10,
                  ),
                },
                onTapLink: (text, href, title) async {
                  if (href == null) return;
                  final url = Uri.tryParse(href);
                  if (url == null) return;
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showShareDialog() async {
    if (_showingShareDialog) return;
    _showingShareDialog = true;
    try {
      String vpnIp = 'Detecting...';
      bool isLoading = true;
      bool hasError = false;

      try {
        vpnIp = await VpnService.getVpnIpAddress();
        hasError = vpnIp.startsWith('Error:');
        isLoading = false;
      } catch (e) {
        vpnIp = 'Error: $e';
        hasError = true;
        isLoading = false;
      }

      if (!mounted) return;

      final widget = StatefulBuilder(
        builder: (context, setState) {
          final colorScheme = Theme.of(context).colorScheme;
          final onSurface = colorScheme.onSurface;
          final onSurfaceMuted = onSurface.withOpacity(0.7);
          final cardFill = colorScheme.surfaceVariant.withOpacity(0.6);
          final cardBorder = onSurface.withOpacity(0.18);

          Widget buildStep(int index, List<InlineSpan> spans) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: onSurface.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: onSurface.withOpacity(0.2)),
                    ),
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12.8, color: onSurfaceMuted),
                        children: spans,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            title: const Text('Share Connection Details'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Radmin VPN IP for Reboot Launcher:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cardBorder),
                  ),
                  child: SelectableText(
                    isLoading ? 'Detecting...' : vpnIp,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: onSurface,
                    ),
                  ),
                ),
                if (hasError) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Make sure Radmin VPN is installed and running',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.redAccent.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final url = Uri.parse('https://www.radmin-vpn.com/');
                      final opened = await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Unable to open download link.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Download Radmin VPN'),
                  ),
                ],
                if (!isLoading && !hasError) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.school_rounded,
                              size: 18,
                              color: onSurfaceMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Quick setup in Reboot Launcher for others',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: onSurface.withOpacity(0.92),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        buildStep(1, const [
                          TextSpan(text: 'Open '),
                          TextSpan(
                            text: 'Reboot Launcher',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: '.'),
                        ]),
                        buildStep(2, const [
                          TextSpan(text: 'Go to '),
                          TextSpan(
                            text: 'Backend',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' and switch '),
                          TextSpan(
                            text: 'Embedded',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' to '),
                          TextSpan(
                            text: 'Remote',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: '.'),
                        ]),
                        buildStep(3, const [
                          TextSpan(text: 'Paste the Host IP into the '),
                          TextSpan(
                            text: 'Host',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' field.'),
                        ]),
                        buildStep(4, const [
                          TextSpan(text: 'Click '),
                          TextSpan(
                            text: 'Start Backend',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: '.'),
                        ]),
                        buildStep(5, const [
                          TextSpan(text: 'Confirm you see '),
                          TextSpan(
                            text: '“The backend was started successfully”',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: ' then launch your game!'),
                        ]),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              if (!isLoading && !hasError)
                ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: 'open $vpnIp'));
                    Navigator.pop(context);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('VPN IP copied to clipboard!'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
            ],
          );
        },
      );

      await _showBlurDialog<void>(
        context: context,
        barrierDismissible: !isLoading,
        builder: (_) => widget,
      );
    } finally {
      _showingShareDialog = false;
    }
  }

  Future<void> _showVersionHistoryMenu(BuildContext anchorContext) async {
    if (_loadingReleaseHistory) return;
    setState(() => _loadingReleaseHistory = true);
    final history = await UpdateService.fetchReleaseHistory();
    if (!mounted) return;
    setState(() {
      if (history.isNotEmpty) {
        _releaseHistory = history;
      }
      _loadingReleaseHistory = false;
    });

    final currentVersion = _normalizeVersion(_backendVersionLabel);
    final newerReleases = _releaseHistory
        .where(
          (release) =>
              _compareVersions(
                _normalizeVersion(release.version),
                currentVersion,
              ) >
              0,
        )
        .toList();
    final olderReleases = _releaseHistory
        .where(
          (release) =>
              _compareVersions(
                _normalizeVersion(release.version),
                currentVersion,
              ) <
              0,
        )
        .toList();

    if (newerReleases.isEmpty && olderReleases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other versions available.')),
      );
      return;
    }

    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final box = anchorContext.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + box.size.height,
        box.size.width,
        box.size.height,
      ),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<ReleaseInfo>(
      context: anchorContext,
      position: position,
      color: Theme.of(context).colorScheme.surface.withOpacity(0.98),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _onSurface(context, 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      items: [
        PopupMenuItem<ReleaseInfo>(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          onTap: () {
            unawaited(_showCurrentVersionNotes(anchorContext));
          },
          child: Text(
            'Current: ${_formatVersion(currentVersion)}',
            style: TextStyle(color: _onSurface(context, 0.7)),
          ),
        ),
        if (newerReleases.isNotEmpty) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<ReleaseInfo>(
            enabled: false,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Text(
              'Newer versions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _onSurface(context, 0.6),
              ),
            ),
          ),
          ...newerReleases.map((release) {
            final dateLabel = release.publishedAt == null
                ? null
                : _formatReleaseDate(release.publishedAt!);
            return PopupMenuItem<ReleaseInfo>(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              value: release,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatVersion(release.version),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  if (dateLabel != null)
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.0,
                        color: _onSurface(context, 0.6),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
        if (olderReleases.isNotEmpty) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<ReleaseInfo>(
            enabled: false,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Text(
              'Older versions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _onSurface(context, 0.6),
              ),
            ),
          ),
          ...olderReleases.map((release) {
            final dateLabel = release.publishedAt == null
                ? null
                : _formatReleaseDate(release.publishedAt!);
            return PopupMenuItem<ReleaseInfo>(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              value: release,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatVersion(release.version),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  if (dateLabel != null)
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.0,
                        color: _onSurface(context, 0.6),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ],
    );

    if (selected == null) return;
    final selectedVersion = _normalizeVersion(selected.version);
    final isUpgrade = _compareVersions(selectedVersion, currentVersion) > 0;

    final info = UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: selectedVersion,
      downloadUrl: selected.downloadUrl,
      isInstaller: true,
      notes: selected.notes,
      currentCommit: null,
      latestCommit: null,
    );
    await _showUpdateDialog(
      info,
      title: isUpgrade ? 'Update available' : 'Downgrade available',
      actionLabel: isUpgrade ? 'Update' : 'Downgrade',
    );
  }

  Future<void> _showCurrentVersionNotes(BuildContext _) async {
    final currentVersion = await _readBackendVersion();
    if (currentVersion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Current version unavailable.')),
      );
      return;
    }

    final notesPayload = await UpdateNotesService.loadNotes();
    if (!mounted) return;
    if (notesPayload == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No update notes found.')));
      return;
    }

    await _showUpdateNotesDialog(
      _normalizeVersion(currentVersion),
      notesPayload.notes,
      notesPayload.style,
    );
  }

  Future<void> _showUpdateDialog(
    UpdateInfo info, {
    String title = 'An update is available',
    String actionLabel = 'Update now',
  }) async {
    final progress = ValueNotifier<double>(0);
    bool updating = false;
    String? error;
    Future<void> restartApp() async {
      final exePath = Platform.resolvedExecutable;
      if (exePath.isNotEmpty) {
        try {
          await Process.start(
            exePath,
            const [],
            mode: ProcessStartMode.detached,
          );
        } catch (_) {}
      }
      exit(0);
    }

    await _showBlurDialog<void>(
      context: context,
      barrierDismissible: !updating,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final tagRow = Row(
            children: [
              _VersionTag(label: info.currentLabel, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('—', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              _VersionTag(label: info.latestLabel, color: Colors.greenAccent),
            ],
          );
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tagRow,
                  const SizedBox(height: 12),
                  if (info.notes != null && info.notes!.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: SingleChildScrollView(
                        child: MarkdownBody(
                          data: info.notes!,
                          styleSheet: MarkdownStyleSheet.fromTheme(
                            Theme.of(context),
                          ).copyWith(p: Theme.of(context).textTheme.bodySmall),
                          blockSyntaxes: _roundedHrBlockSyntaxes,
                          inlineSyntaxes: _roundedHrInlineSyntaxes,
                          builders: {
                            'rounded-hr': _MarkdownHrBuilder(
                              color: _onSurface(context, 0.18),
                              thickness: 0.6,
                              verticalPadding: 8,
                            ),
                          },
                        ),
                      ),
                    ),
                  if (updating) ...[
                    const SizedBox(height: 16),
                    ValueListenableBuilder<double>(
                      valueListenable: progress,
                      builder: (context, value, _) {
                        final pct = (value.clamp(0.0, 1.0) * 100)
                            .toStringAsFixed(0);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value: value > 0 && value < 1 ? value : null,
                            ),
                            const SizedBox(height: 6),
                            Text('Downloading... $pct%'),
                          ],
                        );
                      },
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              _HoverScale(
                child: TextButton(
                  onPressed: updating ? null : () => Navigator.pop(context),
                  child: const Text('Later'),
                ),
              ),
              _HoverScale(
                child: ElevatedButton(
                  onPressed: updating
                      ? null
                      : () async {
                          setState(() {
                            updating = true;
                            error = null;
                          });
                          try {
                            await _controller.stopBackend();
                            await UpdateBackupService.backupBeforeUpdate();
                            await UpdateService.downloadAndApply(
                              info,
                              progress,
                            );
                            if (!mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Updated to ${info.latestLabel}. Restarting...',
                                ),
                              ),
                            );
                            await Future<void>.delayed(
                              const Duration(milliseconds: 600),
                            );
                            await restartApp();
                          } catch (err) {
                            setState(() {
                              error = 'Update failed: $err';
                              updating = false;
                            });
                          } finally {
                            progress.value = 0;
                          }
                        },
                  child: Text(updating ? 'Updating...' : actionLabel),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appStartupAnimationEnabled.removeListener(_startupAnimationListener);
    _shellEntranceController.dispose();
    unawaited(_controller.stopBackend());
    unawaited(_controller.forceKillBackendPort());
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    if (_exitInProgress) return false;
    _exitInProgress = true;
    final confirm = await DataService._confirmDialog(
      context,
      'Close the backend before exiting?',
    );
    if (confirm) {
      await _controller.stopBackend();
      await _controller.forceKillBackendPort();
    }
    _exitInProgress = false;
    return confirm;
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!mounted) return AppExitResponse.exit;
    if (_exitInProgress) return AppExitResponse.cancel;

    // Cancel the platform close request first, then show the confirmation dialog
    // on the next event-loop tick so the dialog transition can animate smoothly.
    Future<void>(() async {
      if (!mounted) return;
      final confirm = await _confirmExit();
      if (confirm) {
        exit(0);
      }
    });

    return AppExitResponse.cancel;
  }

  static const List<MenuItemData> _menuItems = [
    MenuItemData(
      title: 'Modifications',
      subtitle: 'Manage Straight Bloom, CurveTables and DataTables',
      icon: Icons.tune,
      accent: Color(0xFF6BE7FF),
      actions: [
        MenuAction(
          title: 'Toggle Straight Bloom',
          description: 'Enable or disable straight bloom.',
        ),
        MenuAction(
          title: 'Toggle CurveTables',
          description: 'Enable or disable all CurveTables.',
        ),
        MenuAction(
          title: 'CurveTable Settings',
          description: 'Manage individual tables.',
        ),
      ],
    ),
    MenuItemData(
      title: 'Arena',
      subtitle: 'Leaderboard and other arena settings',
      icon: Icons.emoji_events,
      accent: Color(0xFFFF6A8C),
      enabled: true,
      actions: [
        MenuAction(
          title: 'Arena Leaderboard',
          description: 'View top profiles.',
        ),
        MenuAction(
          title: 'Save Arena Points',
          description: 'Toggle saving points.',
        ),
      ],
    ),
    MenuItemData(
      title: 'Game Configuration',
      subtitle: 'Manage In Game Events and Stages',
      icon: Icons.settings_suggest,
      accent: Color(0xFF5BF2B3),
      actions: [
        MenuAction(title: 'Rufus Week Stage', description: 'Set 1-4.'),
        MenuAction(title: 'Water Level', description: 'Set 1-8.'),
        MenuAction(title: 'Water Storm', description: 'Toggle storm events.'),
      ],
    ),
    MenuItemData(
      title: 'Users',
      subtitle: 'Manage users, profiles, and client settings',
      icon: Icons.people_alt_rounded,
      accent: Color(0xFF7EE081),
      actions: [
        MenuAction(title: 'View Users', description: 'See all local users.'),
        MenuAction(
          title: 'Apply Preset',
          description: 'Replace a user with a preset.',
        ),
        MenuAction(
          title: 'Edit User Values',
          description: 'Modify level, V-Bucks, and other attributes.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final showIntro = _showStartupAnimation;
    final content = Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => _TopBar(
              textTheme: textTheme,
              statusText: _controller.statusText,
              statusColor: _controller.statusColor,
              versionLabel: _backendVersionLabel,
              onVersionPressed: _showVersionHistoryMenu,
              onSettingsPressed: () => Navigator.of(
                context,
              ).push(_buildRoute(const SettingsScreen())),
              onCheckUpdates: () => _checkForUpdates(silent: false),
              onShowShareDialog: _showShareDialog,
              height: 110,
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: RepaintBoundary(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _MenuGrid(items: _menuItems)),
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 2,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, __) => _SidePanel(controller: _controller),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return WillPopScope(
      onWillPop: () async => _confirmExit(),
      child: Scaffold(
        body: Stack(
          children: [
            AtlasBackground(showParticles: !showIntro),
            if (_revealHomeContent)
              Positioned.fill(
                child: FadeTransition(
                  opacity: _shellEntranceFade,
                  child: ScaleTransition(
                    scale: _shellEntranceScale,
                    child: IgnorePointer(
                      ignoring: showIntro,
                      child: content,
                    ),
                  ),
                ),
              ),
            if (showIntro)
              _AtlasStartupAnimationOverlay(
                onFinished: _finishStartupAnimation,
              ),
          ],
        ),
      ),
    );
  }
}

class _AtlasStartupAnimationOverlay extends StatefulWidget {
  const _AtlasStartupAnimationOverlay({required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<_AtlasStartupAnimationOverlay> createState() =>
      _AtlasStartupAnimationOverlayState();
}

class _AtlasStartupAnimationOverlayState
    extends State<_AtlasStartupAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _overlayOpacity;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoOffsetY;
  late final Animation<double> _textOpacity;
  late final Animation<double> _textOffsetY;
  late final Animation<double> _textBlur;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _overlayOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 90),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 10,
      ),
    ]).animate(_controller);

    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.05, 0.35, curve: Curves.easeOutCubic),
    );

    _logoOffsetY = Tween<double>(begin: -140.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.35, 0.6, curve: Curves.easeOut),
    );

    _textOffsetY = Tween<double>(begin: 48.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        // Use a non-overshooting curve so the startup text doesn't "bounce".
        curve: const Interval(0.35, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _textBlur = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDarkTheme(context);
    final startupLogoFigureless = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Logo-Figureless.png',
      ]),
    );
    final startupLogoDefault = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Logo.png',
      ]),
    );
    final textStyle = TextStyle(
      fontSize: 54,
      height: 1.0,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: dark ? Colors.white.withOpacity(0.95) : _onSurface(context, 0.96),
      fontFamily: 'Coolvetica',
      fontFamilyFallback: const ['Segoe UI', 'Arial', 'Roboto'],
      shadows: [
        Shadow(
          color: dark
              ? Colors.black.withOpacity(0.45)
              : Colors.black.withOpacity(0.14),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );

    return Positioned.fill(
      child: AbsorbPointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Opacity(
                opacity: _overlayOpacity.value,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _adaptiveScrimColor(
                                context,
                                darkAlpha: 0.22,
                                lightAlpha: 0.08,
                              ),
                              _adaptiveScrimColor(
                                context,
                                darkAlpha: 0.34,
                                lightAlpha: 0.12,
                              ),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.translate(
                            offset: Offset(0, _logoOffsetY.value),
                            child: Opacity(
                              opacity: _logoOpacity.value,
                              child: startupLogoFigureless.existsSync()
                                  ? Image.file(
                                      startupLogoFigureless,
                                      width: 180,
                                      height: 180,
                                      fit: BoxFit.contain,
                                    )
                                  : startupLogoDefault.existsSync()
                                      ? Image.file(
                                          startupLogoDefault,
                                          width: 180,
                                          height: 180,
                                          fit: BoxFit.contain,
                                        )
                                      : Image.asset(
                                          'assets/images/atlas_logo.png',
                                          width: 180,
                                          height: 180,
                                          fit: BoxFit.contain,
                                        ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Transform.translate(
                            offset: Offset(0, _textOffsetY.value),
                            child: Opacity(
                              opacity: _textOpacity.value,
                              child: ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: _textBlur.value,
                                  sigmaY: _textBlur.value,
                                ),
                                child: Text(
                                  'Launching ATLAS Backend',
                                  textAlign: TextAlign.center,
                                  style: textStyle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.textTheme,
    required this.statusText,
    required this.statusColor,
    required this.versionLabel,
    required this.onVersionPressed,
    required this.onSettingsPressed,
    required this.onCheckUpdates,
    required this.onShowShareDialog,
    required this.height,
  });

  final TextTheme textTheme;
  final String statusText;
  final Color statusColor;
  final String versionLabel;
  final void Function(BuildContext context)? onVersionPressed;
  final VoidCallback onSettingsPressed;
  final VoidCallback? onCheckUpdates;
  final VoidCallback onShowShareDialog;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bannerFigureless = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Banner-Transparent-Figureless.png',
      ]),
    );
    final bannerDefault = File(
      joinPath([
        getInstallationRoot(),
        'public',
        'images',
        'ATLAS-Backend-Banner-Transparent.png',
      ]),
    );
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
            GestureDetector(
              onTap: () => _showAboutDialog(context, versionLabel: versionLabel),
              child: bannerFigureless.existsSync()
                  ? Image.file(
                      bannerFigureless,
                      height: 100,
                      fit: BoxFit.contain,
                    )
                  : bannerDefault.existsSync()
                      ? Image.file(
                          bannerDefault,
                          height: 100,
                          fit: BoxFit.contain,
                        )
                      : Row(
                      children: [
                        Image.asset(
                          'assets/images/atlas_logo.png',
                          width: 100,
                        height: 100,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ATLAS Backend',
                            style: textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Backend control center',
                            style: textTheme.bodyMedium?.copyWith(
                              color: _onSurface(context, 0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const Spacer(),
          SizedBox(
            width: 40,
            child: _HoverScale(
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onShowShareDialog,
                icon: const Icon(Icons.share_rounded),
                tooltip: 'Share VPN Connection',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: _HoverScale(
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onSettingsPressed,
                icon: const Icon(Icons.settings_rounded),
                tooltip: 'Settings',
              ),
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(label: 'Backend', value: statusText, color: statusColor),
          const SizedBox(width: 16),
          Builder(
            builder: (pillContext) => _HoverScale(
              enabled: onVersionPressed != null,
              child: GestureDetector(
                onTap: onVersionPressed == null
                    ? null
                    : () => onVersionPressed!(pillContext),
                child: _StatusPill(
                  label: 'Version',
                  value: versionLabel,
                  color: _onSurface(context, 0.24),
                  trailing: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: _onSurface(context, 0.6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: _HoverScale(
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Check for updates',
                onPressed: onCheckUpdates,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
  });

  final String label;
  final String value;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7)),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      ),
    );
  }
}

class _VersionTag extends StatelessWidget {
  const _VersionTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.items});

  final List<MenuItemData> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.6,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return MenuCard(
          data: item,
          onTap: item.enabled
              ? () {
                  Navigator.of(
                    context,
                  ).push(_buildRoute(_pageForMenu(item.title)));
                }
              : null,
        );
      },
    );
  }
}

class MenuCard extends StatefulWidget {
  const MenuCard({super.key, required this.data, required this.onTap});

  final MenuItemData data;
  final VoidCallback? onTap;

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.data.accent;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = widget.data.enabled && widget.onTap != null;
    return MouseRegion(
      onEnter: isEnabled ? (_) => setState(() => _hovered = true) : null,
      onExit: isEnabled ? (_) => setState(() => _hovered = false) : null,
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: _hovered && isEnabled ? 1.02 : 1,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isEnabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    accent.withOpacity(isDark ? 0.22 : 0.32),
                    isDark ? const Color(0xFF141B26) : const Color(0xFFF2F5FB),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: _hovered && isEnabled
                      ? accent.withOpacity(0.8)
                      : _onSurface(context, 0.12),
                  width: 1.2,
                ),
                boxShadow: [
                  if (isDark)
                    BoxShadow(
                      color: _menuShadowColor(context, accent),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    )
                  else ...[
                    BoxShadow(
                      color: _menuShadowColor(context, accent),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(widget.data.icon, color: accent, size: 26),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: _onSurface(context, 0.7),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.data.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.data.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _onSurface(context, 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller});

  final BackendController controller;
  static final ScrollController _logsController = ScrollController();
  static int _lastLogCount = 0;

  @override
  Widget build(BuildContext context) {
    final logCount = controller.recentLogs.length;
    if (logCount != _lastLogCount) {
      _lastLogCount = logCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logsController.hasClients) {
          _logsController.animateTo(
            _logsController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _ActionButton(
              label: controller.isStarting ? 'Starting...' : 'Start Backend',
              icon: Icons.play_arrow_rounded,
              color: const Color(0xFF5BE0B3),
              onPressed:
                  (controller.isRunning ||
                      controller.isStarting ||
                      controller.isStopping ||
                      controller.isRestarting ||
                      controller.hasProcess)
                  ? null
                  : controller.startBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: controller.isRestarting
                  ? 'Restarting...'
                  : 'Restart Backend',
              icon: Icons.refresh_rounded,
              color: const Color(0xFF7CC0FF),
              onPressed:
                  (!controller.isRunning ||
                      controller.isStarting ||
                      controller.isStopping ||
                      controller.isRestarting)
                  ? null
                  : controller.restartBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: controller.isStopping ? 'Stopping...' : 'Stop Backend',
              icon: Icons.stop_circle_outlined,
              color: const Color(0xFFFF6A8C),
              onPressed:
                  (controller.isStopping ||
                      controller.isRestarting ||
                      (!controller.isRunning && !controller.hasProcess))
                  ? null
                  : controller.stopBackend,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Close Fortnite',
              icon: Icons.sports_esports,
              color: const Color(0xFFFFB86B),
              onPressed: Platform.isWindows ? controller.closeFortnite : null,
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Open Logs',
              icon: Icons.receipt_long,
              color: const Color(0xFF7CC0FF),
              onPressed: () =>
                  Navigator.of(context).push(_buildRoute(const LogsScreen())),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Live Logs',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    _LiveLogsRuntimeTimer(controller: controller),
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: controller.recentLogs.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(
                            ClipboardData(
                              text: controller.recentLogs.join('\n'),
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Live logs copied to clipboard'),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: SingleChildScrollView(
                  controller: _logsController,
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      controller.recentLogs.join('\n'),
                      textAlign: TextAlign.left,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _onSurface(context, 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveLogsRuntimeTimer extends StatefulWidget {
  const _LiveLogsRuntimeTimer({required this.controller});

  final BackendController controller;

  @override
  State<_LiveLogsRuntimeTimer> createState() => _LiveLogsRuntimeTimerState();
}

class _LiveLogsRuntimeTimerState extends State<_LiveLogsRuntimeTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Keep the update scoped to this small widget instead of rebuilding
    // the whole UI every second.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = widget.controller.backendStartedAt;
    final show = startedAt != null;
    final elapsed = show ? DateTime.now().difference(startedAt) : Duration.zero;
    final text = show ? _formatElapsed(elapsed) : '';

    final label = Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: _onSurface(context, 0.35),
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0.2,
      ),
    );

    if (!show) return label; // Keeps a baseline for Row alignment.

    return Padding(padding: const EdgeInsets.only(left: 10), child: label);
  }

  String _formatElapsed(Duration elapsed) {
    var totalSeconds = elapsed.inSeconds;
    if (totalSeconds < 0) totalSeconds = 0;

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = onPressed != null;
    final fgColor = isDark ? color : _darken(color, 0.38);
    return _HoverScale(
      enabled: isEnabled,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled
              ? color.withOpacity(isDark ? 0.28 : 0.35)
              : _onSurface(context, isDark ? 0.14 : 0.06),
          foregroundColor: isEnabled ? fgColor : _onSurface(context, 0.35),
          disabledBackgroundColor: _onSurface(context, isDark ? 0.14 : 0.06),
          disabledForegroundColor: _onSurface(context, 0.35),
          elevation: isDark ? 0 : 1.5,
          shadowColor: color.withOpacity(isDark ? 0.0 : 0.35),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isEnabled
                  ? fgColor.withOpacity(isDark ? 0.4 : 0.55)
                  : _onSurface(context, isDark ? 0.18 : 0.12),
            ),
          ),
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: _onSurface(context, 0.7)),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class FeatureScreen extends StatelessWidget {
  const FeatureScreen({super.key, required this.data});

  final MenuItemData data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
            const AtlasBackground(showParticles: false),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HoverScale(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: data.accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(data.icon, color: data.accent),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          data.subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: _onSurface(context, 0.7)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Actions',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ListView.separated(
                              itemCount: data.actions.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final action = data.actions[index];
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  tileColor: Colors.white10,
                                  leading: Icon(
                                    Icons.chevron_right_rounded,
                                    color: data.accent,
                                  ),
                                  title: Text(action.title),
                                  subtitle: Text(action.description),
                                  trailing: _HoverScale(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${action.title} (coming soon)',
                                            ),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: data.accent
                                            .withOpacity(0.15),
                                        foregroundColor: data.accent,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Open'),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _onSurface(context, 0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class AtlasBackground extends StatelessWidget {
  const AtlasBackground({super.key, this.showParticles = true});

  final bool showParticles;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final imagePath = joinPath([
      getBackendRoot(),
      'public',
      'images',
      'DefaultBackground.webp',
    ]);
    final imageFile = File(imagePath);
    return Stack(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([appBackgroundPath, appBackgroundBlur]),
          builder: (context, _) {
            final path = appBackgroundPath.value;
            final blurSigma = appBackgroundBlur.value;
            File? customBackground;
            final resolvedPath = _resolveBackgroundPath(path);
            if (resolvedPath != null) {
              customBackground = File(resolvedPath);
            }
            if (customBackground != null) {
              return Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: Image.file(
                    customBackground,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              );
            }
            if (imageFile.existsSync()) {
              return Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              );
            }
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0A0E14), Color(0xFF0F1726)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            );
          },
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      Colors.black.withOpacity(0.65),
                      Colors.black.withOpacity(0.35),
                    ]
                  : [
                      Colors.white.withOpacity(0.55),
                      Colors.white.withOpacity(0.2),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        ValueListenableBuilder<double>(
          valueListenable: appBackgroundParticlesOpacity,
          builder: (context, opacity, _) {
            if (!showParticles) {
              return const SizedBox.shrink();
            }
            final clamped = opacity.clamp(0.0, 2.0).toDouble();
            if (clamped <= 0.0) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: IgnorePointer(
                child: TickerMode(
                  enabled: routeIsCurrent,
                  child: _AtlasParticleField(opacity: clamped),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AtlasParticleField extends StatefulWidget {
  const _AtlasParticleField({super.key, required this.opacity});

  final double opacity;

  @override
  State<_AtlasParticleField> createState() => _AtlasParticleFieldState();
}

class _AtlasParticleFieldState extends State<_AtlasParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_AtlasParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
    _particles = _AtlasParticle.generate(seed: 90210, count: 120);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final opacity = widget.opacity.clamp(0.0, 2.0).toDouble();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AtlasParticlePainter(
          controller: _controller,
          particles: _particles,
          color: isDark ? Colors.white : Colors.black,
          opacity: opacity,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AtlasParticle {
  const _AtlasParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.alpha,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.glow,
  });

  final double x;
  final double y;
  final double vx;
  final double vy;
  final double radius;
  final double alpha;
  final double twinkleSpeed;
  final double twinklePhase;
  final bool glow;

  static List<_AtlasParticle> generate({required int seed, required int count}) {
    final rng = Random(seed);

    double nextDoubleRange(double min, double max) =>
        min + (max - min) * rng.nextDouble();

    final particles = <_AtlasParticle>[];
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble();
      final y = rng.nextDouble();

      final sizeRoll = rng.nextDouble();
      final radius =
          sizeRoll < 0.12 ? nextDoubleRange(1.8, 2.8) : nextDoubleRange(0.8, 1.8);
      final baseAlpha =
          sizeRoll < 0.12 ? nextDoubleRange(0.08, 0.16) : nextDoubleRange(0.04, 0.12);

      final speed = nextDoubleRange(0.002, 0.012) * (radius / 2.0);
      final angle = nextDoubleRange(0, pi * 2);
      final vx = cos(angle) * speed;
      final vy = sin(angle) * speed;

      final twinkleSpeed = nextDoubleRange(0.6, 1.6);
      final twinklePhase = nextDoubleRange(0, pi * 2);

      particles.add(
        _AtlasParticle(
          x: x,
          y: y,
          vx: vx,
          vy: vy,
          radius: radius,
          alpha: baseAlpha,
          twinkleSpeed: twinkleSpeed,
          twinklePhase: twinklePhase,
          glow: sizeRoll < 0.08,
        ),
      );
    }
    return particles;
  }
}

class _AtlasParticlePainter extends CustomPainter {
  _AtlasParticlePainter({
    required this.controller,
    required this.particles,
    required this.color,
    required this.opacity,
  }) : super(repaint: controller);

  final AnimationController controller;
  final List<_AtlasParticle> particles;
  final Color color;
  final double opacity;

  final Paint _paint = Paint()..isAntiAlias = true;
  final Paint _glowPaint = Paint()
    ..isAntiAlias = true
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);

  @override
  void paint(Canvas canvas, Size size) {
    final t = (controller.lastElapsedDuration?.inMilliseconds ?? 0) / 1000.0;

    for (final p in particles) {
      final px = ((p.x + p.vx * t) % 1.0) * size.width;
      final py = ((p.y + p.vy * t) % 1.0) * size.height;
      final twinkle = 0.65 + 0.35 * sin(p.twinklePhase + t * p.twinkleSpeed);
      final a = (p.alpha * twinkle * opacity).clamp(0.0, 1.0);

      if (p.glow) {
        _glowPaint.color = color.withOpacity(a * 0.6);
        canvas.drawCircle(Offset(px, py), p.radius + 1.4, _glowPaint);
      }

      _paint.color = color.withOpacity(a);
      canvas.drawCircle(Offset(px, py), p.radius, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AtlasParticlePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.opacity != opacity ||
        oldDelegate.particles != particles;
  }
}

class _HoverScale extends StatefulWidget {
  const _HoverScale({
    required this.child,
    this.enabled = true,
    this.scale = 1.05,
    this.duration = const Duration(milliseconds: 200),
  });

  final Widget child;
  final bool enabled;
  final double scale;
  final Duration duration;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverRegion extends StatefulWidget {
  const _HoverRegion({required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<_HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}

class _ImageDropShadow extends StatelessWidget {
  const _ImageDropShadow({
    required this.child,
    this.opacity = 0.75,
    this.blurSigma = 2.5,
    this.offset = const Offset(0, 2),
  });

  final Widget child;
  final double opacity;
  final double blurSigma;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: offset,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(opacity),
                BlendMode.srcIn,
              ),
              child: child,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _HoverShadow extends StatefulWidget {
  const _HoverShadow({
    required this.child,
    this.opacity = 0.75,
    this.blurSigma = 2.5,
    this.baseOffset = const Offset(0, 2),
    this.hoverOffset = const Offset(4, 2),
    this.duration = const Duration(milliseconds: 200),
    this.hovered,
  });

  final Widget child;
  final double opacity;
  final double blurSigma;
  final Offset baseOffset;
  final Offset hoverOffset;
  final Duration duration;
  final bool? hovered;

  @override
  State<_HoverShadow> createState() => _HoverShadowState();
}

class _HoverShadowState extends State<_HoverShadow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveHovered = widget.hovered ?? _hovered;
    final content = TweenAnimationBuilder<Offset>(
      tween: Tween<Offset>(
        begin: widget.baseOffset,
        end: effectiveHovered ? widget.hoverOffset : widget.baseOffset,
      ),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, offset, child) {
        return _ImageDropShadow(
          opacity: widget.opacity,
          blurSigma: widget.blurSigma,
          offset: offset,
          child: child!,
        );
      },
      child: widget.child,
    );
    if (widget.hovered != null) {
      return content;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: content,
    );
  }
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? widget.scale : 1,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

Color _onSurface(BuildContext context, double opacity) {
  return Theme.of(context).colorScheme.onSurface.withOpacity(opacity);
}

bool _isDarkTheme(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark;
}

Color _dialogSurfaceColor(BuildContext context) {
  final dark = _isDarkTheme(context);
  if (dark) {
    return const Color(0xFF081225).withOpacity(0.96);
  }
  return const Color(0xFFF6FAFF).withOpacity(0.96);
}

Color _dialogShadowColor(BuildContext context) {
  final dark = _isDarkTheme(context);
  return Colors.black.withOpacity(dark ? 0.40 : 0.18);
}

Color _dialogBarrierColor(BuildContext context, double transitionValue) {
  final dark = _isDarkTheme(context);
  final base = dark ? Colors.black : Colors.white;
  final alpha = (dark ? 0.34 : 0.22) * transitionValue;
  return base.withOpacity(alpha);
}

Color _adaptiveScrimColor(
  BuildContext context, {
  required double darkAlpha,
  required double lightAlpha,
}) {
  final dark = _isDarkTheme(context);
  final base = dark ? Colors.black : Colors.white;
  return base.withOpacity(dark ? darkAlpha : lightAlpha);
}

Future<void> _applyAcrylicForBackground(String path) async {
  if (!Platform.isWindows) return;
  final color = await _computeAcrylicTint(path);
  await Window.setEffect(effect: WindowEffect.acrylic, color: color);
}

Future<Color> _computeAcrylicTint(String path) async {
  final resolved = _resolveBackgroundPath(path);
  final fallbackPath = joinPath([
    getBackendRoot(),
    'public',
    'images',
    'DefaultBackground.webp',
  ]);
  final candidatePath = resolved ?? fallbackPath;
  try {
    final file = File(candidatePath);
    if (!await file.exists()) return _fallbackAcrylicColor;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return _fallbackAcrylicColor;
    final width = decoded.width;
    final height = decoded.height;
    if (width == 0 || height == 0) return _fallbackAcrylicColor;
    final stepX = max(1, (width / 60).floor());
    final stepY = max(1, (height / 60).floor());
    var r = 0;
    var g = 0;
    var b = 0;
    var count = 0;
    for (var y = 0; y < height; y += stepY) {
      for (var x = 0; x < width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final a = pixel.a;
        if (a < 20) continue;
        r += pixel.r.toInt();
        g += pixel.g.toInt();
        b += pixel.b.toInt();
        count++;
      }
    }
    if (count == 0) return _fallbackAcrylicColor;
    final avg = Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
    final base = const Color(0xFF0A0E14);
    final mixed = _mixColors(base, avg, 0.55);
    return mixed.withAlpha(_fallbackAcrylicColor.alpha);
  } catch (_) {
    return _fallbackAcrylicColor;
  }
}

Color _mixColors(Color a, Color b, double t) {
  final clamped = t.clamp(0.0, 1.0);
  final r = (a.red + (b.red - a.red) * clamped).round();
  final g = (a.green + (b.green - a.green) * clamped).round();
  final bVal = (a.blue + (b.blue - a.blue) * clamped).round();
  return Color.fromARGB(255, r, g, bVal);
}

Color _menuShadowColor(BuildContext context, Color accent) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return accent.withOpacity(isDark ? 0.25 : 0.18);
}

Color _darken(Color color, double amount) {
  final hsl = HSLColor.fromColor(color);
  final lightness = (hsl.lightness - amount).clamp(0.0, 1.0);
  return hsl.withLightness(lightness).toColor();
}

Future<void> _showAboutDialog(
  BuildContext context, {
  required String versionLabel,
}) async {
  const supportUrl = 'https://discord.gg/GqgakxU6bm';
  const githubUrl = 'https://github.com/cipherfps/ATLAS-Backend';
  final formattedVersion = _formatVersion(versionLabel);
  await _showBlurDialog<void>(
    context: context,
    builder: (dialogContext) {
      final secondary = Theme.of(dialogContext).colorScheme.secondary;

      Widget linkRow({
        required String label,
        required String url,
      }) {
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            Text(
              '$label:',
              style: TextStyle(
                color: _onSurface(dialogContext, 0.86),
                fontWeight: FontWeight.w600,
              ),
            ),
            InkWell(
              onTap: () => _openUrl(url),
              borderRadius: BorderRadius.circular(6),
              child: Text(
                _stripScheme(url),
                style: TextStyle(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: secondary,
                ),
              ),
            ),
          ],
        );
      }

      return Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            decoration: BoxDecoration(
              color: _dialogSurfaceColor(dialogContext),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _onSurface(dialogContext, 0.1)),
              boxShadow: [
                BoxShadow(
                  color: _dialogShadowColor(dialogContext),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _adaptiveScrimColor(
                                dialogContext,
                                darkAlpha: 0.24,
                                lightAlpha: 0.14,
                              ),
                              border: Border.all(
                                color: _onSurface(dialogContext, 0.12),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Image.asset(
                                'assets/images/atlas_logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'About',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: _onSurface(dialogContext, 0.96),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: secondary.withOpacity(0.2),
                              border: Border.all(
                                color: secondary.withOpacity(0.55),
                              ),
                            ),
                            child: Text(
                              formattedVersion,
                              style: TextStyle(
                                color: _onSurface(dialogContext, 0.96),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Made by cipher',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _onSurface(dialogContext, 0.96),
                        ),
                      ),
                      const SizedBox(height: 8),
                      linkRow(label: 'GitHub', url: githubUrl),
                      const SizedBox(height: 6),
                      linkRow(label: 'Support', url: supportUrl),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _HoverScale(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Close'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _showCustomCosmeticPresetsInfoDialog(BuildContext context) async {
  const discordUrl = 'https://discord.gg/GqgakxU6bm';
  await _showBlurDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.palette_rounded, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 10),
          const Text('Custom Cosmetic Presets'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Builder(
          builder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            final onSurface = colorScheme.onSurface;
            final onSurfaceMuted = onSurface.withOpacity(0.75);
            final accent = colorScheme.secondary;
            final cardFill = colorScheme.surfaceVariant.withOpacity(0.6);
            final cardBorder = onSurface.withOpacity(0.18);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withOpacity(0.28)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Custom Cosmetic Presets require additional pak files. '
                          'You can download the required paks from the Discord server.',
                          style: TextStyle(color: onSurfaceMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.forum_rounded,
                        size: 18,
                        color: onSurfaceMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Discord server',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: onSurface.withOpacity(0.92),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              discordUrl,
                              style: TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 12.8,
                                fontWeight: FontWeight.w500,
                                color: onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _HoverScale(
                        child: IconButton(
                          tooltip: 'Open Discord',
                          onPressed: () => _openUrl(discordUrl),
                          icon: const Icon(Icons.open_in_new_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        _HoverScale(
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: discordUrl));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Discord link copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy link'),
          ),
        ),
        _HoverScale(
          child: ElevatedButton.icon(
            onPressed: () => _openUrl(discordUrl),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open Discord'),
          ),
        ),
        _HoverScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ),
      ],
    ),
  );
}

Future<void> _openUrl(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    }
  } catch (_) {}
}

PageRouteBuilder<void> _buildRoute(Widget page) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (context, animation, __, child) {
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        return child;
      }
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final slide = Tween<Offset>(
        begin: Offset.zero,
        end: Offset.zero,
      ).animate(curve);
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

class MenuItemData {
  const MenuItemData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.actions,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<MenuAction> actions;
  final bool enabled;
}

class MenuAction {
  const MenuAction({required this.title, required this.description});

  final String title;
  final String description;
}

Widget _pageForMenu(String title) {
  switch (title) {
    case 'Modifications':
      return const ModificationsScreen();
    case 'CurveTables':
      return const CurveTablesScreen();
    case 'Arena':
      return const ArenaScreen();
    case 'Game Configuration':
      return const GameConfigurationScreen();
    case 'Users':
      return const ProfilesScreen();
    case 'Edit User Values':
      return const UserValuesScreen();
    case 'Logs':
      return const LogsScreen();
    default:
      return FeatureScreen(
        data: MenuItemData(
          title: title,
          subtitle: 'Coming soon',
          icon: Icons.dashboard_customize,
          accent: const Color(0xFF6BE7FF),
          actions: const [
            MenuAction(
              title: 'Coming soon',
              description: 'This menu is being built.',
            ),
          ],
        ),
      );
  }
}

class ModificationsScreen extends StatefulWidget {
  const ModificationsScreen({super.key});

  @override
  State<ModificationsScreen> createState() => _ModificationsScreenState();
}

enum _ModificationsTab { curveTables, dataTables }

class _ModificationsScreenState extends State<ModificationsScreen> {
  bool _isLoading = true;
  bool _straightBloom = false;
  bool _curveTablesEnabled = true;
  bool _curveLoading = true;
  List<CurveEntry> _curves = [];
  String _selectedGroupId = 'shockwave';
  final Map<String, TextEditingController> _valueControllers = {};

  // DataTable state
  bool _dataTablesEnabled = false;
  bool _dataTablesLoading = true;
  List<DataTableWeapon> _weapons = [];
  String? _selectedWeaponId;
  String? _selectedVariantWeaponId;
  DataTableSettings? _selectedWeaponSettings;
  final Map<String, TextEditingController> _dataTableControllers = {};
  final Map<String, String> _weaponVariantSelections =
      {}; // weaponId -> variantWeaponId

  _ModificationsTab _tab = _ModificationsTab.curveTables;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    for (final controller in _dataTableControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final bloom = await StraightBloomService.isEnabled();
    final curvesEnabled = await CurveTableService.areGlobalEnabled();
    final curves = await CurveTableService.loadCurves();
    final weapons = await DataTableService.loadWeapons();
    final dataTablesEnabled = await DataTableService.getUIEnabledState();
    if (!mounted) return;
    setState(() {
      _straightBloom = bloom;
      _curveTablesEnabled = curvesEnabled;
      _curves = curves;
      _weapons = weapons;
      _dataTablesEnabled = dataTablesEnabled;
      _isLoading = false;
      _curveLoading = false;
      _dataTablesLoading = false;
    });
  }

  Future<void> _toggleStraightBloom(bool value) async {
    if (!mounted) return;
    setState(() {
      _straightBloom = value;
    });
    StraightBloomService.setEnabled(value).ignore();
  }

  Future<void> _toggleCurveTables() async {
    await CurveTableService.toggleGlobal();
    await _load();
  }

  Future<void> _setDataTablesEnabled(bool enabled) async {
    await DataTableService.setUIEnabledState(enabled);
    if (!mounted) return;
    setState(() => _dataTablesEnabled = enabled);

    // Auto-select first weapon when enabling.
    if (enabled && _weapons.isNotEmpty && _selectedWeaponId == null) {
      final firstWeapon = _weapons.first;
      final hasVariants =
          firstWeapon.variants != null && firstWeapon.variants!.isNotEmpty;
      String? variantWeaponId;
      if (hasVariants) {
        variantWeaponId = firstWeapon.variants!.first.weaponId;
      }

      final settings = await DataTableService.getWeaponSettings(
        firstWeapon,
        variantWeaponId: variantWeaponId,
      );
      if (!mounted) return;
      setState(() {
        _selectedWeaponId = firstWeapon.id;
        _selectedVariantWeaponId = variantWeaponId;
        _selectedWeaponSettings = settings;
      });
    }
  }

  Future<void> _importCurvesInModifications() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    final source = File(path);
    if (!await source.exists()) return;
    final importContent = await source.readAsString();
    await _importCurvesFromIniContent(importContent);
  }

  Future<int> _importCurvesFromIniContent(
    String importContent, {
    bool showSummary = true,
    void Function(Map<String, List<String>> grouped, List<_ImportCurveDraft> missing)?
        onSummary,
  }) async {
    final regex = RegExp(
      '^\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$',
      multiLine: true,
    );
    final matches = regex.allMatches(importContent).toList();
    if (matches.isEmpty) return 0;

    final grouped = <String, List<String>>{};
    for (final match in matches) {
      final pathPart = match.group(1)!;
      final key = match.group(2)!;
      final line = match.group(0)!;
      final groupKey = '$pathPart|||$key';
      grouped.putIfAbsent(groupKey, () => []).add(line);
    }

    final existing = await CurveTableService.loadCurves();
    final existingKeys = existing
        .map(
          (entry) =>
              '${entry.pathPart ?? BackendPaths.defaultCurvePath}|||${entry.key}',
        )
        .toSet();

    final missing = <_ImportCurveDraft>[];
    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      final pathPart = parts[0];
      final key = parts[1];
      if (!existingKeys.contains(entry.key)) {
        final parsed = _parseCurveLines(entry.value.join('\n'));
        missing.add(
          _ImportCurveDraft(
            key: key,
            pathPart: pathPart,
            lines: entry.value,
            staticValue: parsed?.staticValue ?? '0',
          ),
        );
      }
    }

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      await CurveTableService.applyCurveLines(parts[0], parts[1], entry.value);
    }

    if (missing.isNotEmpty) {
      final inputs = await _promptImportMissingCurves(
        context,
        missing,
        _groupInfosForPrompt(_curves),
      );
      if (inputs != null && inputs.isNotEmpty) {
        await CurveTableService.addCustomCurves(inputs);
      }
    }

    await _load();
    if (!mounted) return matches.length;
    onSummary?.call(grouped, missing);
    if (showSummary) {
      await _showCurveImportSummary(context, grouped, missing: missing);
    }
    return matches.length;
  }

  Future<void> _restoreDefaultGameIniFromTemplate() async {
    final confirm = await DataService._confirmDialog(
      context,
      'Repair DefaultGame.ini from template? This will overwrite your current DefaultGame.ini in static/hotfixes.',
    );
    if (!confirm) return;

    final templatePaths = [
      joinPath([
        getBackendRoot(),
        'static',
        'hotfixes',
        'DefaultGame Template',
        'DefaultGame.ini',
      ]),
      joinPath([
        getInstallationRoot(),
        'static',
        'hotfixes',
        'DefaultGame Template',
        'DefaultGame.ini',
      ]),
    ];
    File? templateFile;
    for (final path in templatePaths) {
      final candidate = File(path);
      if (await candidate.exists()) {
        templateFile = candidate;
        break;
      }
    }
    if (templateFile == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Template DefaultGame.ini not found in static/hotfixes/DefaultGame Template.',
          ),
        ),
      );
      return;
    }

    final targetFile = File(BackendPaths.defaultGameIni);
    try {
      if (await targetFile.exists()) {
        await targetFile.copy('${targetFile.path}.bak');
      }
      await templateFile.copy(targetFile.path);

      // Reset Modifications toggles to a clean template state.
      await DataTableService.setUIEnabledState(false);
      final curveBackup = File(BackendPaths.modificationsBackup);
      await curveBackup.parent.create(recursive: true);
      await curveBackup.writeAsString(jsonEncode({'curveTableLines': []}));

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DefaultGame.ini repaired from template.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to repair DefaultGame.ini: $error')),
      );
    }
  }

  Future<void> _toggleCurve(CurveEntry entry, bool value) async {
    if (!_curveTablesEnabled) return;
    if (value && entry.type == 'amount' && entry.staticValue == null) {
      bool isValidNumeric(String input) =>
          RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(input.trim());
      final controller = _valueControllers[entry.id];
      final valueText = controller?.text.trim();
      if (valueText == null || valueText.isEmpty) {
        final promptedValue = await _promptValue(context, entry.name);
        if (promptedValue == null) return;
        controller?.text = promptedValue;
        await CurveTableService.setCurveEnabled(
          entry,
          value,
          customValue: promptedValue,
        );
      } else {
        if (!isValidNumeric(valueText)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a valid numeric value.')),
          );
          return;
        }
        await CurveTableService.setCurveEnabled(
          entry,
          value,
          customValue: valueText,
        );
      }
    } else {
      await CurveTableService.setCurveEnabled(entry, value);
    }
    await _load();
  }

  Future<void> _updateCurveValue(CurveEntry entry, String newValue) async {
    if (!_curveTablesEnabled) return;
    final enabled = await CurveTableService.isCurveEnabled(entry);
    if (!enabled) return;
    final isValid = RegExp(
      r'^[+-]?(?:\d+\.?\d*|\.\d+)$',
    ).hasMatch(newValue.trim());
    if (!isValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid numeric value.')),
      );
      return;
    }
    await CurveTableService.setCurveEnabled(entry, true, customValue: newValue);
    await _load();
  }

  List<CurveGroup> get _groups {
    final builtinIds = _baseCurveGroups.map((group) => group.id).toSet();
    final customGroups =
        _customGroupsFromCurves(_curves, excludeIds: builtinIds).map((group) {
          return CurveGroup(
            id: group.id,
            title: group.name,
            imagePath: group.imagePath,
            icon: Icons.auto_awesome,
            keywords: const [],
            isCustom: true,
          );
        }).toList();

    return [..._baseCurveGroups, ...customGroups];
  }

  List<CurveEntry> _entriesForGroup(
    CurveGroup group,
    List<CurveEntry> entries,
  ) {
    final scopedEntries = group.isCustom
        ? entries.where((entry) => entry.isCustom).toList()
        : entries
              .where((entry) => !entry.isCustom || entry.groupId == group.id)
              .toList();
    final groupMatches = scopedEntries
        .where((entry) => group.matches(entry))
        .toList();
    if (!group.isCustom && group.id == 'glider') {
      return groupMatches.where((entry) {
        final name = entry.name.toLowerCase();
        final key = entry.key.toLowerCase();
        return !name.contains('jules') && !key.contains('grapplinghoot');
      }).toList();
    }
    if (!group.isCustom && group.id == 'impulse') {
      return groupMatches.where((entry) {
        final name = entry.name.toLowerCase();
        final key = entry.key.toLowerCase();
        return !name.contains('cube') && !key.contains('cube');
      }).toList();
    }
    return groupMatches;
  }

  String _groupImagePath(CurveGroup group) {
    final customPath = group.imagePath;
    if (customPath != null && customPath.isNotEmpty) {
      return joinPath([getBackendRoot(), 'public', 'items', customPath]);
    }
    final imageName = group.imageName ?? '';
    return joinPath([getBackendRoot(), 'public', 'items', imageName]);
  }

  Future<void> _addCustomCurve() async {
    final inputs = await _promptCustomCurves(
      context,
      _groupInfosForPrompt(_curves),
    );
    if (inputs == null || inputs.isEmpty) return;
    await CurveTableService.addCustomCurves(inputs);
    await _load();
  }

  Future<void> _addCustomDataTable() async {
    final input = await _promptCustomDataTable(context);
    if (input == null) return;
    await DataTableService.addCustomWeapon(input);
    await _load();
  }

  Future<void> _importDataTablesINI() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    final source = File(path);
    if (!await source.exists()) return;
    final importContent = await source.readAsString();
    await _importDataTablesFromIniContent(importContent);
  }

  Future<int> _importDataTablesFromIniContent(
    String importContent, {
    bool showNoEntriesSnackBar = true,
    bool showImportedSnackBar = true,
  }) async {
    // Only import DataTable entries inside the "# DataTables" block, and stop
    // once we reach "# Fixes" (users don't want fix entries imported as normal
    // DataTables toggles). If the file doesn't contain those markers, fall
    // back to importing all +DataTable= lines.
    final lines = _extractDataTableLinesFromIniContent(importContent);
    if (lines.isEmpty) {
      if (showNoEntriesSnackBar) {
        if (!mounted) return 0;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No DataTable entries found in file')),
        );
      }
      return 0;
    }

    await DataTableService.importDataTableLines(lines);
    await _load();

    if (!mounted) return lines.length;
    if (showImportedSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${lines.length} DataTable entries')),
      );
    }
    return lines.length;
  }

  List<String> _extractDataTableLinesFromIniContent(String importContent) {
    final rawLines = importContent.split(RegExp(r'\r?\n'));
    final dataTablesHeader = RegExp(
      r'^\s*#\s*data\s*tables\b',
      caseSensitive: false,
    );
    final fixesHeader = RegExp(r'^\s*#\s*fixes\b', caseSensitive: false);
    final dataTableLine = RegExp(r'^\s*\+DataTable=.+$');

    var start = 0;
    for (var i = 0; i < rawLines.length; i++) {
      if (dataTablesHeader.hasMatch(rawLines[i])) {
        start = i + 1;
        break;
      }
    }

    var end = rawLines.length;
    for (var i = start; i < rawLines.length; i++) {
      if (fixesHeader.hasMatch(rawLines[i])) {
        end = i;
        break;
      }
    }

    final seen = <String>{};
    final extracted = <String>[];
    for (var i = start; i < end; i++) {
      final line = rawLines[i].trim();
      if (line.isEmpty) continue;
      if (!dataTableLine.hasMatch(line)) continue;
      if (seen.add(line)) {
        extracted.add(line);
      }
    }
    return extracted;
  }

  Future<void> _importIniInModifications() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final path = picked.files.single.path!;

    final source = File(path);
    if (!await source.exists()) return;
    final importContent = await source.readAsString();

    final attemptCurves = _curveTablesEnabled;
    final attemptDataTables = _dataTablesEnabled;
    int curveLines = 0;
    int dataTableLines = 0;
    Map<String, List<String>> curveGrouped = const {};
    List<_ImportCurveDraft> curveMissing = const [];

    if (attemptCurves) {
      curveLines = await _importCurvesFromIniContent(
        importContent,
        showSummary: false,
        onSummary: (grouped, missing) {
          curveGrouped = grouped;
          curveMissing = missing;
        },
      );
    }
    if (attemptDataTables) {
      dataTableLines = await _importDataTablesFromIniContent(
        importContent,
        showNoEntriesSnackBar: false,
        showImportedSnackBar: false,
      );
    }

    if (!mounted) return;

    if (curveLines == 0 && dataTableLines == 0) {
      final message = (attemptCurves && attemptDataTables)
          ? 'No CurveTable or DataTable entries found in file'
          : attemptCurves
              ? 'No CurveTable entries found in file'
              : 'No DataTable entries found in file';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    await _showModificationsIniImportSummary(
      context,
      attemptedCurves: attemptCurves,
      attemptedDataTables: attemptDataTables,
      curveGrouped: curveGrouped,
      curveMissing: curveMissing,
      curveLines: curveLines,
      dataTableLines: dataTableLines,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleGroups = _groups
        .where((group) => _entriesForGroup(group, _curves).isNotEmpty)
        .toList();
    final selectedGroup = visibleGroups.firstWhere(
      (group) => group.id == _selectedGroupId,
      orElse: () =>
          visibleGroups.isNotEmpty ? visibleGroups.first : _groups.first,
    );
    return _BaseScreen(
      title: 'Modifications',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverScale(
            child: OutlinedButton.icon(
              onPressed: () async {
                final hotfixesPath = joinPath([
                  getBackendRoot(),
                  'static',
                  'hotfixes',
                ]);
                if (Platform.isWindows) {
                  try {
                    await Process.start('explorer', [hotfixesPath]);
                  } catch (_) {}
                } else if (Platform.isMacOS) {
                  try {
                    await Process.start('open', [hotfixesPath]);
                  } catch (_) {}
                } else if (Platform.isLinux) {
                  try {
                    await Process.start('xdg-open', [hotfixesPath]);
                  } catch (_) {}
                }
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Folder'),
            ),
          ),
          const SizedBox(width: 10),
          _HoverScale(
            enabled:
                !_isLoading && (_curveTablesEnabled || _dataTablesEnabled),
            child: OutlinedButton.icon(
              onPressed:
                  (!_isLoading && (_curveTablesEnabled || _dataTablesEnabled))
                      ? _importIniInModifications
                      : null,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import INI'),
            ),
          ),
          const SizedBox(width: 10),
          _HoverScale(
            child: OutlinedButton.icon(
              onPressed: _restoreDefaultGameIniFromTemplate,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Repair INI'),
            ),
          ),
        ],
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1040;

                Widget disabledCard({
                  required IconData icon,
                  required String title,
                  required String message,
                }) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _onSurface(context, 0.12)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: _onSurface(context, 0.6)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                message,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: _onSurface(context, 0.7)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final straightBloomSwitch = SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _straightBloom,
                  onChanged: _toggleStraightBloom,
                  title: Text(
                    _straightBloom
                        ? 'Straight Bloom Enabled'
                        : 'Straight Bloom Disabled',
                  ),
                  subtitle: const Text('Toggles no-spread for all snipers.'),
                );

                final curveTablesSwitch = SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _curveTablesEnabled,
                  onChanged: (_) => _toggleCurveTables(),
                  title: Text(
                    _curveTablesEnabled
                        ? 'CurveTables Enabled'
                        : 'CurveTables Disabled',
                  ),
                  subtitle: const Text('Toggle all CurveTable entries on/off'),
                );

                final dataTablesSwitch = SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _dataTablesEnabled,
                  onChanged: _setDataTablesEnabled,
                  title: Text(
                    _dataTablesEnabled
                        ? 'DataTables Enabled'
                        : 'DataTables Disabled',
                  ),
                  subtitle: const Text('Toggle weapon damage modifications'),
                );

                final togglesPanel = ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const _SectionTitle(title: 'Straight Bloom'),
                    straightBloomSwitch,
                    const SizedBox(height: 20),
                    const _SectionTitle(title: 'CurveTables'),
                    curveTablesSwitch,
                    const SizedBox(height: 20),
                    const _SectionTitle(title: 'DataTables'),
                    dataTablesSwitch,
                  ],
                );

                final accent = Theme.of(context).colorScheme.secondary;

                Widget tabPill({
                  required String label,
                  required _ModificationsTab tab,
                }) {
                  final selected = _tab == tab;
                  return _HoverRegion(
                    builder: (context, hovered) {
                      final bgColor = selected
                          ? accent.withOpacity(0.18)
                          : hovered
                              ? Colors.black.withOpacity(0.06)
                              : Colors.transparent;
                      final borderColor =
                          selected ? accent.withOpacity(0.55) : Colors.transparent;
                      return GestureDetector(
                        onTap: () => setState(() => _tab = tab),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: borderColor),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color:
                                  selected ? accent : _onSurface(context, 0.75),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }

                final tablesTabs = Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _onSurface(context, 0.12)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: tabPill(
                          label: 'CurveTables',
                          tab: _ModificationsTab.curveTables,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: tabPill(
                          label: 'DataTables',
                          tab: _ModificationsTab.dataTables,
                        ),
                      ),
                    ],
                  ),
                );

                final contentPanel = ListView(
                  children: [
                    if (!isWide) ...[
                      const _SectionTitle(title: 'Straight Bloom'),
                      straightBloomSwitch,
                      const SizedBox(height: 20),
                    ],
                    tablesTabs,
                    const SizedBox(height: 20),
                    if (_tab == _ModificationsTab.curveTables) ...[
                      if (!isWide) curveTablesSwitch,
                      const SizedBox(height: 8),
                      if (isWide && !_curveTablesEnabled)
                        disabledCard(
                          icon: Icons.table_rows_outlined,
                          title: 'CurveTables Disabled',
                          message:
                              'Enable CurveTables on the left to manage hotfix curve entries.',
                        ),
                      if (_curveTablesEnabled) ...[
                        const SizedBox(height: 12),
                        _curveLoading
                            ? const Center(child: CircularProgressIndicator())
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: visibleGroups.map((group) {
                                final isSelected = selectedGroup.id == group.id;
                                final imageFile = File(_groupImagePath(group));
                                final isDark =
                                    Theme.of(context).brightness ==
                                    Brightness.dark;
                                return GestureDetector(
                                  onTap: () => setState(
                                    () => _selectedGroupId = group.id,
                                  ),
                                  child: _HoverRegion(
                                    builder: (context, hovered) => AnimatedScale(
                                      duration: const Duration(
                                        milliseconds: 140,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      scale: hovered ? 1.03 : 1,
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        width: 140,
                                        height: 130,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          color: isSelected
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .secondary
                                                    .withOpacity(0.18)
                                              : Colors.black.withOpacity(0.08),
                                          border: Border.all(
                                            color: isSelected
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .secondary
                                                      .withOpacity(0.6)
                                                : _onSurface(context, 0.12),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            if (imageFile.existsSync())
                                              _HoverShadow(
                                                opacity: 0.75,
                                                blurSigma: 2,
                                                baseOffset: const Offset(0, 2),
                                                hoverOffset: const Offset(4, 2),
                                                hovered: hovered,
                                                child: (group.id == 'fall'
                                                    ? ColorFiltered(
                                                        colorFilter:
                                                            ColorFilter.mode(
                                                              isDark
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .black,
                                                              BlendMode.srcIn,
                                                            ),
                                                        child: Image.file(
                                                          imageFile,
                                                          width: 52,
                                                          height: 52,
                                                          fit: BoxFit.contain,
                                                        ),
                                                      )
                                                    : Image.file(
                                                        imageFile,
                                                        width: 52,
                                                        height: 52,
                                                        fit: BoxFit.contain,
                                                      )),
                                              )
                                            else
                                              _HoverShadow(
                                                opacity: 0.75,
                                                blurSigma: 2,
                                                baseOffset: const Offset(0, 2),
                                                hoverOffset: const Offset(4, 2),
                                                hovered: hovered,
                                                child: Icon(
                                                  group.icon,
                                                  size: 38,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.secondary,
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            Text(
                                              group.title,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Text(
                                  selectedGroup.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const Spacer(),
                                if (selectedGroup.isCustom)
                                  _HoverScale(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final updated =
                                            await _promptEditCustomGroup(
                                              context,
                                              selectedGroup.id,
                                              selectedGroup.title,
                                            );
                                        if (updated == null) return;
                                        await CurveTableService.updateCustomGroup(
                                          selectedGroup.id,
                                          updated.name,
                                          updated.imagePath,
                                        );
                                        await _load();
                                      },
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Edit Group'),
                                    ),
                                  ),
                                if (selectedGroup.isCustom)
                                  const SizedBox(width: 8),
                                if (selectedGroup.isCustom)
                                  _HoverScale(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final confirm =
                                            await DataService._confirmDialog(
                                              context,
                                              'Delete group "${selectedGroup.title}" and all its custom curves?',
                                            );
                                        if (!confirm) return;
                                        await CurveTableService.deleteCustomGroup(
                                          selectedGroup.id,
                                        );
                                        await _load();
                                      },
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      label: const Text('Delete Group'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.redAccent,
                                      ),
                                    ),
                                  ),
                                if (selectedGroup.isCustom)
                                  const SizedBox(width: 8),
                                _HoverScale(
                                  enabled: _curveTablesEnabled,
                                  child: OutlinedButton.icon(
                                    onPressed: _addCustomCurve,
                                    icon: const Icon(Icons.add_circle_outline),
                                    label: const Text('Add Custom Curve'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF1E88E5),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _HoverScale(
                                  enabled: _curveTablesEnabled,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final confirm =
                                          await DataService._confirmDialog(
                                            context,
                                            'Clear all CurveTables from DefaultGame.ini?',
                                          );
                                      if (!confirm) return;
                                      await CurveTableService.clearAllCurveTables();
                                      await _load();
                                    },
                                    icon: const Icon(
                                      Icons.delete_sweep_outlined,
                                    ),
                                    label: const Text('Clear All CurveTables'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF1E88E5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._entriesForGroup(selectedGroup, _curves).map((
                              entry,
                            ) {
                              final controller = _valueControllers.putIfAbsent(
                                entry.id,
                                () => TextEditingController(),
                              );
                              return _CurveEntryTile(
                                entry: entry,
                                enabled: _curveTablesEnabled,
                                valueController: controller,
                                onToggle: (value) => _toggleCurve(entry, value),
                                onSubmit: (value) =>
                                    _updateCurveValue(entry, value),
                                onEdit: entry.isCustom
                                    ? () async {
                                        final updated =
                                            await _promptEditCustomCurve(
                                              context,
                                              entry,
                                              _groupInfosForPrompt(_curves),
                                            );
                                        if (updated == null) return;
                                        await CurveTableService.updateCustomCurve(
                                          entry.id,
                                          updated,
                                        );
                                        await _load();
                                      }
                                    : null,
                                onDelete: entry.isCustom
                                    ? () async {
                                        final confirm =
                                            await DataService._confirmDialog(
                                              context,
                                              'Delete custom curve "${entry.name}"?',
                                            );
                                        if (!confirm) return;
                                        await CurveTableService.deleteCustomCurve(
                                          entry.id,
                                        );
                                        await _load();
                                      }
                                    : null,
                              );
                            }),
                              ],
                            ),
                    ],
                    ],
                    if (_tab == _ModificationsTab.dataTables) ...[
                      if (!isWide) dataTablesSwitch,
                      const SizedBox(height: 8),
                      if (isWide && !_dataTablesEnabled)
                        disabledCard(
                          icon: Icons.tune_rounded,
                          title: 'DataTables Disabled',
                          message:
                              'Enable DataTables on the left to manage weapon damage modifications.',
                        ),
                      if (_dataTablesEnabled) ...[
                        const SizedBox(height: 12),
                        _dataTablesLoading
                            ? const Center(child: CircularProgressIndicator())
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: _weapons.map((weapon) {
                                final isSelected =
                                    _selectedWeaponId == weapon.id;
                                // Check if selected variant has its own image
                                String? effectiveImagePath = weapon.imagePath;
                                if (weapon.variants != null &&
                                    weapon.variants!.isNotEmpty) {
                                  // Use currently selected variant if this weapon is selected, otherwise use remembered variant
                                  final variantWeaponId = isSelected
                                      ? _selectedVariantWeaponId
                                      : _weaponVariantSelections[weapon.id];

                                  if (variantWeaponId != null) {
                                    final variant = weapon.variants!.firstWhere(
                                      (v) => v.weaponId == variantWeaponId,
                                      orElse: () => weapon.variants!.first,
                                    );
                                    if (variant.imagePath != null) {
                                      effectiveImagePath = variant.imagePath;
                                    }
                                  }
                                }
                                final imagePath = effectiveImagePath != null
                                    ? joinPath([
                                        getBackendRoot(),
                                        'public',
                                        'items',
                                        effectiveImagePath,
                                      ])
                                    : null;
                                final imageFile = imagePath != null
                                    ? File(imagePath)
                                    : null;
                                return GestureDetector(
                                  onTap: () async {
                                    final hasVariants =
                                        weapon.variants != null &&
                                        weapon.variants!.isNotEmpty;
                                    // Check if we've previously selected a variant for this weapon
                                    String? variantWeaponId;
                                    if (hasVariants) {
                                      variantWeaponId =
                                          _weaponVariantSelections[weapon.id] ??
                                          weapon.variants!.first.weaponId;
                                    }
                                    final settings =
                                        await DataTableService.getWeaponSettings(
                                          weapon,
                                          variantWeaponId: variantWeaponId,
                                        );
                                    setState(() {
                                      _selectedWeaponId = weapon.id;
                                      _selectedVariantWeaponId =
                                          variantWeaponId;
                                      _selectedWeaponSettings = settings;
                                    });
                                  },
                                  child: _HoverRegion(
                                    builder: (context, hovered) =>
                                        AnimatedScale(
                                          duration: const Duration(
                                            milliseconds: 140,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          scale: hovered ? 1.03 : 1,
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            width: 140,
                                            height: 130,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              color: isSelected
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .secondary
                                                        .withOpacity(0.18)
                                                  : Colors.black.withOpacity(
                                                      0.08,
                                                    ),
                                              border: Border.all(
                                                color: isSelected
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .secondary
                                                          .withOpacity(0.6)
                                                    : _onSurface(context, 0.12),
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                if (imageFile != null &&
                                                    imageFile.existsSync())
                                                  _HoverShadow(
                                                    opacity: 0.75,
                                                    blurSigma: 2,
                                                    baseOffset: const Offset(
                                                      0,
                                                      2,
                                                    ),
                                                    hoverOffset: const Offset(
                                                      4,
                                                      2,
                                                    ),
                                                    hovered: hovered,
                                                    child: Image.file(
                                                      imageFile,
                                                      width: 52,
                                                      height: 52,
                                                      fit: BoxFit.contain,
                                                    ),
                                                  )
                                                else
                                                  _HoverShadow(
                                                    opacity: 0.75,
                                                    blurSigma: 2,
                                                    baseOffset: const Offset(
                                                      0,
                                                      2,
                                                    ),
                                                    hoverOffset: const Offset(
                                                      4,
                                                      2,
                                                    ),
                                                    hovered: hovered,
                                                    child: Icon(
                                                      Icons.sports_esports,
                                                      size: 38,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.secondary,
                                                    ),
                                                  ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  weapon.name,
                                                  textAlign: TextAlign.center,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                  ),
                                );
                              }).toList(),
                            ),
                            if (_selectedWeaponId != null &&
                                _selectedWeaponSettings != null) ...[
                              const SizedBox(height: 20),
                              _buildWeaponSettings(),
                            ],
                          ],
                        ),
                ],
                    ],
              ],
            );

                if (!isWide) return contentPanel;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 340, child: togglesPanel),
                    const SizedBox(width: 24),
                    Container(width: 1, color: _onSurface(context, 0.08)),
                    const SizedBox(width: 24),
                    Expanded(child: contentPanel),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildWeaponSettings() {
    final weapon = _weapons.firstWhere((w) => w.id == _selectedWeaponId);
    final settings = _selectedWeaponSettings!;
    final hasVariants = weapon.variants != null && weapon.variants!.isNotEmpty;

    WeaponVariant? currentVariant;
    if (hasVariants && _selectedVariantWeaponId != null) {
      currentVariant = weapon.variants!.firstWhere(
        (v) => v.weaponId == _selectedVariantWeaponId,
        orElse: () => weapon.variants!.first,
      );
    }

    final displayDefaultDamage = currentVariant?.damagePB ?? weapon.damagePB;
    final displayDefaultEnvDamage =
        currentVariant?.defaultEnvDamage ?? weapon.defaultEnvDamage;
    final displayDefaultClipSize = weapon.clipSize ?? '30';
    final displayDefaultReloadTime = currentVariant?.reloadTime ?? '2.0';

    // Check which fields are available for this weapon
    final hasDamageFields = weapon.damageFields.isNotEmpty;
    final hasEnvDamageFields = weapon.environmentalDamageFields.isNotEmpty;
    final hasClipSize = weapon.clipSize != null;
    final hasReloadTime = hasVariants 
        ? (currentVariant?.reloadTime != null)
        : false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Text(
                weapon.name,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 7,
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HoverScale(
                      enabled: _dataTablesEnabled,
                      child: OutlinedButton.icon(
                        onPressed: _addCustomDataTable,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add Custom DataTable'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E88E5),
                        ),
                      ),
                    ),
                    _HoverScale(
                      enabled: _dataTablesEnabled,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirm = await DataService._confirmDialog(
                            context,
                            'Clear all DataTables from DefaultGame.ini?',
                          );
                          if (!confirm) return;
                          await DataTableService.clearAllDataTables();
                          await _load();
                        },
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Clear All DataTables'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E88E5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hasVariants) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              value: _selectedVariantWeaponId,
              decoration: InputDecoration(
                labelText: 'Variant',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: weapon.variants!.map((variant) {
                return DropdownMenuItem(
                  value: variant.weaponId,
                  child: Text(variant.name),
                );
              }).toList(),
              onChanged: (value) async {
                if (value != null) {
                  final newSettings = await DataTableService.getWeaponSettings(
                    weapon,
                    variantWeaponId: value,
                  );
                  setState(() {
                    _selectedVariantWeaponId = value;
                    _selectedWeaponSettings = newSettings;
                    _weaponVariantSelections[weapon.id] =
                        value; // Remember this selection
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (hasDamageFields) SwitchListTile(
          value: settings.damageEnabled,
          onChanged: (value) async {
            if (value) {
              // Prompt for damage value
              final promptedValue = await _promptValue(
                context,
                'Damage',
                defaultValue: displayDefaultDamage,
              );
              if (promptedValue == null) return;
              final newSettings = settings.copyWith(
                damageEnabled: value,
                damageValue: promptedValue,
              );
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            } else {
              final newSettings = settings.copyWith(damageEnabled: value);
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            }
          },
          title: const Text('Damage'),
          subtitle: settings.damageEnabled && !settings.advancedMode
              ? Text('Current value: ${settings.damageValue}')
              : const Text('Enable custom damage values'),
        ),
        if (settings.damageEnabled && !settings.advancedMode) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () async {
                final promptedValue = await _promptValue(
                  context,
                  'Damage',
                  defaultValue: displayDefaultDamage,
                );
                if (promptedValue == null) return;
                final newSettings = settings.copyWith(
                  damageValue: promptedValue,
                );
                await DataTableService.applyWeaponSettings(
                  weapon,
                  newSettings,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                final updated = await DataTableService.getWeaponSettings(
                  weapon,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                setState(() => _selectedWeaponSettings = updated);
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Damage Value'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (hasEnvDamageFields) SwitchListTile(
          value: settings.envDamageEnabled,
          onChanged: (value) async {
            if (value) {
              // Prompt for environmental damage value
              final promptedValue = await _promptValue(
                context,
                'Environmental Damage',
                defaultValue: displayDefaultEnvDamage,
              );
              if (promptedValue == null) return;
              final newSettings = settings.copyWith(
                envDamageEnabled: value,
                envDamageValue: promptedValue,
              );
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            } else {
              final newSettings = settings.copyWith(envDamageEnabled: value);
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            }
          },
          title: const Text('Environmental Damage'),
          subtitle: settings.envDamageEnabled && !settings.advancedMode
              ? Text('Current value: ${settings.envDamageValue}')
              : const Text('Enable custom environmental damage'),
        ),
        if (settings.envDamageEnabled && !settings.advancedMode) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () async {
                final promptedValue = await _promptValue(
                  context,
                  'Environmental Damage',
                  defaultValue: displayDefaultEnvDamage,
                );
                if (promptedValue == null) return;
                final newSettings = settings.copyWith(
                  envDamageValue: promptedValue,
                );
                await DataTableService.applyWeaponSettings(
                  weapon,
                  newSettings,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                final updated = await DataTableService.getWeaponSettings(
                  weapon,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                setState(() => _selectedWeaponSettings = updated);
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Environmental Damage Value'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (hasClipSize) SwitchListTile(
          value: settings.clipSizeEnabled,
          onChanged: (value) async {
            if (value) {
              // Prompt for clip size value
              final promptedValue = await _promptValue(
                context,
                'Clip Size',
                defaultValue: displayDefaultClipSize,
              );
              if (promptedValue == null) return;
              final newSettings = settings.copyWith(
                clipSizeEnabled: value,
                clipSizeValue: promptedValue,
              );
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            } else {
              final newSettings = settings.copyWith(clipSizeEnabled: value);
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            }
          },
          title: const Text('Clip Size'),
          subtitle: settings.clipSizeEnabled
              ? Text('Current value: ${settings.clipSizeValue}')
              : const Text('Enable custom clip size'),
        ),
        if (settings.clipSizeEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () async {
                final promptedValue = await _promptValue(
                  context,
                  'Clip Size',
                  defaultValue: displayDefaultClipSize,
                );
                if (promptedValue == null) return;
                final newSettings = settings.copyWith(
                  clipSizeValue: promptedValue,
                );
                await DataTableService.applyWeaponSettings(
                  weapon,
                  newSettings,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                final updated = await DataTableService.getWeaponSettings(
                  weapon,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                setState(() => _selectedWeaponSettings = updated);
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Clip Size Value'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (hasReloadTime) SwitchListTile(
          value: settings.reloadTimeEnabled,
          onChanged: (value) async {
            if (value) {
              // Prompt for reload time value
              final promptedValue = await _promptValue(
                context,
                'Reload Time',
                defaultValue: displayDefaultReloadTime,
              );
              if (promptedValue == null) return;
              final newSettings = settings.copyWith(
                reloadTimeEnabled: value,
                reloadTimeValue: promptedValue,
              );
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            } else {
              final newSettings = settings.copyWith(reloadTimeEnabled: value);
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            }
          },
          title: const Text('Reload Time'),
          subtitle: settings.reloadTimeEnabled
              ? Text('Current value: ${settings.reloadTimeValue}')
              : const Text('Enable custom reload time'),
        ),
        if (settings.reloadTimeEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () async {
                final promptedValue = await _promptValue(
                  context,
                  'Reload Time',
                  defaultValue: displayDefaultReloadTime,
                );
                if (promptedValue == null) return;
                final newSettings = settings.copyWith(
                  reloadTimeValue: promptedValue,
                );
                await DataTableService.applyWeaponSettings(
                  weapon,
                  newSettings,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                final updated = await DataTableService.getWeaponSettings(
                  weapon,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                setState(() => _selectedWeaponSettings = updated);
              },
              icon: const Icon(Icons.edit),
              label: const Text('Edit Reload Time Value'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (hasDamageFields || hasEnvDamageFields) SwitchListTile(
          value: settings.advancedMode,
          onChanged: (value) async {
            if (value) {
              // Collect all relevant fields
              final allFields = <String>[];
              if (settings.damageEnabled) {
                allFields.addAll(weapon.damageFields);
              }
              if (settings.envDamageEnabled) {
                allFields.addAll(weapon.environmentalDamageFields);
              }

              if (allFields.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Enable Damage or Environmental Damage first.',
                    ),
                  ),
                );
                return;
              }

              // Determine default values based on what's enabled
              String defaultValue = displayDefaultDamage;
              if (settings.damageEnabled && !settings.envDamageEnabled) {
                defaultValue = displayDefaultDamage;
              } else if (!settings.damageEnabled && settings.envDamageEnabled) {
                defaultValue = displayDefaultEnvDamage;
              }

              final values = await _promptAdvancedSettings(
                context,
                allFields,
                settings.customValues,
                defaultValue,
              );
              if (values == null) return;

              final newSettings = settings.copyWith(
                advancedMode: value,
                customValues: values,
              );
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            } else {
              final newSettings = settings.copyWith(advancedMode: value);
              // Re-apply settings to use simple mode values
              await DataTableService.applyWeaponSettings(
                weapon,
                newSettings,
                variantWeaponId: _selectedVariantWeaponId,
              );
              final updated = await DataTableService.getWeaponSettings(
                weapon,
                variantWeaponId: _selectedVariantWeaponId,
              );
              setState(() => _selectedWeaponSettings = updated);
            }
          },
          title: const Text('Advanced Settings'),
          subtitle: const Text('Customize each damage field individually'),
        ),
        if (settings.advancedMode) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () async {
                // Collect all relevant fields
                final allFields = <String>[];
                if (settings.damageEnabled) {
                  allFields.addAll(weapon.damageFields);
                }
                if (settings.envDamageEnabled) {
                  allFields.addAll(weapon.environmentalDamageFields);
                }

                // Determine default values based on what's enabled
                String defaultValue = displayDefaultDamage;
                if (settings.damageEnabled && !settings.envDamageEnabled) {
                  defaultValue = displayDefaultDamage;
                } else if (!settings.damageEnabled &&
                    settings.envDamageEnabled) {
                  defaultValue = displayDefaultEnvDamage;
                }

                final values = await _promptAdvancedSettings(
                  context,
                  allFields,
                  settings.customValues,
                  defaultValue,
                );
                if (values == null) return;

                final newSettings = settings.copyWith(customValues: values);
                await DataTableService.applyWeaponSettings(
                  weapon,
                  newSettings,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                final updated = await DataTableService.getWeaponSettings(
                  weapon,
                  variantWeaponId: _selectedVariantWeaponId,
                );
                setState(() => _selectedWeaponSettings = updated);
              },
              icon: const Icon(Icons.tune),
              label: const Text('Edit Advanced Settings'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class CurveTablesScreen extends StatefulWidget {
  const CurveTablesScreen({super.key});

  @override
  State<CurveTablesScreen> createState() => _CurveTablesScreenState();
}

class _CurveTablesScreenState extends State<CurveTablesScreen> {
  bool _loading = true;
  bool _globalEnabled = true;
  List<CurveEntry> _curves = [];
  String _search = '';
  final Map<String, TextEditingController> _valueControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final curves = await CurveTableService.loadCurves();
    final enabled = await CurveTableService.areGlobalEnabled();
    if (!mounted) return;
    setState(() {
      _curves = curves;
      _globalEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _toggleCurve(CurveEntry entry, bool value) async {
    if (!_globalEnabled) return;
    if (value && entry.type == 'amount' && entry.staticValue == null) {
      bool isValidNumeric(String input) =>
          RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(input.trim());
      final controller = _valueControllers[entry.id];
      final valueText = controller?.text.trim();
      if (valueText == null || valueText.isEmpty) {
        final promptedValue = await _promptValue(context, entry.name);
        if (promptedValue == null) return;
        controller?.text = promptedValue;
        await CurveTableService.setCurveEnabled(
          entry,
          value,
          customValue: promptedValue,
        );
      } else {
        if (!isValidNumeric(valueText)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a valid numeric value.')),
          );
          return;
        }
        await CurveTableService.setCurveEnabled(
          entry,
          value,
          customValue: valueText,
        );
      }
    } else {
      await CurveTableService.setCurveEnabled(entry, value);
    }
    await _load();
  }

  Future<void> _updateCurveValue(CurveEntry entry, String newValue) async {
    if (!_globalEnabled) return;
    final enabled = await CurveTableService.isCurveEnabled(entry);
    if (!enabled) return;
    final isValid = RegExp(
      r'^[+-]?(?:\d+\.?\d*|\.\d+)$',
    ).hasMatch(newValue.trim());
    if (!isValid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid numeric value.')),
      );
      return;
    }
    await CurveTableService.setCurveEnabled(entry, true, customValue: newValue);
    await _load();
  }

  Future<void> _addCustomCurve() async {
    final inputs = await _promptCustomCurves(
      context,
      _groupInfosForPrompt(_curves),
    );
    if (inputs == null || inputs.isEmpty) return;
    await CurveTableService.addCustomCurves(inputs);
    await _load();
  }

  Future<void> _importCurves() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import DefaultGame.ini',
      type: FileType.custom,
      allowedExtensions: ['ini'],
    );
    if (picked == null || picked.files.single.path == null) return;
    await CurveTableService.importFromIni(picked.files.single.path!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _curves.where((entry) {
      if (_search.trim().isEmpty) return true;
      final query = _search.toLowerCase();
      return entry.name.toLowerCase().contains(query) ||
          entry.key.toLowerCase().contains(query);
    }).toList();

    return _BaseScreen(
      title: 'CurveTables',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverScale(
            enabled: _globalEnabled,
            child: IconButton(
              tooltip: 'Import DefaultGame.ini',
              onPressed: _globalEnabled ? _importCurves : null,
              icon: const Icon(Icons.file_upload),
            ),
          ),
          _HoverScale(
            enabled: _globalEnabled,
            child: OutlinedButton.icon(
              onPressed: _globalEnabled ? _addCustomCurve : null,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Custom Curve'),
            ),
          ),
        ],
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    labelText: 'Search CurveTables',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (!_globalEnabled)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'CurveTables are disabled. Enable them in Modifications to edit.',
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      _valueControllers.putIfAbsent(
                        entry.id,
                        () => TextEditingController(),
                      );
                      return FutureBuilder<Map<String, dynamic>>(
                        future:
                            Future.wait([
                              CurveTableService.isCurveEnabled(entry),
                              CurveTableService.getCurrentValue(entry),
                            ]).then(
                              (results) => {
                                'enabled': results[0],
                                'value': results[1],
                              },
                            ),
                        builder: (context, snapshot) {
                          final enabled =
                              snapshot.data?['enabled'] as bool? ?? false;
                          final value = snapshot.data?['value'] as String?;
                          final controller = _valueControllers[entry.id]!;
                          if (!enabled) {
                            if (controller.text.isNotEmpty) {
                              controller.text = '';
                            }
                          } else if (value != null) {
                            if (controller.text != value) {
                              controller.text = value;
                            }
                          }
                          final canEdit =
                              entry.type == 'amount' ||
                              (entry.type == 'static' &&
                                  entry.staticValue == null);
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: enabled
                                    ? const Color(0xFF6BE7FF).withOpacity(0.3)
                                    : Colors.white10,
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          entry.key,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _onSurface(context, 0.75),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (enabled && canEdit && value != null) ...[
                                    const SizedBox(width: 12),
                                    Container(
                                      width: 140,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF6BE7FF,
                                        ).withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(
                                            0xFF6BE7FF,
                                          ).withOpacity(0.4),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _valueControllers[entry.id],
                                        enabled: _globalEnabled,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontFamily: 'monospace',
                                          color: Color(0xFF6BE7FF),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          border: InputBorder.none,
                                          hintText: 'Value...',
                                          hintStyle: TextStyle(
                                            color: Color(0xFF6BE7FF),
                                            fontSize: 12,
                                          ),
                                        ),
                                        textAlign: TextAlign.center,
                                        onSubmitted: (newValue) =>
                                            _updateCurveValue(entry, newValue),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: enabled,
                                    onChanged: _globalEnabled
                                        ? (value) => _toggleCurve(entry, value)
                                        : null,
                                  ),
                                  if (entry.isCustom) ...[
                                    const SizedBox(width: 8),
                                    _HoverScale(
                                      child: IconButton(
                                        tooltip: 'Edit Curve',
                                        onPressed: () async {
                                          final updated =
                                              await _promptEditCustomCurve(
                                                context,
                                                entry,
                                                _groupInfosForPrompt(_curves),
                                              );
                                          if (updated == null) return;
                                          await CurveTableService.updateCustomCurve(
                                            entry.id,
                                            updated,
                                          );
                                          await _load();
                                        },
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                    ),
                                    _HoverScale(
                                      child: IconButton(
                                        tooltip: 'Delete Curve',
                                        onPressed: () async {
                                          final confirm =
                                              await DataService._confirmDialog(
                                                context,
                                                'Delete custom curve "${entry.name}"?',
                                              );
                                          if (!confirm) return;
                                          await CurveTableService.deleteCustomCurve(
                                            entry.id,
                                          );
                                          await _load();
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key});

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  bool _saveArenaPoints = false;
  bool _leaderboardLoading = true;
  List<ArenaEntry> _leaderboard = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Load config immediately so screen shows
    final config = await ConfigService.load();
    if (mounted) {
      setState(() {
        _saveArenaPoints = config.saveArenaPoints;
      });
    }

    // Load leaderboard in background (always fresh)
    final leaderboard = await ArenaService.loadLeaderboard();
    if (!mounted) return;
    setState(() {
      _leaderboard = leaderboard;
      _leaderboardLoading = false;
    });
  }

  void _showFullLeaderboard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    unawaited(
      _showBlurDialog<void>(
        context: context,
        builder: (dialogContext) =>
            _buildLeaderboardDialog(dialogContext, isDark),
      ),
    );
  }

  Widget _buildLeaderboardDialog(BuildContext context, bool isDark) {
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 500,
            height: 600,
            decoration: BoxDecoration(
              color: _dialogSurfaceColor(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _onSurface(context, 0.1)),
              boxShadow: [
                BoxShadow(
                  color: _dialogShadowColor(context),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Full Leaderboard',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 50,
                      child: Text(
                        'Rank',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Name',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      'Points',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _leaderboard.length,
                  itemBuilder: (context, index) {
                    final entry = _leaderboard[index];
                    final rank = index + 1;

                    Color? rankColor;
                    FontWeight rankWeight = FontWeight.bold;
                    double rankSize = 14;

                    if (rank == 1) {
                      rankColor = const Color(0xFFD4AF37); // Gold
                      rankWeight = FontWeight.w900;
                      rankSize = 16;
                    } else if (rank == 2) {
                      rankColor = const Color(0xFFC0C0C0); // Silver
                      rankWeight = FontWeight.w900;
                      rankSize = 16;
                    } else if (rank == 3) {
                      rankColor = const Color(0xFFCD7F32); // Bronze
                      rankWeight = FontWeight.w900;
                      rankSize = 16;
                    } else {
                      rankColor = isDark
                          ? Colors.grey.shade300
                          : Colors.grey.shade700;
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              (isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade100)
                                  .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 50,
                              child: Text(
                                '#$rank',
                                style: TextStyle(
                                  fontWeight: rankWeight,
                                  fontSize: rankSize,
                                  color: rankColor,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.accountId,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${entry.hype}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.orangeAccent
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSavePoints(bool value) async {
    final config = await ConfigService.load();
    await ConfigService.save(config.copyWith(saveArenaPoints: value));
    if (!mounted) return;
    setState(() => _saveArenaPoints = value);
  }

  @override
  Widget build(BuildContext context) {
    final top3 = _leaderboard.take(3).toList();
    final rest = _leaderboard.skip(3).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final leaderboardTitleColor = isDark ? Colors.white70 : Colors.black87;
    final podiumBaselineColor = isDark
        ? Colors.grey.shade700
        : Colors.grey.shade300;
    final listRowColor = (isDark ? Colors.grey.shade800 : Colors.grey.shade100)
        .withOpacity(0.5);
    final listRankColor = isDark ? Colors.grey.shade300 : Colors.grey.shade600;
    final listNameColor = isDark ? Colors.white70 : Colors.black87;
    final listHypeColor = isDark ? Colors.orangeAccent : Colors.orange.shade700;
    final podiumNameColor = isDark ? Colors.white : Colors.black87;

    return _BaseScreen(
      title: 'Arena',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Arena leaderboard and point saving is in development.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side: Save Arena Points
                Expanded(
                  flex: 1,
                  child: SwitchListTile(
                    value: _saveArenaPoints,
                    onChanged: null,
                    title: const Text('Save Arena Points'),
                    subtitle: const Text(
                      'Persist player hype between sessions',
                    ),
                    secondary: const Tooltip(
                      message: 'Disabled',
                      child: Icon(Icons.info_outline, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Right side: Leaderboard Box
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: [
                      GlassPanel(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      'Leaderboard',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: leaderboardTitleColor,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        _showFullLeaderboard(context),
                                    icon: const Icon(Icons.list_alt, size: 16),
                                    label: const Text(
                                      'View Full List',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // Top 3 Podium
                              Column(
                                children: [
                                  SizedBox(
                                    height: 230,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        // 2nd Place
                                        Flexible(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              top3.length >= 2
                                                  ? _buildPodiumPillarContent(
                                                      entry: top3[1],
                                                      rank: 2,
                                                      medalColor: const Color(
                                                        0xFFC0C0C0,
                                                      ),
                                                      nameColor:
                                                          podiumNameColor,
                                                    )
                                                  : _buildEmptyPodiumPillarContent(
                                                      rank: 2,
                                                    ),
                                              const SizedBox(height: 8),
                                              Container(
                                                width: 60,
                                                height: 100,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFC0C0C0,
                                                  ),
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(8),
                                                        topRight:
                                                            Radius.circular(8),
                                                      ),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFB0B0B0,
                                                    ),
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '#2',
                                                    style: TextStyle(
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color:
                                                          Colors.grey.shade200,
                                                      shadows: const [
                                                        Shadow(
                                                          blurRadius: 8,
                                                          color: Color(
                                                            0x99000000,
                                                          ),
                                                          offset: Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // 1st Place
                                        Flexible(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              top3.isNotEmpty
                                                  ? _buildPodiumPillarContent(
                                                      entry: top3[0],
                                                      rank: 1,
                                                      medalColor: const Color(
                                                        0xFFD4AF37,
                                                      ),
                                                      nameColor:
                                                          podiumNameColor,
                                                    )
                                                  : _buildEmptyPodiumPillarContent(
                                                      rank: 1,
                                                    ),
                                              const SizedBox(height: 8),
                                              Container(
                                                width: 60,
                                                height: 140,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFD4AF37,
                                                  ),
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(8),
                                                        topRight:
                                                            Radius.circular(8),
                                                      ),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFC89B2C,
                                                    ),
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '#1',
                                                    style: TextStyle(
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Colors
                                                          .yellow
                                                          .shade100,
                                                      shadows: const [
                                                        Shadow(
                                                          blurRadius: 10,
                                                          color: Color(
                                                            0xCC000000,
                                                          ),
                                                          offset: Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // 3rd Place
                                        Flexible(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              top3.length >= 3
                                                  ? _buildPodiumPillarContent(
                                                      entry: top3[2],
                                                      rank: 3,
                                                      medalColor: const Color(
                                                        0xFFCD7F32,
                                                      ),
                                                      nameColor:
                                                          podiumNameColor,
                                                    )
                                                  : _buildEmptyPodiumPillarContent(
                                                      rank: 3,
                                                    ),
                                              const SizedBox(height: 8),
                                              Container(
                                                width: 60,
                                                height: 80,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFCD7F32,
                                                  ),
                                                  borderRadius:
                                                      const BorderRadius.only(
                                                        topLeft:
                                                            Radius.circular(8),
                                                        topRight:
                                                            Radius.circular(8),
                                                      ),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFB56A2A,
                                                    ),
                                                    width: 2,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '#3',
                                                    style: TextStyle(
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Colors
                                                          .orange
                                                          .shade100,
                                                      shadows: const [
                                                        Shadow(
                                                          blurRadius: 8,
                                                          color: Color(
                                                            0x99000000,
                                                          ),
                                                          offset: Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    height: 2,
                                    color: podiumBaselineColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Column headers for the list
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        'Rank',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Text(
                                          'Name',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Points',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Scrollable list of remaining players
                              Expanded(
                                child: rest.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No more players',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: rest.length,
                                        itemBuilder: (context, index) {
                                          final entry = rest[index];
                                          final rank = index + 4;
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: listRowColor,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 40,
                                                    child: Text(
                                                      '#$rank',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: listRankColor,
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                          ),
                                                      child: Text(
                                                        entry.accountId,
                                                        style: TextStyle(
                                                          color: listNameColor,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '${entry.hype}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: listHypeColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Loading overlay with blur
                      if (_leaderboardLoading)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedOpacity(
                              opacity: _leaderboardLoading ? 1 : 0,
                              duration: const Duration(milliseconds: 400),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                child: Container(
                                  color: Colors.black.withOpacity(0.3),
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumPillar({
    required int rank,
    required ArenaEntry entry,
    required double height,
    required Color color,
    required Color medalColor,
  }) {
    final medalIcons = {
      1: Icons.emoji_events,
      2: Icons.military_tech,
      3: Icons.grade,
    };

    final displayName = entry.accountId.trim().isEmpty
        ? 'You'
        : entry.accountId.trim();
    final shortName = displayName.length > 14
        ? '${displayName.substring(0, 14)}…'
        : displayName;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(medalIcons[rank] ?? Icons.circle, color: medalColor, size: 20),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: SizedBox(
            width: 72,
            child: Text(
              shortName,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.7),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${entry.hype}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPodiumPillar({
    required int rank,
    required double height,
    required Color color,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
        const SizedBox(height: 4),
        const SizedBox(
          width: 60,
          child: Text(
            'Empty',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPodiumPillarContent({
    required ArenaEntry entry,
    required int rank,
    required Color medalColor,
    required Color nameColor,
  }) {
    final medalIcons = {
      1: Icons.emoji_events,
      2: Icons.military_tech,
      3: Icons.military_tech,
    };

    return Column(
      children: [
        Icon(medalIcons[rank] ?? Icons.circle, color: medalColor, size: 20),
        const SizedBox(height: 4),
        SizedBox(
          width: 70,
          child: Text(
            entry.accountId,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: nameColor,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${entry.hype}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: nameColor.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPodiumPillarContent({required int rank}) {
    final medalColor = rank == 2
        ? const Color(0xFFC0C0C0)
        : const Color(0xFFCD7F32);

    return Column(
      children: [
        Icon(Icons.military_tech, color: medalColor, size: 20),
        const SizedBox(height: 4),
        const SizedBox(
          width: 70,
          child: Text(
            'Empty',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}

class GameConfigurationScreen extends StatefulWidget {
  const GameConfigurationScreen({super.key});

  @override
  State<GameConfigurationScreen> createState() =>
      _GameConfigurationScreenState();
}

class _GameConfigurationScreenState extends State<GameConfigurationScreen> {
  bool _loading = true;
  int _rufusStage = 1;
  int _waterLevel = 1;
  bool _useWaterStorm = false;
  bool _saving = false;
  _GameConfigPreview _preview = _GameConfigPreview.none;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ConfigService.load();
    if (!mounted) return;
    setState(() {
      _rufusStage = config.rufusStage;
      _waterLevel = config.waterLevel;
      _useWaterStorm = config.useWaterStorm;
      _preview = _GameConfigPreview.none;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final existing = await ConfigService.load();
    final config = ConfigSettings(
      rufusStage: _rufusStage,
      waterLevel: _waterLevel,
      saveArenaPoints: existing.saveArenaPoints,
      useWaterStorm: _useWaterStorm,
      startBackendOnLaunch: existing.startBackendOnLaunch,
      disableBackendUpdateCheck: existing.disableBackendUpdateCheck,
      useDarkMode: existing.useDarkMode,
      backgroundImagePath: existing.backgroundImagePath,
      backgroundBlur: existing.backgroundBlur,
      backgroundParticlesOpacity: existing.backgroundParticlesOpacity,
      dialogBlurEnabled: existing.dialogBlurEnabled,
      startupAnimationEnabled: existing.startupAnimationEnabled,
      lastShownUpdateNotesVersion: existing.lastShownUpdateNotesVersion,
    );
    await ConfigService.save(config);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!_saving) {
        _save();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Game Configuration',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final imagePath = _gameConfigImagePath();
                final controls = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitleWithTag(
                      title: 'Rufus Week Stage',
                      tag: 'v27.11',
                    ),
                    MouseRegion(
                      onEnter: (_) => setState(
                        () => _preview = _GameConfigPreview.rufusStage,
                      ),
                      child: Slider(
                        value: _rufusStage.toDouble(),
                        min: 1,
                        max: 4,
                        divisions: 3,
                        label: 'Stage $_rufusStage',
                        onChanged: (value) => setState(() {
                          _rufusStage = value.round();
                          _preview = _GameConfigPreview.rufusStage;
                          _scheduleSave();
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _SectionTitleWithTag(
                      title: 'Water Level',
                      tag: 'v13.X',
                    ),
                    MouseRegion(
                      onEnter: (_) => setState(
                        () => _preview = _GameConfigPreview.waterLevel,
                      ),
                      child: Slider(
                        value: _waterLevel.toDouble(),
                        min: 1,
                        max: 8,
                        divisions: 7,
                        label: 'Level $_waterLevel',
                        onChanged: (value) => setState(() {
                          _waterLevel = value.round();
                          _preview = _GameConfigPreview.waterLevel;
                          _scheduleSave();
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    MouseRegion(
                      onEnter: (_) => setState(
                        () => _preview = _GameConfigPreview.waterStorm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitleWithTag(
                            title: 'Water Storm',
                            tag: 'v12.61',
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _useWaterStorm,
                            onChanged: (value) => setState(() {
                              _useWaterStorm = value;
                              _preview = _GameConfigPreview.waterStorm;
                              _scheduleSave();
                            }),
                            title: const Text(
                              'Toggle the water storm in Chapter 2 Season 2',
                            ),
                            subtitle: const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final isDefault = _preview == _GameConfigPreview.none;
                final preview = _GameConfigPreviewImage(
                  imagePath: imagePath,
                  switchKey: '${_preview.name}::$imagePath',
                  isDefault: isDefault,
                );
                final isWide = constraints.maxWidth >= 920;
                if (!isWide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [preview, const SizedBox(height: 16), controls],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: controls),
                    const SizedBox(width: 28),
                    Expanded(child: preview),
                  ],
                );
              },
            ),
    );
  }

  String _gameConfigImagePath() {
    final base = joinPath([getBackendRoot(), 'public', 'gameconfig']);
    switch (_preview) {
      case _GameConfigPreview.rufusStage:
        if (_rufusStage == 4) {
          final week4 = joinPath([base, 'week4.webp']);
          return File(week4).existsSync()
              ? week4
              : joinPath([base, 'stage4.webp']);
        }
        return joinPath([base, 'stage$_rufusStage.webp']);
      case _GameConfigPreview.waterLevel:
        return joinPath([base, 'waterlevel$_waterLevel.webp']);
      case _GameConfigPreview.waterStorm:
        return joinPath([base, 'waterstorm.webp']);
      default:
        return joinPath([base, 'default.webp']);
    }
  }
}

enum _GameConfigPreview { none, rufusStage, waterLevel, waterStorm }

class _GameConfigPreviewImage extends StatelessWidget {
  const _GameConfigPreviewImage({
    required this.imagePath,
    required this.switchKey,
    required this.isDefault,
  });

  final String imagePath;
  final String switchKey;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 520),
              reverseDuration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              layoutBuilder: (currentChild, previousChildren) {
                final currentKey = currentChild?.key;
                final filteredPrevious = previousChildren
                    .where((child) => child.key != currentKey)
                    .toList();
                return SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ...filteredPrevious,
                      if (currentChild != null) currentChild,
                    ],
                  ),
                );
              },
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: isDefault
                  ? ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                      child: Image.file(
                        File(imagePath),
                        key: ValueKey(switchKey),
                        fit: BoxFit.cover,
                      ),
                    )
                  : Image.file(
                      File(imagePath),
                      key: ValueKey(switchKey),
                      fit: BoxFit.cover,
                    ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _onSurface(context, isDark ? 0.2 : 0.1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class CurveGroup {
  const CurveGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.keywords,
    this.imageName,
    this.imagePath,
    this.isCustom = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<String> keywords;
  final String? imageName;
  final String? imagePath;
  final bool isCustom;

  bool matches(CurveEntry entry) {
    if (isCustom || (entry.isCustom && entry.groupId == id)) {
      return entry.groupId == id;
    }
    final name = entry.name.toLowerCase();
    final key = entry.key.toLowerCase();
    return keywords.any(
      (keyword) => name.contains(keyword) || key.contains(keyword),
    );
  }
}

class _CurveEntryTile extends StatelessWidget {
  const _CurveEntryTile({
    required this.entry,
    required this.enabled,
    required this.valueController,
    required this.onToggle,
    required this.onSubmit,
    this.onEdit,
    this.onDelete,
  });

  final CurveEntry entry;
  final bool enabled;
  final TextEditingController valueController;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final canEdit =
        entry.type == 'amount' ||
        (entry.type == 'static' && entry.staticValue == null);
    return FutureBuilder<Map<String, dynamic>>(
      future: Future.wait([
        CurveTableService.isCurveEnabled(entry),
        CurveTableService.getCurrentValue(entry),
      ]).then((results) => {'enabled': results[0], 'value': results[1]}),
      builder: (context, snapshot) {
        final isEnabled = snapshot.data?['enabled'] as bool? ?? false;
        final value = snapshot.data?['value'] as String?;
        if (!isEnabled) {
          if (valueController.text.isNotEmpty) {
            valueController.text = '';
          }
        } else if (value != null) {
          if (valueController.text != value) {
            valueController.text = value;
          }
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEnabled
                  ? const Color(0xFF6BE7FF).withOpacity(0.3)
                  : _onSurface(context, 0.12),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 12,
                          color: _onSurface(context, 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isEnabled && canEdit) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 140,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6BE7FF).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF6BE7FF).withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: valueController,
                      enabled: enabled,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        color: Color(0xFF6BE7FF),
                        fontWeight: FontWeight.w500,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-.]')),
                      ],
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: InputBorder.none,
                        hintText: 'Value...',
                        hintStyle: TextStyle(
                          color: Color(0xFF6BE7FF),
                          fontSize: 12,
                        ),
                      ),
                      textAlign: TextAlign.center,
                      onSubmitted: onSubmit,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Switch(value: isEnabled, onChanged: enabled ? onToggle : null),
                if (entry.isCustom) ...[
                  const SizedBox(width: 8),
                  _HoverScale(
                    child: IconButton(
                      tooltip: 'Edit Curve',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  _HoverScale(
                    child: IconButton(
                      tooltip: 'Delete Curve',
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Data Management',
      child: const DataManagementPanel(),
    );
  }
}

class DataManagementPanel extends StatefulWidget {
  const DataManagementPanel({super.key});

  @override
  State<DataManagementPanel> createState() => _DataManagementPanelState();
}

class _DataManagementPanelState extends State<DataManagementPanel> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _openBackendFolder() async {
    final backendRoot = getBackendRoot();
    if (!Directory(backendRoot).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backend folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [backendRoot], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open backend folder.')),
      );
    }
  }

  Future<void> _openExportsFolder() async {
    final exportsPath = joinPath([getBackendRoot(), 'exports']);
    if (!Directory(exportsPath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exports folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [exportsPath], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open exports folder.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Files'),
        ListTile(
          title: const Text('View Internal Files'),
          subtitle: const Text('Open the backend folder on disk'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _openBackendFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('Open Exports Folder'),
          subtitle: const Text('View exported data on disk'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _openExportsFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle(title: 'Export & Import'),
        ListTile(
          title: const Text('Export Backend Settings'),
          subtitle: const Text(
            'Write Profile, Client Settings, and DefaultGame.ini data to exports/',
          ),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => DataService.exportData(context)),
              child: const Text('Export'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('Import Backend Settings'),
          subtitle: const Text('Load data from exports/ into the backend'),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => DataService.importData(context)),
              child: const Text('Import'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('Clear Exported Data'),
          subtitle: const Text(
            'Remove Profile, Client Setting, and DefaultGame.ini data from exports/',
          ),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => DataService.clearExportedData(context)),
              child: const Text('Clear'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle(title: 'Reset'),
        ListTile(
          title: const Text('Clear Backend Data'),
          subtitle: const Text(
            'Clear All Profile, Client Setting, CurveTable, and Straight Bloom data from the backend',
          ),
          trailing: _HoverScale(
            enabled: !_busy,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy
                  ? null
                  : () => _run(() => DataService.clearBackendData(context)),
              child: const Text('Clear'),
            ),
          ),
        ),
      ],
    );
  }
}

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool _loading = true;
  List<ProfileSummary> _profiles = [];
  List<ProfilePreset> _presets = [];
  bool _hasAnyUsers = false;
  String? _selectedProfile;
  String? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profiles = await ProfileService.listProfiles();
      final presets = await ProfileService.listPresets();
      final hasAnyUsers = await ProfileService.hasAnyUsers();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _presets = presets;
        _hasAnyUsers = hasAnyUsers;
        _selectedProfile = profiles.isNotEmpty
            ? profiles.first.accountId
            : null;
        _selectedPreset = presets.isNotEmpty ? presets.first.folder : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasAnyUsers = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profiles: $error')),
      );
    }
  }

  String? _validateNewUserName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'User name is required.';
    }
    if (trimmed == '.' || trimmed == '..') {
      return 'That name is not allowed.';
    }
    if (trimmed.startsWith('.')) {
      return 'User name cannot start with a dot.';
    }
    if (RegExp(r'[<>:"/\\|?*]').hasMatch(trimmed)) {
      return 'User name contains invalid characters.';
    }
    if (trimmed.endsWith(' ') || trimmed.endsWith('.')) {
      return 'User name cannot end with a space or dot.';
    }
    if (trimmed.toLowerCase() == 'host') {
      return 'The name "host" is reserved.';
    }
    return null;
  }

  Future<_CreateUserResult?> _showCreateUserDialog() async {
    if (_presets.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No presets found.')));
      return null;
    }

    final controller = TextEditingController();
    String? selectedPreset =
        _presets.any((preset) => preset.folder == _selectedPreset)
        ? _selectedPreset
        : _presets.first.folder;
    String? errorText;

    return _showBlurDialog<_CreateUserResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create User'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'User name',
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedPreset,
                  decoration: const InputDecoration(
                    labelText: 'Preset',
                    border: OutlineInputBorder(),
                  ),
                  items: _presets
                      .map(
                        (preset) => DropdownMenuItem(
                          value: preset.folder,
                          child: _PresetLabel(
                            name: preset.name,
                            tag: preset.versionTag,
                          ),
                        ),
                      )
                      .toList(),
                  selectedItemBuilder: (context) => _presets
                      .map(
                        (preset) => _PresetLabel(
                          name: preset.name,
                          tag: preset.versionTag,
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(
                    () => selectedPreset = value ?? _presets.first.folder,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            _HoverScale(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            _HoverScale(
              child: ElevatedButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  final validationError = _validateNewUserName(name);
                  if (validationError != null) {
                    setState(() => errorText = validationError);
                    return;
                  }
                  if (await ProfileService.userExists(name)) {
                    setState(() => errorText = 'That user already exists.');
                    return;
                  }
                  final presetFolder = selectedPreset ?? _presets.first.folder;
                  Navigator.pop(
                    context,
                    _CreateUserResult(
                      accountId: name,
                      presetFolder: presetFolder,
                    ),
                  );
                },
                child: const Text('Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createUser() async {
    final result = await _showCreateUserDialog();
    if (result == null) return;
    try {
      await ProfileService.createUser(
        result.accountId,
        presetFolder: result.presetFolder,
      );
      await _load();
      if (!mounted) return;
      setState(() => _selectedProfile = result.accountId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created "${result.accountId}" with preset "${result.presetFolder}".',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create user: $error')));
    }
  }

  Future<void> _applyPreset() async {
    final profileId = _selectedProfile;
    final presetFolder = _selectedPreset;
    if (profileId == null || presetFolder == null) return;
    ProfilePreset? preset;
    for (final entry in _presets) {
      if (entry.folder == presetFolder) {
        preset = entry;
        break;
      }
    }
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selected preset no longer exists. Refresh and try again.',
          ),
        ),
      );
      return;
    }
    final confirm = await DataService._confirmDialog(
      context,
      'Replace profile_athena.json for "$profileId" with preset "${preset.displayName}"?',
    );
    if (!confirm) return;
    try {
      await ProfileService.applyPreset(profileId, presetFolder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied "${preset.displayName}" to $profileId'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to apply preset: $error')));
    }
  }

  Future<void> _applyPresetToAll() async {
    final presetFolder = _selectedPreset;
    if (presetFolder == null) return;
    ProfilePreset? preset;
    for (final entry in _presets) {
      if (entry.folder == presetFolder) {
        preset = entry;
        break;
      }
    }
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selected preset no longer exists. Refresh and try again.',
          ),
        ),
      );
      return;
    }
    final confirm = await DataService._confirmDialog(
      context,
      'Replace profile_athena.json for all users with preset "${preset.displayName}"?',
    );
    if (!confirm) return;
    try {
      final applied = await ProfileService.applyPresetToAll(presetFolder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied "${preset.displayName}" to $applied profile(s).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to apply preset to all profiles: $error'),
        ),
      );
    }
  }

  Future<void> _deleteProfile() async {
    final profileId = _selectedProfile;
    if (profileId == null) return;

    // Check which folders exist
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles', profileId]),
    );
    final clientSettingsDir = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings', profileId]),
    );
    final profileFolderExists = await profilesDir.exists();
    final clientSettingsFolderExists = await clientSettingsDir.exists();

    bool deleteProfile = profileFolderExists;
    bool deleteClientSettings = clientSettingsFolderExists;

    final result = await _showBlurDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) => AlertDialog(
          title: Text('Delete profile "$profileId"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select what to delete:'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteProfile,
                onChanged: profileFolderExists
                    ? (value) => setState(() => deleteProfile = value ?? true)
                    : null,
                title: const Text('User Profile'),
                subtitle: const Text(
                  'profile_athena.json and related profile data',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: deleteClientSettings,
                onChanged: clientSettingsFolderExists
                    ? (value) =>
                          setState(() => deleteClientSettings = value ?? true)
                    : null,
                title: const Text('ClientSettings'),
                subtitle: const Text('Game settings and preferences'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(stateContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: (deleteProfile || deleteClientSettings)
                  ? () => Navigator.of(stateContext).pop({
                      'profile': deleteProfile,
                      'settings': deleteClientSettings,
                    })
                  : null,
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await ProfileService.deleteProfile(
        profileId,
        deleteProfile: result['profile']!,
        deleteClientSettings: result['settings']!,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted profile "$profileId".')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete profile: $error')),
      );
    }
  }

  Future<void> _deleteAllProfiles() async {
    bool deleteProfiles = true;
    bool deleteClientSettings = true;

    final result = await _showBlurDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) => AlertDialog(
          title: const Text('Delete ALL profiles?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select what to delete for all users:'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteProfiles,
                onChanged: (value) =>
                    setState(() => deleteProfiles = value ?? true),
                title: const Text('User Profiles'),
                subtitle: const Text(
                  'All profile_athena.json files and related data',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: deleteClientSettings,
                onChanged: (value) =>
                    setState(() => deleteClientSettings = value ?? true),
                title: const Text('ClientSettings'),
                subtitle: const Text('All game settings and preferences'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(stateContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: (deleteProfiles || deleteClientSettings)
                  ? () => Navigator.of(stateContext).pop({
                      'profiles': deleteProfiles,
                      'settings': deleteClientSettings,
                    })
                  : null,
              child: const Text(
                'Delete All',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      await ProfileService.deleteAllProfiles(
        deleteProfiles: result['profiles']!,
        deleteClientSettings: result['settings']!,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted all profiles.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete all profiles: $error')),
      );
    }
  }

  Future<void> _openClientSettingsFolder(String accountId) async {
    final clientSettingsPath = joinPath([
      getBackendRoot(),
      'static',
      'ClientSettings',
      accountId,
    ]);
    if (!Directory(clientSettingsPath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ClientSettings folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [clientSettingsPath], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open Client Settings folder.')),
      );
    }
  }

  Future<void> _openProfileFolder(String accountId) async {
    final profilePath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
    ]);
    if (!Directory(profilePath).existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile folder not found.')),
      );
      return;
    }
    try {
      await Process.start('explorer', [profilePath], runInShell: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open Profile folder.')),
      );
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDir = Directory(
          joinPath([
            destination.path,
            entity.path.split(Platform.pathSeparator).last,
          ]),
        );
        await newDir.create(recursive: true);
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        final newFile = File(
          joinPath([
            destination.path,
            entity.path.split(Platform.pathSeparator).last,
          ]),
        );
        await entity.copy(newFile.path);
      }
    }
  }

  Future<void> _exportUserSettings(String accountId) async {
    bool exportProfile = true;
    bool exportClientSettings = true;

    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles', accountId]),
    );
    final clientSettingsDir = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings', accountId]),
    );
    final profileFolderExists = await profilesDir.exists();
    final clientSettingsFolderExists = await clientSettingsDir.exists();

    if (!profileFolderExists && !clientSettingsFolderExists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No profile or client settings found to export.'),
        ),
      );
      return;
    }

    final result = await _showBlurDialog<Map<String, bool>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stateContext, setState) => AlertDialog(
          title: Text('Export settings for "$accountId"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select what to export:'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: exportProfile,
                onChanged: profileFolderExists
                    ? (value) => setState(() => exportProfile = value ?? true)
                    : null,
                title: const Text('User Profile'),
                subtitle: const Text(
                  'profile_athena.json and related profile data',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: exportClientSettings,
                onChanged: clientSettingsFolderExists
                    ? (value) =>
                          setState(() => exportClientSettings = value ?? true)
                    : null,
                title: const Text('ClientSettings'),
                subtitle: const Text('Game settings and preferences'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(stateContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: (exportProfile || exportClientSettings)
                  ? () => Navigator.of(stateContext).pop({
                      'profile': exportProfile,
                      'settings': exportClientSettings,
                    })
                  : null,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Export'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    try {
      final backendRoot = getBackendRoot();
      final zipFileName =
          '${accountId}_export_${DateTime.now().millisecondsSinceEpoch}.zip';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Export Zip',
        fileName: zipFileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (savePath == null) return;

      final tempDir = Directory.systemTemp.createTempSync('atlas_export_');
      final exportDir = Directory(joinPath([tempDir.path, accountId]));
      await exportDir.create();

      if (result['profile']!) {
        final profileSource = Directory(
          joinPath([backendRoot, 'static', 'profiles', accountId]),
        );
        final profileDest = Directory(
          joinPath([exportDir.path, 'profiles', accountId]),
        );
        await profileDest.create(recursive: true);
        await _copyDirectory(profileSource, profileDest);
      }

      if (result['settings']!) {
        final settingsSource = Directory(
          joinPath([backendRoot, 'static', 'ClientSettings', accountId]),
        );
        final settingsDest = Directory(
          joinPath([exportDir.path, 'ClientSettings', accountId]),
        );
        await settingsDest.create(recursive: true);
        await _copyDirectory(settingsSource, settingsDest);
      }

      final zipPath = savePath;

      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Add-Type -AssemblyName System.IO.Compression.FileSystem; '
            '[System.IO.Compression.ZipFile]::CreateFromDirectory(\'${exportDir.path}\', \'$zipPath\')',
      ]);

      await tempDir.delete(recursive: true);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exported: $zipPath')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export settings: $error')),
      );
    }
  }

  Future<void> _importUserSettingsZip() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import User Settings (zip)',
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked == null || picked.files.single.path == null) return;
    final zipPath = picked.files.single.path!;

    try {
      final backendRoot = getBackendRoot();
      final input = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeBuffer(input);

      final matched = <String>{};
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = file.name.replaceAll('\\', '/');
        final segments = name.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.length < 3) continue;

        String? accountId;
        String? category;
        int relativeStart = 0;

        if (segments[0] == 'profiles' || segments[0] == 'ClientSettings') {
          category = segments[0];
          accountId = segments[1];
          relativeStart = 2;
        } else if (segments.length >= 4 &&
            (segments[1] == 'profiles' || segments[1] == 'ClientSettings')) {
          accountId = segments[0];
          category = segments[1];
          if (segments[2] != accountId) continue;
          relativeStart = 3;
        }

        if (accountId == null || category == null) continue;

        String? baseDir;
        if (category == 'profiles') {
          baseDir = joinPath([backendRoot, 'static', 'profiles', accountId]);
        } else if (category == 'ClientSettings') {
          baseDir = joinPath([
            backendRoot,
            'static',
            'ClientSettings',
            accountId,
          ]);
        } else {
          continue;
        }

        final relative = segments.sublist(relativeStart).join('/');
        if (relative.isEmpty) continue;
        final outPath = joinPath([baseDir, relative]);
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        final data = file.content as List<int>;
        await outFile.writeAsBytes(data, flush: true);
        matched.add(accountId);
      }

      if (!mounted) return;
      if (matched.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No valid profiles found in zip.')),
        );
        return;
      }

      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${matched.length} profile(s).')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to import zip: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final presetItems = {
      for (final preset in _presets) preset.folder: preset,
    }.values.toList();
    final profileItems = {
      for (final profile in _profiles) profile.accountId: profile,
    }.values.toList();
    final presetValue = presetItems.any((p) => p.folder == _selectedPreset)
        ? _selectedPreset
        : null;
    final profileValue =
        profileItems.any((p) => p.accountId == _selectedProfile)
        ? _selectedProfile
        : null;
    return _BaseScreen(
      title: 'Users',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HoverScale(
            enabled: !_loading,
            child: IconButton(
              tooltip: 'Create user',
              onPressed: _loading ? null : _createUser,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ),
          const SizedBox(width: 8),
          _HoverScale(
            enabled: !_loading,
            child: IconButton(
              tooltip: 'Refresh users',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
        ],
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(title: 'Users (${_profiles.length})'),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: _profiles.isEmpty
                              ? const Center(child: Text('No users found.'))
                              : ListView.separated(
                                  itemCount: _profiles.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    color: Colors.white12,
                                  ),
                                  itemBuilder: (context, index) {
                                    final profile = _profiles[index];
                                    final selected =
                                        profile.accountId == _selectedProfile;
                                    return GestureDetector(
                                      onSecondaryTapDown: (details) {
                                        showMenu(
                                          context: context,
                                          position: RelativeRect.fromLTRB(
                                            details.globalPosition.dx,
                                            details.globalPosition.dy,
                                            details.globalPosition.dx,
                                            details.globalPosition.dy,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          items: [
                                            PopupMenuItem(
                                              child: const Text(
                                                'Open Client Settings Folder',
                                              ),
                                              onTap: () =>
                                                  _openClientSettingsFolder(
                                                    profile.accountId,
                                                  ),
                                            ),
                                            PopupMenuItem(
                                              child: const Text(
                                                'Open Profile Folder',
                                              ),
                                              onTap: () => _openProfileFolder(
                                                profile.accountId,
                                              ),
                                            ),
                                            PopupMenuItem(
                                              child: const Text(
                                                'Export User Settings',
                                              ),
                                              onTap: () => _exportUserSettings(
                                                profile.accountId,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                      child: ListTile(
                                        selected: selected,
                                        selectedTileColor: Colors.white10,
                                        title: Text(profile.accountId),
                                        subtitle: Text(
                                          profile.hasAthena
                                              ? 'profile_athena.json found'
                                              : 'Missing profile_athena.json',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.secondary,
                                          ),
                                        ),
                                        trailing: selected
                                            ? const Icon(
                                                Icons.check_circle,
                                                color: Colors.greenAccent,
                                              )
                                            : null,
                                        onTap: () => setState(
                                          () => _selectedProfile =
                                              profile.accountId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.flash_on_rounded,
                              color: const Color(0xFF7EE081),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Level and Currency',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            _HoverScale(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(
                                    context,
                                  ).push(_buildRoute(const UserValuesScreen()));
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFF7EE081,
                                  ).withOpacity(0.15),
                                  foregroundColor: const Color(0xFF7EE081),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.edit, size: 18),
                                label: const Text('Edit User Values'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _SectionTitle(title: 'Custom Cosmetic Presets'),
                          const SizedBox(width: 8),
                          _HoverScale(
                            scale: 1.08,
                            child: Tooltip(
                              message: 'Info',
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      _showCustomCosmeticPresetsInfoDialog(
                                        context,
                                      ),
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _onSurface(context, 0.06),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: _onSurface(context, 0.14),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.help_outline_rounded,
                                      size: 18,
                                      color: _onSurface(context, 0.78),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: presetValue,
                        decoration: InputDecoration(
                          labelText: 'Preset',
                          border: const OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.secondary,
                              width: 1.6,
                            ),
                          ),
                        ),
                        items: presetItems
                            .map(
                              (preset) => DropdownMenuItem(
                                value: preset.folder,
                                child: _PresetLabel(
                                  name: preset.name,
                                  tag: preset.versionTag,
                                ),
                              ),
                            )
                            .toList(),
                        selectedItemBuilder: (context) => presetItems
                            .map(
                              (preset) => _PresetLabel(
                                name: preset.name,
                                tag: preset.versionTag,
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedPreset = value),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: profileValue,
                        decoration: InputDecoration(
                          labelText: 'User',
                          border: const OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.secondary,
                              width: 1.6,
                            ),
                          ),
                        ),
                        items: profileItems
                            .map(
                              (profile) => DropdownMenuItem(
                                value: profile.accountId,
                                child: Text(profile.accountId),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedProfile = value),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _HoverScale(
                              enabled:
                                  _selectedProfile != null &&
                                  _selectedPreset != null,
                              child: ElevatedButton.icon(
                                onPressed:
                                    (_selectedProfile != null &&
                                        _selectedPreset != null)
                                    ? _applyPreset
                                    : null,
                                icon: const Icon(Icons.auto_fix_high),
                                label: const Text('Apply preset to user'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _HoverScale(
                              enabled:
                                  _selectedPreset != null &&
                                  _profiles.isNotEmpty,
                              child: ElevatedButton.icon(
                                onPressed:
                                    (_selectedPreset != null &&
                                        _profiles.isNotEmpty)
                                    ? _applyPresetToAll
                                    : null,
                                icon: const Icon(Icons.group_rounded),
                                label: const Text('Apply preset to all users'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This replaces profile_athena.json for the selected user.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _onSurface(context, 0.6),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _HoverScale(
                              enabled: _selectedProfile != null,
                              child: OutlinedButton.icon(
                                onPressed: _selectedProfile != null
                                    ? _deleteProfile
                                    : null,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                label: const Text('Delete user'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _HoverScale(
                              enabled: _hasAnyUsers,
                              child: OutlinedButton.icon(
                                onPressed: _hasAnyUsers
                                    ? _deleteAllProfiles
                                    : null,
                                icon: const Icon(
                                  Icons.delete_sweep,
                                  color: Colors.redAccent,
                                ),
                                label: const Text('Delete all users'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Permanently removes user data and game settings.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _onSurface(context, 0.6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _HoverScale(
                              enabled: !_loading && _selectedProfile != null,
                              child: OutlinedButton.icon(
                                onPressed:
                                    (_loading || _selectedProfile == null)
                                    ? null
                                    : () => _exportUserSettings(
                                        _selectedProfile!,
                                      ),
                                icon: const Icon(Icons.download_rounded),
                                label: const Text('Export User'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _HoverScale(
                              enabled: !_loading,
                              child: OutlinedButton.icon(
                                onPressed: _loading
                                    ? null
                                    : _importUserSettingsZip,
                                icon: const Icon(Icons.file_upload_outlined),
                                label: const Text('Import User (Select ZIP)'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Export or import a user into the backend.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _onSurface(context, 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class UserValuesScreen extends StatefulWidget {
  const UserValuesScreen({super.key});

  @override
  State<UserValuesScreen> createState() => _UserValuesScreenState();
}

class _UserValuesScreenState extends State<UserValuesScreen> {
  bool _loading = true;
  List<ProfileSummary> _profiles = [];
  String? _selectedProfile;

  final TextEditingController _levelController = TextEditingController();
  final TextEditingController _vbucksController = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _levelController.dispose();
    _vbucksController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profiles = await ProfileService.listProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _loading = false;
      if (_profiles.isNotEmpty && _selectedProfile == null) {
        _selectedProfile = _profiles.first.accountId;
        unawaited(_loadUserValues());
      }
    });
  }

  Future<void> _loadUserValues() async {
    if (_selectedProfile == null) return;

    final values = await UserValuesService.loadUserValues(_selectedProfile!);
    if (!mounted) return;

    setState(() {
      // Use level as the single source, but fall back to accountLevel if level is 1
      final displayLevel = values.level > 1
          ? values.level
          : values.accountLevel;
      _levelController.text = displayLevel.toString();
      _vbucksController.text = values.vbucks.toString();
    });
  }

  Future<void> _saveUserValues() async {
    if (_selectedProfile == null || _saving) return;

    setState(() => _saving = true);

    final level = int.tryParse(_levelController.text) ?? 1;
    final vbucks = int.tryParse(_vbucksController.text) ?? 0;

    // Use the same level value for all three level fields
    await UserValuesService.saveUserValues(
      _selectedProfile!,
      UserValues(
        level: level,
        bookLevel: level,
        accountLevel: level,
        vbucks: vbucks,
      ),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User values saved successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? const Color(0xFF1A1F2E).withOpacity(0.5)
        : Colors.white.withOpacity(0.5);
    final borderColor = _onSurface(context, 0.12);

    return _BaseScreen(
      title: 'Edit User Values',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_off,
                    size: 64,
                    color: _onSurface(context, 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No users found',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a user first from the Users menu',
                    style: TextStyle(color: _onSurface(context, 0.6)),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(title: 'Select User'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedProfile,
                      decoration: const InputDecoration(
                        labelText: 'User',
                        border: OutlineInputBorder(),
                      ),
                      items: _profiles.map((profile) {
                        return DropdownMenuItem(
                          value: profile.accountId,
                          child: Text(profile.accountId),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedProfile = value);
                          unawaited(_loadUserValues());
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  const _SectionTitle(title: 'Level Settings'),
                  const SizedBox(height: 12),
                  _buildValueCard(
                    context,
                    cardColor,
                    borderColor,
                    icon: Icons.trending_up,
                    title: 'Level',
                    description:
                        'Sets level, book_level, and accountLevel to the same value',
                    imagePath: 'public/items/levels.webp',
                    fields: [
                      _ValueField(
                        label: 'Level',
                        controller: _levelController,
                        hint: 'e.g., 100 or 999',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  const _SectionTitle(title: 'Currency Settings'),
                  const SizedBox(height: 12),
                  _buildValueCard(
                    context,
                    cardColor,
                    borderColor,
                    icon: Icons.monetization_on,
                    title: 'V-Bucks',
                    imagePath: 'public/items/VBucks.webp',
                    fields: [
                      _ValueField(
                        label: 'V-Bucks Amount',
                        controller: _vbucksController,
                        hint: 'Total V-Bucks (e.g., 13500)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  Center(
                    child: _HoverScale(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _saveUserValues,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'Saving...' : 'Save Changes'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildValueCard(
    BuildContext context,
    Color cardColor,
    Color borderColor, {
    required IconData icon,
    required String title,
    String? description,
    required String imagePath,
    required List<_ValueField> fields,
  }) {
    final fullImagePath = joinPath([getBackendRoot(), imagePath]);
    final imageFile = File(fullImagePath);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageFile.existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                imageFile,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _onSurface(context, 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 40, color: _onSurface(context, 0.3)),
            ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _onSurface(context, 0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ...fields.map(
                  (field) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: field.controller,
                      decoration: InputDecoration(
                        labelText: field.label,
                        hintText: field.hint,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueField {
  const _ValueField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
}

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logStore = LogStore.instance;
    return AnimatedBuilder(
      animation: logStore,
      builder: (context, _) {
        final allLogsText = logStore.allLogs.join('\n');
        return _BaseScreen(
          title: 'Logs',
          trailing: _HoverScale(
            child: IconButton(
              tooltip: 'Copy all logs',
              onPressed: allLogsText.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: allLogsText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logs copied to clipboard'),
                        ),
                      );
                    },
              icon: const Icon(Icons.copy_all_rounded),
            ),
          ),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: SelectableText(
                  allLogsText,
                  textAlign: TextAlign.left,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _onSurface(context, 0.7),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BaseScreen extends StatelessWidget {
  const _BaseScreen({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AtlasBackground(showParticles: false),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HoverScale(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Spacer(),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: GlassPanel(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _SectionTitleWithTag extends StatelessWidget {
  const _SectionTitleWithTag({required this.title, required this.tag});

  final String title;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withOpacity(0.45)),
          ),
          child: Text(
            tag,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PresetLabel extends StatelessWidget {
  const _PresetLabel({required this.name, this.tag});

  final String name;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Text(name, overflow: TextOverflow.ellipsis),
        ),
        if (tag != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withOpacity(0.45)),
            ),
            child: Text(
              tag!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ArenaEntry {
  const ArenaEntry({required this.accountId, required this.hype});

  final String accountId;
  final int hype;
}

class ArenaService {
  static Future<List<ArenaEntry>> loadLeaderboard() async {
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    if (!await profilesDir.exists()) return [];
    final entries = <ArenaEntry>[];
    await for (final entity in profilesDir.list()) {
      if (entity is Directory) {
        final profilePath = File(
          joinPath([entity.path, 'profile_athena.json']),
        );
        if (await profilePath.exists()) {
          try {
            final data =
                jsonDecode(await profilePath.readAsString())
                    as Map<String, dynamic>;
            final stats =
                (data['stats'] as Map<String, dynamic>?)?['attributes']
                    as Map<String, dynamic>?;
            final hype = stats?['arena_hype'] ?? 0;
            final folderName = entity.path.split(Platform.pathSeparator).last;
            entries.add(
              ArenaEntry(
                accountId: folderName,
                hype: hype is int ? hype : int.tryParse(hype.toString()) ?? 0,
              ),
            );
          } catch (_) {}
        }
      }
    }
    entries.sort((a, b) => b.hype.compareTo(a.hype));
    return entries;
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _tabIndex = 0;
  bool _loading = true;
  bool _startBackendOnLaunch = false;
  bool _disableBackendUpdateCheck = false;
  bool _useDarkMode = true;
  String _backgroundImagePath = '';
  double _backgroundBlur = 15;
  double _backgroundParticlesOpacity = 1.0;
  bool _dialogBlurEnabled = true;
  bool _startupAnimationEnabled = true;
  late final VoidCallback _backgroundPathListener;
  late final VoidCallback _backgroundBlurListener;

  @override
  void initState() {
    super.initState();
    _load();
    _backgroundPathListener = () {
      if (!mounted) return;
      setState(() => _backgroundImagePath = appBackgroundPath.value);
    };
    _backgroundBlurListener = () {
      if (!mounted) return;
      setState(() => _backgroundBlur = appBackgroundBlur.value);
    };
    appBackgroundPath.addListener(_backgroundPathListener);
    appBackgroundBlur.addListener(_backgroundBlurListener);
  }

  @override
  void dispose() {
    appBackgroundPath.removeListener(_backgroundPathListener);
    appBackgroundBlur.removeListener(_backgroundBlurListener);
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ConfigService.load();
    if (!mounted) return;
    setState(() {
      _startBackendOnLaunch = config.startBackendOnLaunch;
      _disableBackendUpdateCheck = config.disableBackendUpdateCheck;
      _useDarkMode = config.useDarkMode;
      _backgroundImagePath = config.backgroundImagePath;
      _backgroundBlur = config.backgroundBlur;
      _backgroundParticlesOpacity = config.backgroundParticlesOpacity;
      _dialogBlurEnabled = config.dialogBlurEnabled;
      _startupAnimationEnabled = config.startupAnimationEnabled;
      _loading = false;
    });
  }

  Future<void> _updateTheme(bool value) async {
    setState(() => _useDarkMode = value);
    appThemeMode.value = value ? ThemeMode.dark : ThemeMode.light;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(useDarkMode: value));
  }

  Future<void> _pickBackgroundImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => _backgroundImagePath = path);
    appBackgroundPath.value = path;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundImagePath: path));
  }

  Future<void> _clearBackgroundImage() async {
    setState(() => _backgroundImagePath = '');
    appBackgroundPath.value = '';
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundImagePath: ''));
  }

  Future<void> _updateBackgroundBlur(double value) async {
    setState(() => _backgroundBlur = value);
    appBackgroundBlur.value = value;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(backgroundBlur: value));
  }

  Future<void> _updateBackgroundParticlesOpacity(double value) async {
    final clamped = value.clamp(0.0, 2.0).toDouble();
    setState(() => _backgroundParticlesOpacity = clamped);
    appBackgroundParticlesOpacity.value = clamped;
    final existing = await ConfigService.load();
    await ConfigService.save(
      existing.copyWith(backgroundParticlesOpacity: clamped),
    );
  }

  Future<void> _updateDialogBlur(bool value) async {
    setState(() => _dialogBlurEnabled = value);
    appDialogBlurEnabled.value = value;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(dialogBlurEnabled: value));
  }

  Future<void> _updateStartupAnimationEnabled(bool value) async {
    setState(() => _startupAnimationEnabled = value);
    appStartupAnimationEnabled.value = value;
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(startupAnimationEnabled: value));
  }

  Future<void> _updateStartOnLaunch(bool value) async {
    setState(() => _startBackendOnLaunch = value);
    final existing = await ConfigService.load();
    await ConfigService.save(existing.copyWith(startBackendOnLaunch: value));
  }

  Future<void> _updateDisableBackendUpdateCheck(bool value) async {
    setState(() => _disableBackendUpdateCheck = value);
    final existing = await ConfigService.load();
    await ConfigService.save(
      existing.copyWith(disableBackendUpdateCheck: value),
    );
  }

  String _backgroundSubtitle() {
    if (_backgroundImagePath.isEmpty) {
      return 'Default background';
    }
    final resolved = _resolveBackgroundPath(_backgroundImagePath);
    if (resolved == null) {
      return 'Missing image: $_backgroundImagePath';
    }
    return _backgroundImagePath;
  }

  @override
  Widget build(BuildContext context) {
    return _BaseScreen(
      title: 'Settings',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  child: ListView(
                    children: [
                      _SettingsTab(
                        label: 'Appearance',
                        icon: Icons.palette_outlined,
                        selected: _tabIndex == 0,
                        onTap: () => setState(() => _tabIndex = 0),
                      ),
                      _SettingsTab(
                        label: 'Data Management',
                        icon: Icons.storage_rounded,
                        selected: _tabIndex == 1,
                        onTap: () => setState(() => _tabIndex = 1),
                      ),
                      _SettingsTab(
                        label: 'Startup',
                        icon: Icons.power_settings_new_rounded,
                        selected: _tabIndex == 2,
                        onTap: () => setState(() => _tabIndex = 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topLeft,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    child: _buildTabContent(context),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    final title = switch (_tabIndex) {
      0 => 'Appearance',
      1 => 'Data Management',
      2 => 'Startup',
      _ => 'Settings',
    };
    switch (_tabIndex) {
      case 0:
        return Column(
          key: const ValueKey('appearance'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(title: title),
            const SizedBox(height: 16),
             SwitchListTile(
               value: _useDarkMode,
               onChanged: _updateTheme,
               title: const Text('Dark mode'),
               subtitle: const Text('Toggle between dark and light themes.'),
             ),
             const SizedBox(height: 8),
             SwitchListTile(
                 value: _dialogBlurEnabled,
                 onChanged: _updateDialogBlur,
                 title: const Text('Popup background blur'),
               subtitle: const Text('Blur the background behind popups.'),
             ),
             const SizedBox(height: 8),
             SwitchListTile(
               value: _startupAnimationEnabled,
               onChanged: _updateStartupAnimationEnabled,
               title: const Text('Startup animation'),
               subtitle: const Text(
                 'Play the intro animation when ATLAS Backend launches.',
               ),
             ),
             const SizedBox(height: 12),
             ListTile(
               title: const Text('Background image'),
               subtitle: Text(
                _backgroundSubtitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HoverScale(
                    enabled: _backgroundImagePath.isNotEmpty,
                    child: TextButton(
                      onPressed: _backgroundImagePath.isEmpty
                          ? null
                          : _clearBackgroundImage,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _HoverScale(
                    child: ElevatedButton(
                      onPressed: _pickBackgroundImage,
                      child: const Text('Choose image'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Background blur (${_backgroundBlur.toStringAsFixed(0)})'),
            const SizedBox(height: 6),
             LayoutBuilder(
               builder: (context, constraints) {
                const min = 0.0;
                const max = 30.0;
                const defaultBlur = 15.0;
                final trackWidth = constraints.maxWidth;
                final normalized = (defaultBlur - min) / (max - min);
                final dotX = trackWidth * normalized;
                return SizedBox(
                  height: 36,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Slider(
                        value: _backgroundBlur,
                        min: min,
                        max: max,
                        divisions: 30,
                        onChanged: _updateBackgroundBlur,
                      ),
                      Positioned(
                        left: dotX - 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Background particles (${(_backgroundParticlesOpacity * 100).round()}%)',
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                const min = 0.0;
                const max = 2.0;
                const defaultOpacity = 1.0; // 100%
                final trackWidth = constraints.maxWidth;
                final normalized = (defaultOpacity - min) / (max - min);
                final dotX = trackWidth * normalized;
                return SizedBox(
                  height: 36,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Slider(
                        value: _backgroundParticlesOpacity,
                        min: min,
                        max: max,
                        divisions: 20,
                        label: '${(_backgroundParticlesOpacity * 100).round()}%',
                        onChanged: _updateBackgroundParticlesOpacity,
                      ),
                      Positioned(
                        left: dotX - 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      case 1:
        return SingleChildScrollView(
          key: const ValueKey('data'),
          primary: false,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle(title: title),
              const SizedBox(height: 16),
              const DataManagementPanel(),
            ],
          ),
        );
      case 2:
        return Column(
          key: const ValueKey('startup'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(title: title),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _startBackendOnLaunch,
              onChanged: _updateStartOnLaunch,
              title: const Text('Start backend on launch'),
              subtitle: const Text(
                'Automatically start the backend when the GUI opens.',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _disableBackendUpdateCheck,
              onChanged: _updateDisableBackendUpdateCheck,
              title: const Text('Disable Update Checks'),
              subtitle: const Text(
                'Skip update checks when launching the backend.',
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.secondary
        : _onSurface(context, 0.7);
    return ListTile(
      selected: selected,
      selectedTileColor: Colors.white10,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
      ),
      onTap: onTap,
    );
  }
}

class ProfileSummary {
  const ProfileSummary({required this.accountId, required this.hasAthena});

  final String accountId;
  final bool hasAthena;
}

class ProfilePreset {
  const ProfilePreset({
    required this.name,
    required this.folder,
    this.versionTag,
  });

  final String name;
  final String folder;
  final String? versionTag;

  String get displayName =>
      versionTag == null ? name : '$name (${versionTag!})';
}

class _CreateUserResult {
  const _CreateUserResult({
    required this.accountId,
    required this.presetFolder,
  });

  final String accountId;
  final String presetFolder;
}

class UserValues {
  const UserValues({
    required this.level,
    required this.bookLevel,
    required this.accountLevel,
    required this.vbucks,
  });

  final int level;
  final int bookLevel;
  final int accountLevel;
  final int vbucks;
}

class UserValuesService {
  static Future<UserValues> loadUserValues(String accountId) async {
    int level = 1;
    int bookLevel = 1;
    int accountLevel = 1;
    int vbucks = 0;

    final athenaPath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
      'profile_athena.json',
    ]);
    final athenaFile = File(athenaPath);
    if (await athenaFile.exists()) {
      try {
        final content = await athenaFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        // Navigate to stats.attributes where the level data is stored
        final stats = json['stats'] as Map<String, dynamic>?;
        if (stats != null) {
          final attributes = stats['attributes'] as Map<String, dynamic>?;
          if (attributes != null) {
            // Read actual values, with fallbacks
            if (attributes.containsKey('level')) {
              level = (attributes['level'] is int)
                  ? attributes['level'] as int
                  : int.tryParse(attributes['level'].toString()) ?? 1;
            }
            if (attributes.containsKey('book_level')) {
              bookLevel = (attributes['book_level'] is int)
                  ? attributes['book_level'] as int
                  : int.tryParse(attributes['book_level'].toString()) ?? 1;
            }
            if (attributes.containsKey('accountLevel')) {
              accountLevel = (attributes['accountLevel'] is int)
                  ? attributes['accountLevel'] as int
                  : int.tryParse(attributes['accountLevel'].toString()) ?? 1;
            }
          }
        }
      } catch (e) {
        print('Error reading athena profile: $e');
      }
    }

    final commonCorePath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
      'profile_common_core.json',
    ]);
    final commonCoreFile = File(commonCorePath);
    if (await commonCoreFile.exists()) {
      try {
        final content = await commonCoreFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final items = json['items'] as Map<String, dynamic>?;
        if (items != null) {
          final mtxPurchased =
              items['Currency:MtxPurchased'] as Map<String, dynamic>?;
          if (mtxPurchased != null && mtxPurchased.containsKey('quantity')) {
            vbucks = (mtxPurchased['quantity'] is int)
                ? mtxPurchased['quantity'] as int
                : int.tryParse(mtxPurchased['quantity'].toString()) ?? 0;
          }
        }
      } catch (e) {
        print('Error reading common_core profile: $e');
      }
    }

    return UserValues(
      level: level,
      bookLevel: bookLevel,
      accountLevel: accountLevel,
      vbucks: vbucks,
    );
  }

  static Future<void> saveUserValues(
    String accountId,
    UserValues values,
  ) async {
    final athenaPath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
      'profile_athena.json',
    ]);
    final athenaFile = File(athenaPath);
    if (await athenaFile.exists()) {
      try {
        final content = await athenaFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        // Navigate to stats.attributes to set the level values
        final stats = json['stats'] as Map<String, dynamic>?;
        if (stats != null) {
          final attributes = stats['attributes'] as Map<String, dynamic>?;
          if (attributes != null) {
            attributes['level'] = values.level;
            attributes['book_level'] = values.bookLevel;
            attributes['accountLevel'] = values.accountLevel;

            await athenaFile.writeAsString(
              const JsonEncoder.withIndent('  ').convert(json),
            );
          }
        }
      } catch (e) {
        print('Error saving athena profile: $e');
      }
    }

    final commonCorePath = joinPath([
      getBackendRoot(),
      'static',
      'profiles',
      accountId,
      'profile_common_core.json',
    ]);
    final commonCoreFile = File(commonCorePath);
    if (await commonCoreFile.exists()) {
      try {
        final content = await commonCoreFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final items = json['items'] as Map<String, dynamic>?;
        if (items != null) {
          if (!items.containsKey('Currency:MtxPurchased')) {
            items['Currency:MtxPurchased'] = {
              'templateId': 'Currency:MtxPurchased',
              'attributes': {'platform': 'EpicPC'},
              'quantity': values.vbucks,
            };
          } else {
            final mtxPurchased =
                items['Currency:MtxPurchased'] as Map<String, dynamic>;
            mtxPurchased['quantity'] = values.vbucks;
          }
          await commonCoreFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(json),
          );
        }
      } catch (_) {}
    }
  }
}

class ProfileService {
  static const String _profileTemplateBackupDirName = '.defaults';
  static const String _hostAccountId = 'host';
  static const Set<String> _profileTemplateFiles = {
    'profile_campaign.json',
    'profile_collections.json',
    'profile_common_core.json',
    'profile_common_public.json',
    'profile_creative.json',
    'profile_metadata.json',
    'profile_outpost0.json',
    'profile_profile0.json',
    'profile_theater0.json',
  };

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].trim().isNotEmpty) return parts[i];
    }
    return path;
  }

  static bool _isHostAccountId(String accountId) {
    return accountId.trim().toLowerCase() == _hostAccountId;
  }

  static Future<bool> userExists(String accountId) async {
    final trimmed = accountId.trim();
    if (trimmed.isEmpty) return false;
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles', trimmed]),
    );
    if (await profilesDir.exists()) return true;
    final clientSettingsDir = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings', trimmed]),
    );
    return await clientSettingsDir.exists();
  }

  static Future<void> createUser(
    String accountId, {
    required String presetFolder,
  }) async {
    final trimmed = accountId.trim();
    if (trimmed.isEmpty) {
      throw Exception('User name is required.');
    }
    if (_isHostAccountId(trimmed)) {
      throw Exception('The name "host" is reserved.');
    }
    if (await userExists(trimmed)) {
      throw Exception('User already exists.');
    }
    final presetPath = File(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
        presetFolder,
        'profile_athena.json',
      ]),
    );
    if (!await presetPath.exists()) {
      throw Exception('Preset profile not found.');
    }
    final profilesRoot = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    if (!await profilesRoot.exists()) {
      throw Exception('Profiles directory not found.');
    }
    final profileDir = Directory(joinPath([profilesRoot.path, trimmed]));
    await profileDir.create(recursive: true);
    for (final templateName in _profileTemplateFiles) {
      final templatePath = File(joinPath([profilesRoot.path, templateName]));
      if (await templatePath.exists()) {
        await templatePath.copy(joinPath([profileDir.path, templateName]));
      }
    }
    final profilePath = File(
      joinPath([profileDir.path, 'profile_athena.json']),
    );
    await presetPath.copy(profilePath.path);
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
  }

  static Future<List<ProfileSummary>> listProfiles() async {
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    final clientSettingsRoot = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings']),
    );

    final profiles = <ProfileSummary>[];
    final seenAccountIds = <String>{};

    // Check profiles directory
    if (await profilesDir.exists()) {
      await for (final entity in profilesDir.list(recursive: false)) {
        if (entity is! Directory) continue;
        final accountId = _basename(entity.path);
        if (accountId.trim().isEmpty) continue;
        if (accountId == _profileTemplateBackupDirName ||
            accountId.startsWith('.')) {
          continue;
        }
        if (_isHostAccountId(accountId)) {
          continue;
        }
        final profilePath = File(
          joinPath([entity.path, 'profile_athena.json']),
        );
        profiles.add(
          ProfileSummary(
            accountId: accountId,
            hasAthena: await profilePath.exists(),
          ),
        );
        seenAccountIds.add(accountId);
      }
    }

    // Also check ClientSettings directory for accounts not in profiles
    if (await clientSettingsRoot.exists()) {
      await for (final entity in clientSettingsRoot.list(recursive: false)) {
        if (entity is! Directory) continue;
        final accountId = _basename(entity.path);
        if (accountId.trim().isEmpty) continue;
        if (accountId.toLowerCase() == 'config' ||
            accountId == _profileTemplateBackupDirName ||
            accountId.startsWith('.')) {
          continue;
        }
        if (_isHostAccountId(accountId)) {
          continue;
        }

        // Only add if not already added from profiles directory
        if (!seenAccountIds.contains(accountId)) {
          profiles.add(ProfileSummary(accountId: accountId, hasAthena: false));
          seenAccountIds.add(accountId);
        }
      }
    }

    profiles.sort((a, b) => a.accountId.compareTo(b.accountId));
    return profiles;
  }

  static Future<bool> hasAnyUsers() async {
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    final clientSettingsRoot = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings']),
    );

    if (await profilesDir.exists()) {
      await for (final entity in profilesDir.list(recursive: false)) {
        if (entity is! Directory) continue;
        final accountId = _basename(entity.path);
        if (accountId.trim().isEmpty) continue;
        if (accountId == _profileTemplateBackupDirName ||
            accountId.startsWith('.')) {
          continue;
        }
        return true;
      }
    }

    if (await clientSettingsRoot.exists()) {
      await for (final entity in clientSettingsRoot.list(recursive: false)) {
        if (entity is! Directory) continue;
        final accountId = _basename(entity.path);
        if (accountId.trim().isEmpty) continue;
        if (accountId.toLowerCase() == 'config' ||
            accountId == _profileTemplateBackupDirName ||
            accountId.startsWith('.')) {
          continue;
        }
        return true;
      }
    }

    return false;
  }

  static Future<List<ProfilePreset>> listPresets() async {
    final presetsDir = Directory(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
      ]),
    );
    if (!await presetsDir.exists()) return [];
    final presets = <ProfilePreset>[];
    await for (final entity in presetsDir.list(recursive: false)) {
      if (entity is! Directory) continue;
      final folder = _basename(entity.path);
      if (folder.trim().isEmpty) continue;
      final presetPath = File(joinPath([entity.path, 'profile_athena.json']));
      if (!await presetPath.exists()) continue;
      final labelParts = _presetLabelParts(folder);
      presets.add(
        ProfilePreset(
          name: labelParts.$1,
          folder: folder,
          versionTag: labelParts.$2,
        ),
      );
    }
    presets.sort((a, b) {
      final aBottomPinned = _isBottomPinnedPresetFolder(a.folder);
      final bBottomPinned = _isBottomPinnedPresetFolder(b.folder);
      if (aBottomPinned != bBottomPinned) {
        return aBottomPinned ? 1 : -1;
      }
      return a.name.compareTo(b.name);
    });
    return presets;
  }

  static (String, String?) _presetLabelParts(String folderName) {
    switch (folderName.trim().toLowerCase()) {
      case 'reboot x pulse profile':
      case 'reboot x pulse one profile':
      case 'reboot x pulse one':
        return ('Reboot X Pulse', 'v9.10');
      case 'reboot x stellar profile':
        return ('Reboot X Stellar', 'v12.41');
      case 'reboot x tozo profile':
        return ('Reboot X Tozo', 'v12.41');
      case 'reboot x retrac profile':
        return ('Reboot X Retrac', 'v14.40');
      case 'latest profile':
        return ('Latest', 'v39+');
      default:
        return (folderName, null);
    }
  }

  static bool _isBottomPinnedPresetFolder(String folderName) {
    switch (folderName.trim().toLowerCase()) {
      case 'reboot x pulse profile':
      case 'reboot x pulse one profile':
      case 'reboot x pulse one':
        return true;
      default:
        return false;
    }
  }

  static Future<void> applyPreset(String accountId, String presetFolder) async {
    final presetPath = File(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
        presetFolder,
        'profile_athena.json',
      ]),
    );
    final profilePath = File(
      joinPath([
        getBackendRoot(),
        'static',
        'profiles',
        accountId,
        'profile_athena.json',
      ]),
    );
    if (!await presetPath.exists()) {
      throw Exception('Preset profile not found.');
    }
    await profilePath.parent.create(recursive: true);
    await presetPath.copy(profilePath.path);
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
  }

  static Future<int> applyPresetToAll(String presetFolder) async {
    final presetPath = File(
      joinPath([
        getBackendRoot(),
        'static',
        'athenaprofiles',
        'Profile Presets',
        presetFolder,
        'profile_athena.json',
      ]),
    );
    if (!await presetPath.exists()) {
      throw Exception('Preset profile not found.');
    }
    final profiles = await listProfiles();
    if (profiles.isEmpty) {
      throw Exception('No profiles found.');
    }
    var appliedCount = 0;
    for (final profile in profiles) {
      final profilePath = File(
        joinPath([
          getBackendRoot(),
          'static',
          'profiles',
          profile.accountId,
          'profile_athena.json',
        ]),
      );
      await profilePath.parent.create(recursive: true);
      await presetPath.copy(profilePath.path);
      appliedCount += 1;
    }
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
    return appliedCount;
  }

  static Future<void> deleteProfile(
    String accountId, {
    required bool deleteProfile,
    required bool deleteClientSettings,
  }) async {
    if (deleteProfile) {
      final profilesDir = Directory(
        joinPath([getBackendRoot(), 'static', 'profiles', accountId]),
      );
      if (await profilesDir.exists()) {
        await profilesDir.delete(recursive: true);
      }
    }

    if (deleteClientSettings) {
      final clientSettingsDir = Directory(
        joinPath([getBackendRoot(), 'static', 'ClientSettings', accountId]),
      );
      if (await clientSettingsDir.exists()) {
        await clientSettingsDir.delete(recursive: true);
      }
    }

    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
  }

  static Future<void> deleteAllProfiles({
    required bool deleteProfiles,
    required bool deleteClientSettings,
  }) async {
    if (deleteProfiles) {
      final profilesRoot = Directory(
        joinPath([getBackendRoot(), 'static', 'profiles']),
      );
      if (await profilesRoot.exists()) {
        await for (final entity in profilesRoot.list(recursive: false)) {
          if (entity is! Directory) continue;
          final name = _basename(entity.path);
          if (name.isEmpty || name.startsWith('.')) continue;
          await entity.delete(recursive: true);
        }
      }
    }

    if (deleteClientSettings) {
      final clientSettingsRoot = Directory(
        joinPath([getBackendRoot(), 'static', 'ClientSettings']),
      );
      if (await clientSettingsRoot.exists()) {
        await for (final entity in clientSettingsRoot.list(recursive: false)) {
          if (entity is! Directory) continue;
          final name = _basename(entity.path);
          if (name.isEmpty || name.startsWith('.')) continue;
          if (name.toLowerCase() == 'config') continue;
          await entity.delete(recursive: true);
        }
      }
    }
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {}
  }
}

class LogStore extends ChangeNotifier {
  LogStore._();

  static final LogStore instance = LogStore._();

  final List<String> _logs = [];

  List<String> get allLogs => List.unmodifiable(_logs);
  List<String> get recentLogs =>
      _logs.length > 20 ? _logs.sublist(_logs.length - 20) : _logs;

  void addLog(String line) {
    _logs.add(line);
    if (_logs.length > 1000) {
      _logs.removeRange(0, _logs.length - 1000);
    }
    notifyListeners();
  }

  void clear() {
    if (_logs.isEmpty) return;
    _logs.clear();
    notifyListeners();
  }
}

class BackendPaths {
  static const String curveTableComment = '# CurveTables';
  static const String straightBloomComment = '# Straight Bloom';
  static const String dataTableComment = '# DataTables';
  static const String defaultCurvePath =
      '/Game/Athena/Balance/DataTables/AthenaGameData';

  static String get defaultGameIni =>
      joinPath([getBackendRoot(), 'static', 'hotfixes', 'DefaultGame.ini']);
  static String get curvesJson =>
      joinPath([getBackendRoot(), 'responses', 'curves.json']);
  static String get dataTablesJson =>
      joinPath([getBackendRoot(), 'responses', 'datatables.json']);
  static String get dataTablesUiState =>
      joinPath([getBackendRoot(), 'responses', 'datatables-ui.json']);
  static String get modificationsBackup =>
      joinPath([getBackendRoot(), 'responses', 'modifications-backup.json']);
  static String get sniperJson =>
      joinPath([getBackendRoot(), 'responses', 'sniper.json']);
  static String get configIni =>
      joinPath([getBackendRoot(), 'src', 'config', 'config.ini']);
  static String get updateNotesMarkdown =>
      joinPath([getBackendRoot(), 'update-notes.md']);
  static String get updateNotesText =>
      joinPath([getBackendRoot(), 'update-notes.txt']);
}

class IniService {
  static ({String content, int insertPoint}) ensureAssetSection(
    String content,
    String commentLabel, {
    bool preferPrepend = false,
  }) {
    var updated = content;
    if (!updated.contains(commentLabel)) {
      final assetIndex = updated.indexOf('[AssetHotfix]');
      if (assetIndex != -1) {
        if (preferPrepend) {
          updated =
              '${updated.substring(0, assetIndex)}[AssetHotfix]\n$commentLabel\n${updated.substring(assetIndex)}';
        } else {
          final newlineAfter = updated.indexOf('\n', assetIndex);
          final insertAt = newlineAfter == -1
              ? updated.length
              : newlineAfter + 1;
          updated =
              '${updated.substring(0, insertAt)}$commentLabel\n${updated.substring(insertAt)}';
        }
      } else {
        updated = '${updated.trimRight()}\n[AssetHotfix]\n$commentLabel\n';
      }
    }

    final commentIndex = updated.indexOf(commentLabel);
    final newlineAfterComment = updated.indexOf('\n', commentIndex);
    final insertPoint = newlineAfterComment == -1
        ? updated.length
        : newlineAfterComment + 1;
    return (content: updated, insertPoint: insertPoint);
  }
}

class StraightBloomService {
  static Future<bool> isEnabled() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    final sniperFile = File(BackendPaths.sniperJson);
    if (!await iniFile.exists() || !await sniperFile.exists()) return false;
    final content = await iniFile.readAsString();
    final lines =
        (jsonDecode(await sniperFile.readAsString())
                as Map<String, dynamic>)['lines']
            as List<dynamic>;
    return lines.any((line) => content.contains(line as String));
  }

  static Future<void> setEnabled(bool enabled) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    final sniperFile = File(BackendPaths.sniperJson);
    if (!await iniFile.exists() || !await sniperFile.exists()) return;
    var content = await iniFile.readAsString();
    final lines =
        (jsonDecode(await sniperFile.readAsString())
                as Map<String, dynamic>)['lines']
            as List<dynamic>;
    final sniperLines = lines.cast<String>();
    if (!enabled) {
      for (final line in sniperLines) {
        content = content.replaceAll('$line\n', '').replaceAll(line, '');
      }
      content = content.replaceAll(RegExp('\n\n+'), '\n');
    } else {
      final ensured = IniService.ensureAssetSection(
        content,
        BackendPaths.straightBloomComment,
      );
      content = ensured.content;
      final insertPoint = ensured.insertPoint;
      content =
          '${content.substring(0, insertPoint)}${sniperLines.join('\n')}\n${content.substring(insertPoint)}';
    }
    await iniFile.writeAsString(content);
  }

  static Future<void> importFromIni(String importPath) async {
    final source = File(importPath);
    final sniperFile = File(BackendPaths.sniperJson);
    if (!await source.exists() || !await sniperFile.exists()) return;
    final importContent = await source.readAsString();
    final block = _extractLastHotfixBlock(importContent);
    if (block.trim().isEmpty) return;
    final blockLines = block
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.startsWith(';') ? line.substring(1) : line)
        .toSet();
    final lines =
        (jsonDecode(await sniperFile.readAsString())
                as Map<String, dynamic>)['lines']
            as List<dynamic>;
    final sniperLines = lines.cast<String>();
    final hasAll = sniperLines.every((line) => blockLines.contains(line));
    await setEnabled(hasAll);
  }
}

class CurveEntry {
  const CurveEntry({
    required this.id,
    required this.name,
    required this.key,
    required this.type,
    required this.pathPart,
    required this.staticValue,
    required this.isCustom,
    required this.multiLines,
    this.groupId,
    this.groupName,
    this.groupImagePath,
  });

  final String id;
  final String name;
  final String key;
  final String type;
  final String? pathPart;
  final String? staticValue;
  final bool isCustom;
  final List<String> multiLines;
  final String? groupId;
  final String? groupName;
  final String? groupImagePath;
}

class CustomCurveInput {
  const CustomCurveInput({
    required this.name,
    required this.key,
    required this.pathPart,
    required this.lines,
    required this.staticValue,
    required this.isStatic,
    required this.groupId,
    required this.groupName,
    required this.groupImagePath,
    required this.groupImageSourcePath,
  });

  final String name;
  final String key;
  final String pathPart;
  final List<String> lines;
  final String staticValue;
  final bool isStatic;
  final String groupId;
  final String groupName;
  final String groupImagePath;
  final String groupImageSourcePath;
}

class CustomCurveGroupInfo {
  const CustomCurveGroupInfo({
    required this.id,
    required this.name,
    required this.imagePath,
  });

  final String id;
  final String name;
  final String? imagePath;
}

class CustomDataTableInput {
  const CustomDataTableInput({
    required this.weaponName,
    required this.weaponIdLine,
    required this.damagePB,
    required this.envDamage,
    required this.advancedMode,
    this.imageSourcePath,
    this.damageMid,
    this.damageLong,
    this.damageMaxRange,
    this.rarityConfigs,
    this.clipSize,
    this.reloadTime,
  });

  final String weaponName;
  final String weaponIdLine;
  final String damagePB;
  final String envDamage;
  final bool advancedMode;
  final String? imageSourcePath;
  final String? damageMid;
  final String? damageLong;
  final String? damageMaxRange;
  // Map of rarity name -> damage configuration
  // Each config contains: damagePB, envDamage, damageMid, damageLong, damageMaxRange, weaponIdLine, reloadTime
  final Map<String, Map<String, String>>? rarityConfigs;
  final String? clipSize;
  final String? reloadTime;
}

class DataTableWeapon {
  const DataTableWeapon({
    required this.id,
    required this.name,
    required this.weaponId,
    required this.weaponPath,
    required this.imagePath,
    required this.damageFields,
    required this.environmentalDamageFields,
    required this.damagePB,
    required this.defaultEnvDamage,
    this.variants,
    this.clipSize,
  });

  final String id;
  final String name;
  final String weaponId;
  final String weaponPath;
  final String? imagePath;
  final List<String> damageFields;
  final List<String> environmentalDamageFields;
  final String damagePB;
  final String defaultEnvDamage;
  final List<WeaponVariant>? variants;
  final String? clipSize;
}

class WeaponVariant {
  const WeaponVariant({
    required this.name,
    required this.weaponId,
    required this.damagePB,
    required this.defaultEnvDamage,
    this.imagePath,
    this.reloadTime,
  });

  final String name;
  final String weaponId;
  final String damagePB;
  final String defaultEnvDamage;
  final String? imagePath;
  final String? reloadTime;
}

class DataTableSettings {
  const DataTableSettings({
    required this.damageEnabled,
    required this.envDamageEnabled,
    required this.advancedMode,
    required this.damageValue,
    required this.envDamageValue,
    required this.customValues,
    required this.clipSizeEnabled,
    required this.clipSizeValue,
    required this.reloadTimeEnabled,
    required this.reloadTimeValue,
  });

  final bool damageEnabled;
  final bool envDamageEnabled;
  final bool advancedMode;
  final String damageValue;
  final String envDamageValue;
  final Map<String, String> customValues;
  final bool clipSizeEnabled;
  final String clipSizeValue;
  final bool reloadTimeEnabled;
  final String reloadTimeValue;

  DataTableSettings copyWith({
    bool? damageEnabled,
    bool? envDamageEnabled,
    bool? advancedMode,
    String? damageValue,
    String? envDamageValue,
    Map<String, String>? customValues,
    bool? clipSizeEnabled,
    String? clipSizeValue,
    bool? reloadTimeEnabled,
    String? reloadTimeValue,
  }) {
    return DataTableSettings(
      damageEnabled: damageEnabled ?? this.damageEnabled,
      envDamageEnabled: envDamageEnabled ?? this.envDamageEnabled,
      advancedMode: advancedMode ?? this.advancedMode,
      damageValue: damageValue ?? this.damageValue,
      envDamageValue: envDamageValue ?? this.envDamageValue,
      customValues: customValues ?? this.customValues,
      clipSizeEnabled: clipSizeEnabled ?? this.clipSizeEnabled,
      clipSizeValue: clipSizeValue ?? this.clipSizeValue,
      reloadTimeEnabled: reloadTimeEnabled ?? this.reloadTimeEnabled,
      reloadTimeValue: reloadTimeValue ?? this.reloadTimeValue,
    );
  }
}

const List<CurveGroup> _baseCurveGroups = [
  CurveGroup(
    id: 'shockwave',
    title: 'Shockwave',
    imageName: 'shock.webp',
    icon: Icons.waves,
    keywords: ['shockwave'],
  ),
  CurveGroup(
    id: 'bouncer',
    title: 'Bouncer',
    imageName: 'bouncer.webp',
    icon: Icons.unfold_more_double,
    keywords: ['bouncer', 'bouncepad', 'bounce pad'],
  ),
  CurveGroup(
    id: 'flint',
    title: 'Flint-Knock',
    imageName: 'flintknock.webp',
    icon: Icons.local_fire_department,
    keywords: ['flint', 'flintlock'],
  ),
  CurveGroup(
    id: 'glider',
    title: 'Glider Redeploy',
    imageName: 'glider.webp',
    icon: Icons.paragliding_rounded,
    keywords: ['glider', 'redeploy', 'parachute'],
  ),
  CurveGroup(
    id: 'jules',
    title: 'Jules',
    imageName: 'jules.webp',
    icon: Icons.person,
    keywords: ['jules', 'grappler', 'grapplinghoot'],
  ),
  CurveGroup(
    id: 'impulse',
    title: 'Impulse',
    imageName: 'impulse.webp',
    icon: Icons.bolt,
    keywords: ['impulse', 'knockgrenade'],
  ),
  CurveGroup(
    id: 'chiller',
    title: 'Chiller',
    imageName: 'chiller.webp',
    icon: Icons.ac_unit,
    keywords: ['chiller', 'icegrenade'],
  ),
  CurveGroup(
    id: 'launchpad',
    title: 'Launch Pad',
    imageName: 'launch.webp',
    icon: Icons.flight_takeoff,
    keywords: ['launch pad', 'launchpad'],
  ),
  CurveGroup(
    id: 'crashpad',
    title: 'Crash Pad',
    imageName: 'crashpad.webp',
    icon: Icons.airline_seat_legroom_extra,
    keywords: ['crash pad', 'applesun', 'crashpad'],
  ),
  CurveGroup(
    id: 'dub',
    title: 'Dub',
    imageName: 'dub.webp',
    icon: Icons.gavel,
    keywords: ['dub'],
  ),
  CurveGroup(
    id: 'cube',
    title: 'Cube',
    imageName: 'cube.webp',
    icon: Icons.crop_square,
    keywords: ['cube'],
  ),
  CurveGroup(
    id: 'rift',
    title: 'Rift',
    imageName: 'rift.webp',
    icon: Icons.public,
    keywords: ['rift'],
  ),
  CurveGroup(
    id: 'hopflopper',
    title: 'Hop Flopper',
    imageName: 'hopflop.webp',
    icon: Icons.set_meal,
    keywords: ['hop flopper', 'hopflopper'],
  ),
  CurveGroup(
    id: 'fall',
    title: 'Fall Damage',
    imageName: 'fall.webp',
    icon: Icons.heart_broken,
    keywords: ['fall damage', 'falling'],
  ),
  CurveGroup(
    id: 'neutral',
    title: 'Neutral Editing',
    imageName: 'edit.webp',
    icon: Icons.handyman,
    keywords: ['neutral editing'],
  ),
  CurveGroup(
    id: 'ammunition',
    title: 'Ammunition',
    imageName: 'ammo.webp',
    icon: Icons.inventory_2,
    keywords: ['ammo', 'ammunition', 'maxstackamount', 'max stack'],
  ),
  CurveGroup(
    id: 'storm',
    title: 'Storm',
    imageName: 'storm.webp',
    icon: Icons.cloud,
    keywords: ['storm', 'safezone', 'safe zone'],
  ),
];

List<CustomCurveGroupInfo> _customGroupsFromCurves(
  List<CurveEntry> curves, {
  Set<String> excludeIds = const {},
}) {
  final map = <String, CustomCurveGroupInfo>{};
  for (final entry in curves) {
    final groupId = entry.groupId;
    if (groupId == null || groupId.isEmpty) continue;
    if (excludeIds.contains(groupId)) continue;
    final existing = map[groupId];
    if (existing == null) {
      map[groupId] = CustomCurveGroupInfo(
        id: groupId,
        name: entry.groupName ?? 'Custom',
        imagePath: entry.groupImagePath,
      );
    } else if (existing.imagePath == null && entry.groupImagePath != null) {
      map[groupId] = CustomCurveGroupInfo(
        id: groupId,
        name: existing.name,
        imagePath: entry.groupImagePath,
      );
    }
  }
  return map.values.toList();
}

List<CustomCurveGroupInfo> _groupInfosForPrompt(List<CurveEntry> curves) {
  final builtinIds = _baseCurveGroups.map((group) => group.id).toSet();
  final builtinInfos = _baseCurveGroups
      .map(
        (group) => CustomCurveGroupInfo(
          id: group.id,
          name: group.title,
          imagePath: null,
        ),
      )
      .toList();
  final customInfos = _customGroupsFromCurves(curves, excludeIds: builtinIds);
  final hasOther =
      builtinInfos.any((group) => group.id == 'other') ||
      customInfos.any((group) => group.id == 'other');
  return [
    ...builtinInfos,
    ...customInfos,
    if (!hasOther)
      const CustomCurveGroupInfo(id: 'other', name: 'Other', imagePath: null),
  ];
}

String _humanizeCurveKey(String key) {
  final last = key.split('.').last;
  return last
      .replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match.group(0)}')
      .trim();
}

String _stripScheme(String url) {
  return url.replaceFirst(RegExp(r'^https?://'), '');
}

class _CustomCurveDraft {
  _CustomCurveDraft()
    : nameController = TextEditingController(),
      linesController = TextEditingController(),
      isStatic = false;

  final TextEditingController nameController;
  final TextEditingController linesController;
  bool isStatic;
}

class _CustomGroupEditResult {
  const _CustomGroupEditResult({required this.name, required this.imagePath});

  final String name;
  final String? imagePath;
}

class _CustomCurveEditResult {
  const _CustomCurveEditResult({
    required this.name,
    required this.lines,
    required this.staticValue,
    required this.isStatic,
    required this.key,
    required this.pathPart,
    required this.groupId,
    required this.groupName,
    required this.groupImagePath,
  });

  final String name;
  final List<String> lines;
  final String staticValue;
  final bool isStatic;
  final String key;
  final String pathPart;
  final String groupId;
  final String groupName;
  final String? groupImagePath;
}

class _ImportCurveDraft {
  _ImportCurveDraft({
    required this.key,
    required this.pathPart,
    required this.lines,
    required this.staticValue,
  }) : nameController = TextEditingController(),
       selectedGroupId = '';

  final String key;
  final String pathPart;
  final List<String> lines;
  final String staticValue;
  final TextEditingController nameController;
  String selectedGroupId;
}

class CurveTableService {
  static CurveEntry _entryFromJson(String id, Map<String, dynamic> data) {
    return CurveEntry(
      id: id,
      name: data['name'] ?? 'Curve $id',
      key: data['key'] ?? '',
      type: data['type'] ?? 'amount',
      pathPart: data['pathPart'],
      staticValue: data['staticValue'],
      isCustom: data['isCustom'] == true,
      multiLines:
          (data['multiLines'] as List<dynamic>?)?.cast<String>() ?? const [],
      groupId: data['groupId'],
      groupName: data['groupName'],
      groupImagePath: data['groupImagePath'] ?? data['imagePath'],
    );
  }

  static Future<List<CurveEntry>> loadCurves() async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return [];
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final entries = map.entries.map((entry) {
      final data = entry.value as Map<String, dynamic>;
      return _entryFromJson(entry.key, data);
    }).toList();
    entries.sort((a, b) => a.id.compareTo(b.id));
    return entries;
  }

  static Future<bool> areGlobalEnabled() async {
    final backup = File(BackendPaths.modificationsBackup);
    return !(await backup.exists());
  }

  static Future<void> toggleGlobal() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    final backupFile = File(BackendPaths.modificationsBackup);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    if (await backupFile.exists()) {
      final backup =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      final lines = (backup['curveTableLines'] as List<dynamic>? ?? [])
          .cast<String>();
      for (final line in lines) {
        content = content.replaceAll(';$line', line);
      }
      await iniFile.writeAsString(content);
      await backupFile.delete();
    } else {
      final regex = RegExp('^\\+CurveTable=.*;RowUpdate;.*\$', multiLine: true);
      final matches = regex
          .allMatches(content)
          .map((m) => m.group(0)!)
          .toList();
      final active = <String>[];
      for (final line in matches) {
        if (!line.startsWith(';')) {
          active.add(line);
          content = content.replaceAll(
            RegExp('^${RegExp.escape(line)}\$', multiLine: true),
            ';$line',
          );
        }
      }
      await iniFile.writeAsString(content);
      await backupFile.writeAsString(jsonEncode({'curveTableLines': active}));
    }
  }

  static Future<bool> isCurveEnabled(CurveEntry entry) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return false;
    final content = await iniFile.readAsString();
    if (entry.multiLines.isNotEmpty) {
      for (final line in entry.multiLines) {
        final parts = _splitCurveLine(line);
        if (parts == null) return false;
        final regex = RegExp(
          '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
          multiLine: true,
        );
        if (!regex.hasMatch(content)) return false;
      }
      return true;
    }
    final escapedKey = RegExp.escape(entry.key);
    final regex = RegExp(
      '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;.*\$',
      multiLine: true,
    );
    return regex.hasMatch(content);
  }

  static Future<String?> getCurrentValue(CurveEntry entry) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return null;
    final content = await iniFile.readAsString();
    if (entry.multiLines.isNotEmpty) {
      final escapedKey = RegExp.escape(entry.key);
      final regex = RegExp(
        '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;(.+)\$',
        multiLine: true,
      );
      final match = regex.firstMatch(content);
      return match?.group(1) ?? entry.staticValue;
    }
    final escapedKey = RegExp.escape(entry.key);
    final regex = RegExp(
      '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;(.+)\$',
      multiLine: true,
    );
    final match = regex.firstMatch(content);
    if (match == null) return null;
    return match.group(1);
  }

  static Future<void> setCurveEnabled(
    CurveEntry entry,
    bool enabled, {
    String? customValue,
  }) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    if (!enabled) {
      if (entry.multiLines.isNotEmpty) {
        for (final line in entry.multiLines) {
          final parts = _splitCurveLine(line);
          if (parts == null) continue;
          final regex = RegExp(
            '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
            multiLine: true,
          );
          content = content.replaceAll(regex, '');
        }
      } else {
        final escapedKey = RegExp.escape(entry.key);
        final regex = RegExp(
          '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;.*\$',
          multiLine: true,
        );
        content = content.replaceAll(regex, '');
      }
      content = content.replaceAll(RegExp('\n\n+'), '\n');
      await iniFile.writeAsString(content);
      return;
    }

    if (entry.multiLines.isNotEmpty) {
      for (final line in entry.multiLines) {
        final parts = _splitCurveLine(line);
        if (parts == null) continue;
        final regex = RegExp(
          '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
          multiLine: true,
        );
        content = content.replaceAll(regex, '');
      }
    } else {
      final escapedKey = RegExp.escape(entry.key);
      final regex = RegExp(
        '^\\+CurveTable=.*;RowUpdate;$escapedKey;\\d+;.*\$',
        multiLine: true,
      );
      content = content.replaceAll(regex, '');
    }
    content = content.replaceAll(RegExp('\n\n+'), '\n');

    final ensured = IniService.ensureAssetSection(
      content,
      BackendPaths.curveTableComment,
      preferPrepend: true,
    );
    content = ensured.content;
    final insertPoint = ensured.insertPoint;

    if (entry.multiLines.isNotEmpty) {
      final lines = entry.multiLines.map((line) {
        if (entry.type == 'amount' && customValue != null) {
          return _replaceCurveLineValue(line, customValue);
        }
        return line;
      }).toList();
      content =
          '${content.substring(0, insertPoint)}${lines.join('\n')}\n${content.substring(insertPoint)}';
    } else {
      final pathPart = entry.pathPart ?? BackendPaths.defaultCurvePath;
      final value = entry.type == 'static'
          ? (entry.staticValue ?? '0')
          : (customValue ?? '0');
      final line = '+CurveTable=$pathPart;RowUpdate;${entry.key};0;$value';
      content =
          '${content.substring(0, insertPoint)}$line\n${content.substring(insertPoint)}';
    }
    await iniFile.writeAsString(content);
  }

  static Future<void> importFromIni(String importPath) async {
    final source = File(importPath);
    final target = File(BackendPaths.defaultGameIni);
    if (!await source.exists() || !await target.exists()) return;
    final importContent = await source.readAsString();
    final filteredContent = _extractLastHotfixBlock(importContent);
    if (filteredContent.trim().isEmpty) {
      return;
    }
    final regex = RegExp(
      '^\\s*;?\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$',
      multiLine: true,
    );
    final matches = regex.allMatches(filteredContent).toList();
    if (matches.isEmpty) return;

    final grouped = <String, List<String>>{};
    var hasEnabled = false;
    final allNormalized = <String>[];
    for (final match in matches) {
      final pathPart = match.group(1)!.trim();
      final key = match.group(2)!.trim();
      final rawLine = match.group(0)!.trim();
      final normalized = rawLine.startsWith(';')
          ? rawLine.substring(1).trim()
          : rawLine;
      allNormalized.add(normalized);
      if (!rawLine.startsWith(';')) {
        hasEnabled = true;
      }
      final groupKey = '$pathPart|||$key';
      grouped.putIfAbsent(groupKey, () => []).add(normalized);
    }

    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) {
      await curvesFile.parent.create(recursive: true);
      await curvesFile.writeAsString('{}');
    }

    final existing = await CurveTableService.loadCurves();
    final existingKeys = existing
        .map(
          (entry) =>
              '${(entry.pathPart ?? BackendPaths.defaultCurvePath).trim()}|||${entry.key.trim()}',
        )
        .toSet();

    final missing = <CustomCurveInput>[];
    for (final entry in grouped.entries) {
      if (existingKeys.contains(entry.key)) continue;
      final parts = entry.key.split('|||');
      final key = parts[1];
      missing.add(
        CustomCurveInput(
          name: _humanizeKey(key),
          key: key,
          pathPart: parts[0],
          lines: entry.value,
          staticValue: '0',
          isStatic: false,
          groupId: 'other',
          groupName: 'Other',
          groupImagePath: '',
          groupImageSourcePath: '',
        ),
      );
    }

    if (missing.isNotEmpty) {
      await CurveTableService.addCustomCurves(missing);
    }

    for (final entry in grouped.entries) {
      final parts = entry.key.split('|||');
      final activeLines = entry.value
          .where((line) => !line.startsWith(';'))
          .toList();
      if (activeLines.isNotEmpty) {
        await CurveTableService.applyCurveLines(
          parts[0],
          parts[1],
          activeLines,
        );
      }
    }

    final backupFile = File(BackendPaths.modificationsBackup);
    if (matches.isNotEmpty) {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } else {
      await backupFile.writeAsString(
        jsonEncode({'curveTableLines': allNormalized}),
      );
    }
  }

  static String? _extractBlock(String content, String label) {
    final lines = content.split('\n');
    final startIndex = lines.indexWhere(
      (line) => line.trim() == label || line.trim().startsWith(label),
    );
    if (startIndex == -1) return null;
    final buffer = <String>[];
    for (var i = startIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#') || line.startsWith('[')) break;
      buffer.add(line);
    }
    return buffer.join('\n');
  }

  static Future<void> applyCurveLines(
    String pathPart,
    String key,
    List<String> lines,
  ) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    for (final line in lines) {
      final parts = _splitCurveLine(line);
      if (parts == null) continue;
      final regex = RegExp(
        '^\\+CurveTable=${RegExp.escape(parts.pathPart)};RowUpdate;${RegExp.escape(parts.key)};${RegExp.escape(parts.row)};.*\$',
        multiLine: true,
      );
      content = content.replaceAll(regex, '');
    }
    content = content.replaceAll(RegExp('\n\n+'), '\n');
    final ensured = IniService.ensureAssetSection(
      content,
      BackendPaths.curveTableComment,
      preferPrepend: true,
    );
    content = ensured.content;
    final insertPoint = ensured.insertPoint;
    content =
        '${content.substring(0, insertPoint)}${lines.join('\n')}\n${content.substring(insertPoint)}';
    content = content.replaceAll(RegExp(r'\n\n+'), '\n');
    await iniFile.writeAsString(content);
  }

  static Future<void> clearAllCurveTables() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    final backupFile = File(BackendPaths.modificationsBackup);
    final curvesFile = File(BackendPaths.curvesJson);

    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    content = content.replaceAll(
      RegExp('^\\+CurveTable=.*\$', multiLine: true),
      '',
    );
    content = content.replaceAll(RegExp('\n\n+'), '\n');
    await iniFile.writeAsString(content);

    if (await backupFile.exists()) {
      await backupFile.delete();
    }

    // Remove all entries in the "Other" group
    if (await curvesFile.exists()) {
      final curvesContent = await curvesFile.readAsString();
      final curvesData = jsonDecode(curvesContent) as Map<String, dynamic>;
      curvesData.removeWhere((_, value) {
        if (value is! Map<String, dynamic>) return false;
        return value['groupId'] == 'other';
      });
      await curvesFile.writeAsString(jsonEncode(curvesData));
    }
  }

  static Future<void> addCustomCurve(CustomCurveInput input) async {
    await addCustomCurves([input]);
  }

  static Future<void> addCustomCurves(List<CustomCurveInput> inputs) async {
    if (inputs.isEmpty) return;
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    var nextId =
        (map.keys
            .map(int.tryParse)
            .whereType<int>()
            .fold(0, (a, b) => a > b ? a : b)) +
        1;
    final groupImageCache = <String, String>{};

    for (final input in inputs) {
      var storedGroupImagePath = input.groupImagePath;
      if (storedGroupImagePath.isEmpty) {
        storedGroupImagePath = groupImageCache[input.groupId] ?? '';
      }
      if (storedGroupImagePath.isEmpty &&
          input.groupImageSourcePath.isNotEmpty) {
        final source = File(input.groupImageSourcePath);
        if (await source.exists()) {
          final destDir = Directory(
            joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']),
          );
          await destDir.create(recursive: true);
          final fileName = source.uri.pathSegments.last;
          final stampedName =
              '${DateTime.now().millisecondsSinceEpoch}_$fileName';
          storedGroupImagePath = joinPath(['custom-groups', stampedName]);
          await source.copy(joinPath([destDir.path, stampedName]));
        }
      }
      if (storedGroupImagePath.isNotEmpty) {
        groupImageCache[input.groupId] = storedGroupImagePath;
      }

      map[nextId.toString()] = {
        'name': input.name,
        'key': input.key,
        'type': input.isStatic ? 'static' : 'amount',
        'pathPart': input.pathPart,
        if (input.isStatic) 'staticValue': input.staticValue,
        'isCustom': true,
        'multiLines': input.lines,
        'groupId': input.groupId,
        'groupName': input.groupName,
        if (storedGroupImagePath.isNotEmpty)
          'groupImagePath': storedGroupImagePath,
      };

      final entry = CurveEntry(
        id: nextId.toString(),
        name: input.name,
        key: input.key,
        type: input.isStatic ? 'static' : 'amount',
        pathPart: input.pathPart,
        staticValue: input.isStatic ? input.staticValue : null,
        isCustom: true,
        multiLines: input.lines,
        groupId: input.groupId,
        groupName: input.groupName,
        groupImagePath: storedGroupImagePath.isNotEmpty
            ? storedGroupImagePath
            : null,
      );
      await setCurveEnabled(entry, true);
      nextId++;
    }

    await curvesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );
  }

  static Future<void> deleteCustomGroup(String groupId) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final entriesToDelete = <String, CurveEntry>{};
    String? groupImagePath;
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      if (data['isCustom'] == true && data['groupId'] == groupId) {
        entriesToDelete[entry.key] = _entryFromJson(entry.key, data);
        groupImagePath ??=
            (data['groupImagePath'] ?? data['imagePath']) as String?;
      }
    }
    for (final entry in entriesToDelete.values) {
      await setCurveEnabled(entry, false);
    }
    for (final key in entriesToDelete.keys) {
      map.remove(key);
    }
    await curvesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );

    if (groupImagePath != null && groupImagePath.isNotEmpty) {
      if (groupImagePath.startsWith('custom-groups')) {
        final imageFile = File(
          joinPath([getBackendRoot(), 'public', 'items', groupImagePath]),
        );
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      }
    }
  }

  static Future<void> deleteCustomCurve(String curveId) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final data = map[curveId];
    if (data is! Map<String, dynamic> || data['isCustom'] != true) return;
    final entry = _entryFromJson(curveId, data);
    await setCurveEnabled(entry, false);
    map.remove(curveId);
    await curvesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );
  }

  static Future<void> updateCustomCurve(
    String curveId,
    _CustomCurveEditResult updated,
  ) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final data = map[curveId];
    if (data is! Map<String, dynamic> || data['isCustom'] != true) return;
    final oldEntry = _entryFromJson(curveId, data);
    await setCurveEnabled(oldEntry, false);
    map[curveId] = {
      ...data,
      'name': updated.name,
      'key': updated.key,
      'type': updated.isStatic ? 'static' : 'amount',
      'pathPart': updated.pathPart,
      if (updated.isStatic) 'staticValue': updated.staticValue,
      if (!updated.isStatic) 'staticValue': null,
      'multiLines': updated.lines,
      'groupId': updated.groupId,
      'groupName': updated.groupName,
      if (updated.groupImagePath != null)
        'groupImagePath': updated.groupImagePath,
    };
    if (updated.groupImagePath == null) {
      (map[curveId] as Map<String, dynamic>).remove('groupImagePath');
    }
    final newEntry = CurveEntry(
      id: curveId,
      name: updated.name,
      key: updated.key,
      type: updated.isStatic ? 'static' : 'amount',
      pathPart: updated.pathPart,
      staticValue: updated.isStatic ? updated.staticValue : null,
      isCustom: true,
      multiLines: updated.lines,
      groupId: updated.groupId,
      groupName: updated.groupName,
      groupImagePath: updated.groupImagePath ?? oldEntry.groupImagePath,
    );
    await setCurveEnabled(newEntry, true);
    await curvesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );
  }

  static Future<void> updateCustomGroup(
    String groupId,
    String name,
    String? newImagePath,
  ) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) return;
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    String? storedImagePath;
    if (newImagePath != null && newImagePath.isNotEmpty) {
      final source = File(newImagePath);
      if (await source.exists()) {
        final destDir = Directory(
          joinPath([getBackendRoot(), 'public', 'items', 'custom-groups']),
        );
        await destDir.create(recursive: true);
        final fileName = source.uri.pathSegments.last;
        final stampedName =
            '${DateTime.now().millisecondsSinceEpoch}_$fileName';
        storedImagePath = joinPath(['custom-groups', stampedName]);
        await source.copy(joinPath([destDir.path, stampedName]));
      }
    }
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      if (data['isCustom'] == true && data['groupId'] == groupId) {
        data['groupName'] = name;
        if (storedImagePath != null) {
          data['groupImagePath'] = storedImagePath;
        }
        map[entry.key] = data;
      }
    }
    await curvesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );
  }

  static Future<void> _ensureCurveInJson(String key, String pathPart) async {
    final curvesFile = File(BackendPaths.curvesJson);
    if (!await curvesFile.exists()) {
      await curvesFile.parent.create(recursive: true);
      await curvesFile.writeAsString('{}');
    }
    final map =
        jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
    final exists = map.values.any((value) {
      final data = value as Map<String, dynamic>;
      final existingPath =
          (data['pathPart'] ?? BackendPaths.defaultCurvePath) as String;
      return data['key'] == key && existingPath == pathPart;
    });
    if (exists) return;
    final nextId =
        (map.keys
            .map(int.tryParse)
            .whereType<int>()
            .fold(0, (a, b) => a > b ? a : b)) +
        1;
    map[nextId.toString()] = {
      'name': _humanizeKey(key),
      'key': key,
      'type': 'amount',
      'pathPart': pathPart,
      'isCustom': true,
      'groupId': 'other',
      'groupName': 'Other',
    };
    await curvesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );
  }

  static String _humanizeKey(String key) {
    final last = key.split('.').last;
    return last
        .replaceAllMapped(RegExp('[A-Z]'), (match) => ' ${match.group(0)}')
        .trim();
  }
}

class DataTableService {
  // Preserve any manual fixes under the "# Fixes" marker in DefaultGame.ini.
  static ({String editable, String protected}) _splitProtectedFixesBlock(
    String content,
  ) {
    final match =
        RegExp(r'^\s*#\s*Fixes\s*$', multiLine: true).firstMatch(content);
    if (match == null) return (editable: content, protected: '');
    return (
      editable: content.substring(0, match.start),
      protected: content.substring(match.start),
    );
  }

  static Future<List<DataTableWeapon>> loadWeapons() async {
    final dataTablesFile = File(BackendPaths.dataTablesJson);
    if (!await dataTablesFile.exists()) {
      return [];
    }
    final map =
        jsonDecode(await dataTablesFile.readAsString()) as Map<String, dynamic>;
    final weapons = <DataTableWeapon>[];
    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      final variantsData = data['variants'] as List<dynamic>?;
      List<WeaponVariant>? variants;
      if (variantsData != null && variantsData.isNotEmpty) {
        variants = variantsData.map((v) {
          final vMap = v as Map<String, dynamic>;
          return WeaponVariant(
            name: vMap['name'] ?? '',
            weaponId: vMap['weaponId'] ?? '',
            damagePB: vMap['damagePB'] ?? '0',
            defaultEnvDamage: vMap['defaultEnvDamage'] ?? '0',
            imagePath: vMap['imagePath'],
            reloadTime: vMap['reloadTime'],
          );
        }).toList();
      }
      weapons.add(
        DataTableWeapon(
          id: entry.key,
          name: data['name'] ?? 'Weapon ${entry.key}',
          weaponId: data['weaponId'] ?? '',
          weaponPath:
              data['weaponPath'] ??
              '/Game/Athena/Items/Weapons/AthenaRangedWeapons',
          imagePath: data['imagePath'],
          damageFields:
              (data['damageFields'] as List<dynamic>?)?.cast<String>() ?? [],
          environmentalDamageFields:
              (data['environmentalDamageFields'] as List<dynamic>?)
                  ?.cast<String>() ??
              [],
          damagePB: data['damagePB'] ?? '0',
          defaultEnvDamage: data['defaultEnvDamage'] ?? '0',
          variants: variants,
          clipSize: data['clipSize'],
        ),
      );
    }
    return weapons;
  }

  static Future<bool> areDataTablesEnabled() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return false;
    final content = await iniFile.readAsString();
    final regex = RegExp(r'^\+DataTable=.*$', multiLine: true);
    return regex.hasMatch(content);
  }

  static Future<bool> getUIEnabledState() async {
    final stateFile = File(BackendPaths.dataTablesUiState);
    if (await stateFile.exists()) {
      try {
        final state =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        return state['enabled'] == true;
      } catch (_) {
        return false;
      }
    }

    // Legacy fallback: migrate from modifications-backup.json if present.
    final backupFile = File(BackendPaths.modificationsBackup);
    if (!await backupFile.exists()) return false;
    try {
      final backup =
          jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
      final enabled = backup['dataTablesUIEnabled'] == true;
      try {
        await _writeUiState(enabled);
      } catch (_) {}
      if (!backup.containsKey('curveTableLines')) {
        final extraKeys = backup.keys
            .where((key) => key != 'dataTablesUIEnabled')
            .toList();
        if (extraKeys.isEmpty) {
          try {
            await backupFile.delete();
          } catch (_) {}
        }
      }
      return enabled;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setUIEnabledState(bool enabled) async {
    await _writeUiState(enabled);
  }

  static Future<void> _writeUiState(bool enabled) async {
    final stateFile = File(BackendPaths.dataTablesUiState);
    await stateFile.parent.create(recursive: true);
    await stateFile.writeAsString(jsonEncode({'enabled': enabled}));
  }

  static Future<DataTableSettings> getWeaponSettings(
    DataTableWeapon weapon, {
    String? variantWeaponId,
  }) async {
    final weaponId = variantWeaponId ?? weapon.weaponId;

    // Get default clipSize and reloadTime
    String defaultClipSize = weapon.clipSize ?? '30';
    String defaultReloadTime = '2.0';

    // If variant is selected, get reloadTime from variant
    if (variantWeaponId != null && weapon.variants != null) {
      final variant = weapon.variants!.firstWhere(
        (v) => v.weaponId == variantWeaponId,
        orElse: () => weapon.variants!.first,
      );
      defaultReloadTime = variant.reloadTime ?? '2.0';
    }

    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) {
      return DataTableSettings(
        damageEnabled: false,
        envDamageEnabled: false,
        advancedMode: false,
        damageValue: weapon.damagePB,
        envDamageValue: weapon.defaultEnvDamage,
        customValues: {},
        clipSizeEnabled: false,
        clipSizeValue: defaultClipSize,
        reloadTimeEnabled: false,
        reloadTimeValue: defaultReloadTime,
      );
    }
    final content = await iniFile.readAsString();
    final customValues = <String, String>{};
    bool hasDamage = false;
    bool hasEnvDamage = false;
    bool hasClipSize = false;
    bool hasReloadTime = false;
    String? clipSizeValue;
    String? reloadTimeValue;

    for (final field in weapon.damageFields) {
      final regex = RegExp(
        r'^\+DataTable=' +
            RegExp.escape(weapon.weaponPath) +
            r';RowUpdate;' +
            RegExp.escape(weaponId) +
            r';' +
            RegExp.escape(field) +
            r';(.+)$',
        multiLine: true,
      );
      final match = regex.firstMatch(content);
      if (match != null) {
        customValues[field] = match.group(1)!;
        hasDamage = true;
      }
    }

    for (final field in weapon.environmentalDamageFields) {
      final regex = RegExp(
        r'^\+DataTable=' +
            RegExp.escape(weapon.weaponPath) +
            r';RowUpdate;' +
            RegExp.escape(weaponId) +
            r';' +
            RegExp.escape(field) +
            r';(.+)$',
        multiLine: true,
      );
      final match = regex.firstMatch(content);
      if (match != null) {
        customValues[field] = match.group(1)!;
        hasEnvDamage = true;
      }
    }

    // Check for ClipSize
    final clipSizeRegex = RegExp(
      r'^\+DataTable=' +
          RegExp.escape(weapon.weaponPath) +
          r';RowUpdate;' +
          RegExp.escape(weaponId) +
          r';ClipSize;(.+)$',
      multiLine: true,
    );
    final clipSizeMatch = clipSizeRegex.firstMatch(content);
    if (clipSizeMatch != null) {
      clipSizeValue = clipSizeMatch.group(1)!;
      hasClipSize = true;
    }

    // Check for ReloadTime
    final reloadTimeRegex = RegExp(
      r'^\+DataTable=' +
          RegExp.escape(weapon.weaponPath) +
          r';RowUpdate;' +
          RegExp.escape(weaponId) +
          r';ReloadTime;(.+)$',
      multiLine: true,
    );
    final reloadTimeMatch = reloadTimeRegex.firstMatch(content);
    if (reloadTimeMatch != null) {
      reloadTimeValue = reloadTimeMatch.group(1)!;
      hasReloadTime = true;
    }

    // Check if values are consistent (simple mode) or different (advanced mode)
    bool advancedMode = false;
    String? dmgValue;
    String? envDmgValue;

    if (hasDamage) {
      final damageValues = weapon.damageFields
          .map((f) => customValues[f])
          .whereType<String>()
          .toSet();
      if (damageValues.length == 1) {
        dmgValue = damageValues.first;
      } else {
        advancedMode = true;
      }
    }

    if (hasEnvDamage) {
      final envValues = weapon.environmentalDamageFields
          .map((f) => customValues[f])
          .whereType<String>()
          .toSet();
      if (envValues.length == 1) {
        envDmgValue = envValues.first;
      } else {
        advancedMode = true;
      }
    }

    return DataTableSettings(
      damageEnabled: hasDamage,
      envDamageEnabled: hasEnvDamage,
      advancedMode: advancedMode,
      damageValue: dmgValue ?? weapon.damagePB,
      envDamageValue: envDmgValue ?? weapon.defaultEnvDamage,
      customValues: customValues,
      clipSizeEnabled: hasClipSize,
      clipSizeValue: clipSizeValue ?? defaultClipSize,
      reloadTimeEnabled: hasReloadTime,
      reloadTimeValue: reloadTimeValue ?? defaultReloadTime,
    );
  }

  static Future<void> applyWeaponSettings(
    DataTableWeapon weapon,
    DataTableSettings settings, {
    String? variantWeaponId,
  }) async {
    final weaponId = variantWeaponId ?? weapon.weaponId;
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    final split = _splitProtectedFixesBlock(content);
    var editable = split.editable;
    final protected = split.protected;

    // Remove existing DataTable lines for this weapon
    for (final field in [
      ...weapon.damageFields,
      ...weapon.environmentalDamageFields,
      'ClipSize',
      'ReloadTime',
    ]) {
      final regex = RegExp(
        r'^\+DataTable=' +
            RegExp.escape(weapon.weaponPath) +
            r';RowUpdate;' +
            RegExp.escape(weaponId) +
            r';' +
            RegExp.escape(field) +
            r';.*$',
        multiLine: true,
      );
      editable = editable.replaceAll(regex, '');
    }
    editable = editable.replaceAll(RegExp(r'\n\n+'), '\n');

    // Add new lines if enabled
    final linesToAdd = <String>[];

    if (settings.damageEnabled) {
      if (settings.advancedMode) {
        for (final field in weapon.damageFields) {
          final value = settings.customValues[field] ?? weapon.damagePB;
          linesToAdd.add(
            '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;$field;$value',
          );
        }
      } else {
        for (final field in weapon.damageFields) {
          linesToAdd.add(
            '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;$field;${settings.damageValue}',
          );
        }
      }
    }

    if (settings.envDamageEnabled) {
      if (settings.advancedMode) {
        for (final field in weapon.environmentalDamageFields) {
          final value = settings.customValues[field] ?? weapon.defaultEnvDamage;
          linesToAdd.add(
            '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;$field;$value',
          );
        }
      } else {
        for (final field in weapon.environmentalDamageFields) {
          linesToAdd.add(
            '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;$field;${settings.envDamageValue}',
          );
        }
      }
    }

    if (settings.clipSizeEnabled) {
      linesToAdd.add(
        '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;ClipSize;${settings.clipSizeValue}',
      );
    }

    if (settings.reloadTimeEnabled) {
      linesToAdd.add(
        '+DataTable=${weapon.weaponPath};RowUpdate;$weaponId;ReloadTime;${settings.reloadTimeValue}',
      );
    }

    if (linesToAdd.isNotEmpty) {
      final ensured = IniService.ensureAssetSection(
        editable,
        BackendPaths.dataTableComment,
        preferPrepend: true,
      );
      editable = ensured.content;
      final insertPoint = ensured.insertPoint;
      editable =
          '${editable.substring(0, insertPoint)}${linesToAdd.join('\n')}\n${editable.substring(insertPoint)}';
    }

    await iniFile.writeAsString('$editable$protected');
  }

  static Future<void> clearAllDataTables() async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    final split = _splitProtectedFixesBlock(content);
    var editable = split.editable;
    final protected = split.protected;
    final regex = RegExp(r'^\+DataTable=.*$', multiLine: true);
    editable = editable.replaceAll(regex, '');
    editable = editable.replaceAll(RegExp(r'\n\n+'), '\n');
    await iniFile.writeAsString('$editable$protected');
  }

  static Future<void> addCustomWeapon(CustomDataTableInput input) async {
    // Add weapon to datatables-ui.json
    final dataTablesFile = File(BackendPaths.dataTablesJson);
    Map<String, dynamic> data = {};
    if (await dataTablesFile.exists()) {
      data =
          jsonDecode(await dataTablesFile.readAsString())
              as Map<String, dynamic>;
    }

    // Generate unique ID
    final weaponId = 'custom-${DateTime.now().millisecondsSinceEpoch}';

    // Save image if provided
    String? savedImagePath;
    if (input.imageSourcePath != null && input.imageSourcePath!.isNotEmpty) {
      final sourceFile = File(input.imageSourcePath!);
      if (await sourceFile.exists()) {
        final fileName = 'custom_${DateTime.now().millisecondsSinceEpoch}.png';
        final targetPath = joinPath([
          getBackendRoot(),
          'public',
          'items',
          fileName,
        ]);
        await sourceFile.copy(targetPath);
        savedImagePath = fileName;
      }
    }

    // Determine damage fields based on advanced mode
    List<String> damageFields;
    List<String> envDamageFields;

    if (input.advancedMode) {
      damageFields = ['DamagePB', 'DamageMid', 'DamageLong', 'DamageMaxRange'];
      envDamageFields = [
        'EnvironmentalDamagePB',
        'EnvironmentalDamageMid',
        'EnvironmentalDamageLong',
        'EnvironmentalDamageMaxRange',
      ];
    } else {
      damageFields = ['DamagePB'];
      envDamageFields = ['EnvironmentalDamagePB'];
    }

    data[weaponId] = {
      'name': input.weaponName,
      'weaponId': input.weaponIdLine,
      'weaponPath': '/Game/Athena/Items/Weapons/AthenaRangedWeapons',
      'imagePath': savedImagePath,
      'damageFields': damageFields,
      'environmentalDamageFields': envDamageFields,
      'damagePB': input.damagePB,
      'defaultEnvDamage': input.envDamage,
      if (input.clipSize != null) 'clipSize': input.clipSize,
    };

    await dataTablesFile.parent.create(recursive: true);
    await dataTablesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  static Future<void> importDataTableLines(List<String> lines) async {
    final iniFile = File(BackendPaths.defaultGameIni);
    if (!await iniFile.exists()) return;

    var content = await iniFile.readAsString();
    final ensured = IniService.ensureAssetSection(
      content,
      BackendPaths.dataTableComment,
      preferPrepend: true,
    );
    content = ensured.content;
    final insertPoint = ensured.insertPoint;

    // Insert the imported lines
    final linesToAdd = lines.join('\n');
    content =
        '${content.substring(0, insertPoint)}$linesToAdd\n${content.substring(insertPoint)}';

    await iniFile.writeAsString(content);
  }
}

class ConfigSettings {
  const ConfigSettings({
    required this.rufusStage,
    required this.waterLevel,
    required this.saveArenaPoints,
    required this.useWaterStorm,
    required this.startBackendOnLaunch,
    required this.disableBackendUpdateCheck,
    required this.useDarkMode,
    required this.backgroundImagePath,
    required this.backgroundBlur,
    required this.backgroundParticlesOpacity,
    required this.dialogBlurEnabled,
    required this.startupAnimationEnabled,
    required this.lastShownUpdateNotesVersion,
  });

  final int rufusStage;
  final int waterLevel;
  final bool saveArenaPoints;
  final bool useWaterStorm;
  final bool startBackendOnLaunch;
  final bool disableBackendUpdateCheck;
  final bool useDarkMode;
  final String backgroundImagePath;
  final double backgroundBlur;
  final double backgroundParticlesOpacity;
  final bool dialogBlurEnabled;
  final bool startupAnimationEnabled;
  final String lastShownUpdateNotesVersion;

  ConfigSettings copyWith({
    int? rufusStage,
    int? waterLevel,
    bool? saveArenaPoints,
    bool? useWaterStorm,
    bool? startBackendOnLaunch,
    bool? disableBackendUpdateCheck,
    bool? useDarkMode,
    String? backgroundImagePath,
    double? backgroundBlur,
    double? backgroundParticlesOpacity,
    bool? dialogBlurEnabled,
    bool? startupAnimationEnabled,
    String? lastShownUpdateNotesVersion,
  }) {
    return ConfigSettings(
      rufusStage: rufusStage ?? this.rufusStage,
      waterLevel: waterLevel ?? this.waterLevel,
      saveArenaPoints: saveArenaPoints ?? this.saveArenaPoints,
      useWaterStorm: useWaterStorm ?? this.useWaterStorm,
      startBackendOnLaunch: startBackendOnLaunch ?? this.startBackendOnLaunch,
      disableBackendUpdateCheck:
          disableBackendUpdateCheck ?? this.disableBackendUpdateCheck,
      useDarkMode: useDarkMode ?? this.useDarkMode,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      backgroundParticlesOpacity:
          backgroundParticlesOpacity ?? this.backgroundParticlesOpacity,
      dialogBlurEnabled: dialogBlurEnabled ?? this.dialogBlurEnabled,
      startupAnimationEnabled:
          startupAnimationEnabled ?? this.startupAnimationEnabled,
      lastShownUpdateNotesVersion:
          lastShownUpdateNotesVersion ?? this.lastShownUpdateNotesVersion,
    );
  }
}

class ConfigService {
  static Future<ConfigSettings> load() async {
    final base = await _loadConfigFile(File(BackendPaths.configIni));
    final gui = await _loadConfigFile(File(_guiConfigPath()));
    final map = {...base, ...gui};
    if (map.isEmpty) {
      return const ConfigSettings(
        rufusStage: 1,
        waterLevel: 1,
        saveArenaPoints: false,
        useWaterStorm: false,
        startBackendOnLaunch: false,
        disableBackendUpdateCheck: false,
        useDarkMode: true,
        backgroundImagePath: '',
        backgroundBlur: 15,
        backgroundParticlesOpacity: 1.0,
        dialogBlurEnabled: true,
        startupAnimationEnabled: true,
        lastShownUpdateNotesVersion: '',
      );
    }
    final lastShownUpdateNotesVersion =
        gui['LastShownUpdateNotesVersion'] ?? '';
    final legacyParticlesEnabled =
        (map['BackgroundParticlesEnabled'] ?? 'true').toLowerCase() == 'true';
    final parsedParticlesOpacity =
        double.tryParse(map['BackgroundParticlesOpacity'] ?? '');
    final resolvedParticlesOpacity =
        parsedParticlesOpacity ?? (legacyParticlesEnabled ? 1.0 : 0.0);
    return ConfigSettings(
      rufusStage: int.tryParse(map['RufusStage'] ?? '') ?? 1,
      waterLevel: int.tryParse(map['WaterLevel'] ?? '') ?? 1,
      saveArenaPoints: (map['SaveArenaPoints'] ?? '').toLowerCase() == 'true',
      useWaterStorm: (map['UseWaterStorm'] ?? '').toLowerCase() == 'true',
      startBackendOnLaunch:
          (map['StartBackendOnLaunch'] ?? '').toLowerCase() == 'true',
      disableBackendUpdateCheck:
          (map['DisableBackendUpdateCheck'] ?? '').toLowerCase() == 'true',
      useDarkMode: (map['UseDarkMode'] ?? 'true').toLowerCase() == 'true',
      backgroundImagePath: map['BackgroundImagePath'] ?? '',
      backgroundBlur: double.tryParse(map['BackgroundBlur'] ?? '') ?? 15,
      backgroundParticlesOpacity: resolvedParticlesOpacity,
      dialogBlurEnabled:
          (map['DialogBlurEnabled'] ?? 'true').toLowerCase() == 'true',
      startupAnimationEnabled:
          (map['StartupAnimationEnabled'] ?? 'true').toLowerCase() == 'true',
      lastShownUpdateNotesVersion: lastShownUpdateNotesVersion,
    );
  }

  static Future<void> save(ConfigSettings settings) async {
    final buffer = StringBuffer()
      ..writeln('RufusStage=${settings.rufusStage}')
      ..writeln('WaterLevel=${settings.waterLevel}')
      ..writeln('SaveArenaPoints=${settings.saveArenaPoints}')
      ..writeln('UseWaterStorm=${settings.useWaterStorm}')
      ..writeln('StartBackendOnLaunch=${settings.startBackendOnLaunch}')
      ..writeln(
        'DisableBackendUpdateCheck=${settings.disableBackendUpdateCheck}',
      )
      ..writeln('UseDarkMode=${settings.useDarkMode}')
      ..writeln('BackgroundImagePath=${settings.backgroundImagePath}')
      ..writeln('BackgroundBlur=${settings.backgroundBlur}')
      ..writeln(
        'BackgroundParticlesEnabled=${settings.backgroundParticlesOpacity > 0}',
      )
      ..writeln('BackgroundParticlesOpacity=${settings.backgroundParticlesOpacity}')
      ..writeln('DialogBlurEnabled=${settings.dialogBlurEnabled}')
      ..writeln('StartupAnimationEnabled=${settings.startupAnimationEnabled}')
      ..writeln(
        'LastShownUpdateNotesVersion=${settings.lastShownUpdateNotesVersion}',
      );
    final backendFile = File(BackendPaths.configIni);
    try {
      await backendFile.writeAsString(buffer.toString());
    } catch (_) {
      // Backend config might be read-only on some installs.
    }
    final guiFile = File(_guiConfigPath());
    try {
      await guiFile.parent.create(recursive: true);
      await guiFile.writeAsString(buffer.toString());
    } catch (_) {}
  }

  static String _guiConfigPath() {
    final appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isNotEmpty) {
      return joinPath([appData, 'ATLAS', 'gui.ini']);
    }
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    if (home.isNotEmpty) {
      return joinPath([home, 'AppData', 'Roaming', 'ATLAS', 'gui.ini']);
    }
    return joinPath([Directory.current.path, 'gui.ini']);
  }

  static Future<Map<String, String>> _loadConfigFile(File file) async {
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    final map = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          !trimmed.contains('=')) {
        continue;
      }
      final parts = trimmed.split('=');
      map[parts.first.trim()] = parts.sublist(1).join('=').trim();
    }
    return map;
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.downloadUrl,
    this.publishedAt,
    this.notes,
  });

  final String version;
  final String downloadUrl;
  final DateTime? publishedAt;
  final String? notes;
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.isInstaller,
    this.notes,
    this.currentCommit,
    this.latestCommit,
  });

  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final bool isInstaller;
  final String? notes;
  final String? currentCommit;
  final String? latestCommit;

  String get currentLabel => _formatVersion(currentVersion);
  String get latestLabel => _formatVersion(latestVersion);
}

class UpdateService {
  static const String _repo = 'cipherfps/ATLAS-Backend';
  static const String _branch = 'gui';
  static const String _mainZipUrl =
      'https://github.com/cipherfps/ATLAS-Backend/archive/refs/heads/gui.zip';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases/latest';
  static const String _releasesListUrl =
      'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases?per_page=30';

  static Future<UpdateInfo?> checkForUpdate() async {
    final detectedVersion = await _readBackendVersionFromCandidates();
    final currentVersion = detectedVersion.isEmpty ? '0.0.0' : detectedVersion;
    final release = await _fetchLatestReleaseInfo();
    if (release != null && _isNewerVersion(release.version, currentVersion)) {
      final downloadUrl = release.installerUrl ?? _mainZipUrl;
      final isInstaller = release.installerUrl != null;
      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: release.version,
        downloadUrl: downloadUrl,
        isInstaller: isInstaller,
        notes: release.notes,
        currentCommit: null,
        latestCommit: null,
      );
    }

    // Fallback for unreleased GUI branch updates.
    final remotePackage = await _fetchRemotePackage();
    if (remotePackage == null) return null;
    final latestVersion = (remotePackage['version'] ?? currentVersion)
        .toString();
    if (!_isNewerVersion(latestVersion, currentVersion)) return null;

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl: _mainZipUrl,
      isInstaller: false,
      notes: null,
      currentCommit: null,
      latestCommit: null,
    );
  }

  static Future<List<ReleaseInfo>> fetchReleaseHistory() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_releasesListUrl));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) return [];
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body);
      if (json is! List) return [];

      final releases = <ReleaseInfo>[];
      for (final entry in json) {
        if (entry is! Map<String, dynamic>) continue;
        if (entry['draft'] == true) continue;
        final tag = entry['tag_name']?.toString().trim();
        if (tag == null || tag.isEmpty) continue;

        final installerUrl = _findReleaseInstallerUrl(entry['assets']);
        if (installerUrl == null) continue;

        DateTime? published;
        final publishedRaw = entry['published_at']?.toString();
        if (publishedRaw != null) {
          published = DateTime.tryParse(publishedRaw);
        }

        releases.add(
          ReleaseInfo(
            version: tag,
            downloadUrl: installerUrl,
            publishedAt: published,
            notes: entry['body']?.toString(),
          ),
        );
      }

      releases.sort(
        (a, b) => _compareVersions(
          _normalizeVersion(b.version),
          _normalizeVersion(a.version),
        ),
      );
      return releases;
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }

  static Future<void> downloadAndApply(
    UpdateInfo info,
    ValueNotifier<double>? progress,
  ) async {
    if (info.isInstaller) {
      final installerFile = await _downloadInstaller(info.downloadUrl, progress);
      final lowerPath = installerFile.path.toLowerCase();
      if (lowerPath.endsWith('.msi')) {
        await Process.start('msiexec', [
          '/i',
          installerFile.path,
        ], mode: ProcessStartMode.detached);
      } else {
        await Process.start(
          installerFile.path,
          const [],
          mode: ProcessStartMode.detached,
        );
      }
      exit(0);
    } else {
      final zipFile = await _downloadZip(info.downloadUrl, progress);
      await _applyZip(zipFile);
    }
  }

  static Future<({String version, String? installerUrl, String? notes})?>
  _fetchLatestReleaseInfo() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_latestReleaseUrl));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name']?.toString().trim();
      if (tag == null || tag.isEmpty) return null;
      final installerUrl = _findReleaseInstallerUrl(json['assets']);
      return (
        version: tag,
        installerUrl: installerUrl,
        notes: json['body']?.toString(),
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static String? _findReleaseInstallerUrl(dynamic assetsRaw) {
    if (assetsRaw is! List) return null;

    String? preferredExe;
    String? fallbackExe;
    String? msi;

    for (final asset in assetsRaw) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name']?.toString().toLowerCase() ?? '';
      final url = asset['browser_download_url']?.toString();
      if (url == null || name.isEmpty || !name.contains('atlas')) continue;

      if (name.endsWith('.exe')) {
        if (name.contains('setup') || name.contains('installer')) {
          preferredExe ??= url;
        } else {
          fallbackExe ??= url;
        }
      } else if (name.endsWith('.msi')) {
        msi ??= url;
      }
    }

    // Prefer MSI if both installer types are published on a release.
    return msi ?? preferredExe ?? fallbackExe;
  }

  static Future<Map<String, dynamic>?> _fetchRemotePackage() async {
    final url = Uri.parse(
      'https://raw.githubusercontent.com/$_repo/$_branch/package.json?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<File> _downloadZip(
    String url,
    ValueNotifier<double>? progress,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('atlas_update_');
    final zipFile = File(joinPath([tempDir.path, 'update.zip']));
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = zipFile.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && progress != null) {
          progress.value = received / total;
        }
      }
      await sink.close();
      if (progress != null) {
        progress.value = 1;
      }
      return zipFile;
    } finally {
      client.close();
    }
  }

  static Future<File> _downloadInstaller(
    String url,
    ValueNotifier<double>? progress,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('atlas_update_');
    final uri = Uri.parse(url);
    var fileName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (fileName.trim().isEmpty) {
      fileName = 'ATLAS-Backend-Installer.msi';
    }
    final installerFile = File(joinPath([tempDir.path, fileName]));
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'ATLAS-GUI');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = installerFile.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && progress != null) {
          progress.value = received / total;
        }
      }
      await sink.close();
      if (progress != null) {
        progress.value = 1;
      }
      return installerFile;
    } finally {
      client.close();
    }
  }

  static Future<void> _applyZip(File zipFile) async {
    final backendRoot = getBackendRoot();
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final rawPath = file.name;
      final relative = _stripZipRoot(rawPath);
      if (relative.isEmpty) continue;
      if (_shouldPreserve(relative)) continue;

      final outPath = joinPath([backendRoot, ...relative.split('/')]);
      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }

  static String _stripZipRoot(String path) {
    final parts = path.split('/');
    if (parts.length <= 1) return '';
    return parts.sublist(1).join('/');
  }

  static bool _shouldPreserve(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.startsWith('atlas_gui_flutter/')) return true;
    if (normalized.startsWith('node_modules/')) return true;
    if (normalized.startsWith('exports/')) return true;
    if (normalized.startsWith('responses/curves.json')) return true;
    if (normalized.startsWith('responses/datatables-ui.json')) return true;
    if (normalized.startsWith('responses/modifications-backup.json')) {
      return true;
    }
    if (normalized.startsWith('src/config/config.ini')) return true;
    if (normalized.startsWith('public/items/custom-groups/')) return true;
    if (normalized.startsWith('static/hotfixes/DefaultGame.ini')) return true;

    if (normalized.startsWith('static/profiles/')) {
      final rest = normalized.substring('static/profiles/'.length);
      return !rest.startsWith('profile_');
    }
    if (normalized.startsWith('static/ClientSettings/')) {
      final rest = normalized.substring('static/ClientSettings/'.length);
      return !rest.startsWith('config/');
    }
    return false;
  }
}

class UpdateNotesService {
  static const UpdateNotesStyle _defaultStyle = UpdateNotesStyle(
    hrThickness: 0.6,
    hrOpacity: 0.18,
  );

  static Future<UpdateNotesPayload?> loadNotes() async {
    final target = await _findNotesFile();
    if (target == null) return null;
    final content = await target.readAsString();
    final parsed = _extractStyleAndContent(content);
    if (parsed.notes.trim().isEmpty) return null;
    return parsed;
  }

  static Future<File?> _findNotesFile() async {
    final candidates = <String>[
      BackendPaths.updateNotesMarkdown,
      BackendPaths.updateNotesText,
      joinPath([getInstallationRoot(), 'update-notes.md']),
      joinPath([getInstallationRoot(), 'update-notes.txt']),
      joinPath([Directory.current.path, 'update-notes.md']),
      joinPath([Directory.current.path, 'update-notes.txt']),
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }
    return null;
  }

  static UpdateNotesPayload _extractStyleAndContent(String content) {
    final regex = RegExp(
      r'<!--\s*hr:\s*thickness\s*=\s*([0-9]*\.?[0-9]+)\s+opacity\s*=\s*([0-9]*\.?[0-9]+)\s*-->',
      caseSensitive: false,
    );
    final match = regex.firstMatch(content);
    var style = _defaultStyle;
    var notes = content;
    if (match != null) {
      final thickness = double.tryParse(match.group(1) ?? '');
      final opacity = double.tryParse(match.group(2) ?? '');
      if (thickness != null || opacity != null) {
        style = style.copyWith(hrThickness: thickness, hrOpacity: opacity);
      }
      notes = content.replaceFirst(match.group(0) ?? '', '').trim();
    }
    return UpdateNotesPayload(notes: notes, style: style);
  }
}

class UpdateNotesPayload {
  const UpdateNotesPayload({required this.notes, required this.style});

  final String notes;
  final UpdateNotesStyle style;
}

class UpdateNotesStyle {
  const UpdateNotesStyle({required this.hrThickness, required this.hrOpacity});

  final double hrThickness;
  final double hrOpacity;

  UpdateNotesStyle copyWith({double? hrThickness, double? hrOpacity}) {
    return UpdateNotesStyle(
      hrThickness: hrThickness ?? this.hrThickness,
      hrOpacity: hrOpacity ?? this.hrOpacity,
    );
  }
}

final List<md.BlockSyntax> _roundedHrBlockSyntaxes = [
  _RoundedHrSyntax(),
  ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
];

final List<md.InlineSyntax> _roundedHrInlineSyntaxes =
    md.ExtensionSet.gitHubFlavored.inlineSyntaxes;

class _RoundedHrSyntax extends md.BlockSyntax {
  const _RoundedHrSyntax();

  @override
  RegExp get pattern => RegExp(r'^ {0,3}([-*_])[ \t]*\1[ \t]*\1(?:\1|[ \t])*$');

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    return md.Element.empty('rounded-hr');
  }
}

class _MarkdownHrBuilder extends MarkdownElementBuilder {
  _MarkdownHrBuilder({
    required this.color,
    required this.thickness,
    required this.verticalPadding,
  });

  final Color color;
  final double thickness;
  final double verticalPadding;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: thickness,
          width: double.infinity,
          child: DecoratedBox(decoration: BoxDecoration(color: color)),
        ),
      ),
    );
  }
}

class UpdateBackupService {
  static const String _backupFolderName = 'update-backup';

  static Future<void> backupBeforeUpdate() async {
    final backupRoot = Directory(_resolveBackupRoot());
    if (await backupRoot.exists()) {
      await backupRoot.delete(recursive: true);
    }
    await backupRoot.create(recursive: true);

    final backendRoot = getBackendRoot();
    final entries = <_BackupEntry>[
      _BackupEntry.dir(joinPath([backendRoot, 'static', 'ClientSettings'])),
      _BackupEntry.file(
        joinPath([backendRoot, 'static', 'hotfixes', 'DefaultGame.ini']),
      ),
      // Don't backup curves.json - let new version provide updated curves
      _BackupEntry.file(
        joinPath([backendRoot, 'responses', 'modifications-backup.json']),
      ),
      _BackupEntry.file(
        joinPath([backendRoot, 'responses', 'datatables-ui.json']),
      ),
      _BackupEntry.file(joinPath([backendRoot, 'src', 'config', 'config.ini'])),
      _BackupEntry.dir(
        joinPath([backendRoot, 'public', 'items', 'custom-groups']),
      ),
    ];

    for (final entry in entries) {
      final target = joinPath([
        backupRoot.path,
        ...entry.relativeParts(backendRoot),
      ]);
      if (entry.isDir) {
        final dir = Directory(entry.path);
        if (!dir.existsSync()) continue;
        await _copyDirectory(dir, Directory(target));
      } else {
        final file = File(entry.path);
        if (!file.existsSync()) continue;
        await File(target).parent.create(recursive: true);
        await file.copy(target);
      }
    }

    // Backup user-created profiles only (exclude template profiles)
    final profilesSource = Directory(
      joinPath([backendRoot, 'static', 'profiles']),
    );
    if (profilesSource.existsSync()) {
      final profilesTarget = Directory(
        joinPath([backupRoot.path, 'static', 'profiles']),
      );
      await _copyDirectoryExcludingProfiles(
        profilesSource,
        profilesTarget,
        _templateProfiles,
      );
    }

    // Don't backup Profile Presets - they are templates
    // (athenaprofiles/Profile Presets is skipped automatically)

    final manifest = {
      'version': _normalizeVersion(await _readBackendVersion()),
      'createdAt': DateTime.now().toIso8601String(),
    };
    await File(
      joinPath([backupRoot.path, 'manifest.json']),
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
  }

  static Future<void> restoreIfNeeded(BuildContext context) async {
    final backupRoot = Directory(_resolveBackupRoot());
    if (!backupRoot.existsSync()) return;

    final backendRoot = getBackendRoot();
    final entries = <_BackupEntry>[
      _BackupEntry.dir(joinPath([backupRoot.path, 'static', 'ClientSettings'])),
      _BackupEntry.file(
        joinPath([backupRoot.path, 'static', 'hotfixes', 'DefaultGame.ini']),
      ),
      // Don't restore curves.json - keep new version's curves with new entries
      _BackupEntry.file(
        joinPath([backupRoot.path, 'responses', 'modifications-backup.json']),
      ),
      _BackupEntry.file(
        joinPath([backupRoot.path, 'responses', 'datatables-ui.json']),
      ),
      _BackupEntry.file(
        joinPath([backupRoot.path, 'src', 'config', 'config.ini']),
      ),
      _BackupEntry.dir(
        joinPath([backupRoot.path, 'public', 'items', 'custom-groups']),
      ),
    ];

    for (final entry in entries) {
      final target = joinPath([
        backendRoot,
        ...entry.relativeParts(backupRoot.path),
      ]);
      if (entry.isDir) {
        final dir = Directory(entry.path);
        if (!dir.existsSync()) continue;
        await _copyDirectory(dir, Directory(target));
      } else {
        final file = File(entry.path);
        if (!file.existsSync()) continue;
        await File(target).parent.create(recursive: true);
        await file.copy(target);
      }
    }

    // Restore user-created profiles only (exclude template profiles)
    final profilesSource = Directory(
      joinPath([backupRoot.path, 'static', 'profiles']),
    );
    if (profilesSource.existsSync()) {
      final profilesTarget = Directory(
        joinPath([backendRoot, 'static', 'profiles']),
      );
      await _copyDirectoryExcludingProfiles(
        profilesSource,
        profilesTarget,
        _templateProfiles,
      );
    }

    // Note: Profile Presets (athenaprofiles/Profile Presets) are not backed up or restored
    // They are templates and should not be modified

    await backupRoot.delete(recursive: true);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restored data from previous version.')),
      );
    }
  }

  static String _resolveBackupRoot() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base = localAppData ?? Directory.systemTemp.path;
    return joinPath([base, 'ATLAS', _backupFolderName]);
  }

  static Future<String> _readBackendVersion() async {
    return _readBackendVersionFromCandidates();
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.uri.pathSegments.last;
      final newPath = joinPath([destination.path, name]);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  static const Set<String> _templateProfiles = {
    'profile_athena.json',
    'profile_campaign.json',
    'profile_collections.json',
    'profile_common_core.json',
    'profile_common_public.json',
    'profile_creative.json',
    'profile_metadata.json',
    'profile_outpost0.json',
    'profile_profile0.json',
    'profile_theater0.json',
  };

  static Future<void> _copyDirectoryExcludingProfiles(
    Directory source,
    Directory destination,
    Set<String> excludeFiles, {
    bool isRootLevel = true,
  }) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.uri.pathSegments.last;
      // Only exclude template files at root level, not in user subfolders
      if (isRootLevel && excludeFiles.contains(name)) continue;
      final newPath = joinPath([destination.path, name]);
      if (entity is Directory) {
        await _copyDirectoryExcludingProfiles(
          entity,
          Directory(newPath),
          excludeFiles,
          isRootLevel: false,
        );
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}

class _BackupEntry {
  _BackupEntry._(this.path, this.isDir);

  final String path;
  final bool isDir;

  static _BackupEntry dir(String path) => _BackupEntry._(path, true);
  static _BackupEntry file(String path) => _BackupEntry._(path, false);

  List<String> relativeParts(String root) {
    final normalizedRoot = root.replaceAll('\\', '/');
    final normalizedPath = path.replaceAll('\\', '/');
    if (!normalizedPath.startsWith(normalizedRoot)) {
      return normalizedPath.split('/');
    }
    final relative = normalizedPath
        .substring(normalizedRoot.length)
        .replaceFirst(RegExp('^/'), '');
    if (relative.isEmpty) return [];
    return relative.split('/');
  }
}

String _formatVersion(String version) {
  final trimmed = version.trim();
  return trimmed.startsWith('v') ? trimmed : 'v$trimmed';
}

Future<String> _readBackendVersionFromCandidates() async {
  final packagePaths = <String>[
    joinPath([getBackendRoot(), 'package.json']),
    joinPath([getInstallationRoot(), 'package.json']),
    joinPath([Directory.current.path, 'package.json']),
  ];
  final seen = <String>{};
  for (final path in packagePaths) {
    if (!seen.add(path)) continue;
    final packageFile = File(path);
    if (!await packageFile.exists()) continue;
    try {
      final json =
          jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
      final version = json['version']?.toString().trim();
      if (version != null && version.isNotEmpty) {
        return version;
      }
    } catch (_) {
      // Continue to the next candidate.
    }
  }

  return '';
}

String _normalizeVersion(String version) {
  final trimmed = version.trim();
  return trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
}

int _compareVersions(String left, String right) {
  final leftParts = left
      .split('.')
      .map(int.tryParse)
      .map((v) => v ?? 0)
      .toList();
  final rightParts = right
      .split('.')
      .map(int.tryParse)
      .map((v) => v ?? 0)
      .toList();
  final maxLen = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var i = 0; i < maxLen; i++) {
    final l = i < leftParts.length ? leftParts[i] : 0;
    final r = i < rightParts.length ? rightParts[i] : 0;
    if (l == r) continue;
    return l > r ? 1 : -1;
  }
  return 0;
}

bool _isNewerVersion(String latest, String current) {
  return _compareVersions(
        _normalizeVersion(latest),
        _normalizeVersion(current),
      ) >
      0;
}

String _formatReleaseDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[date.month - 1];
  return '$month ${date.day}, ${date.year}';
}

class DataService {
  static const Set<String> _profileTemplateFiles = {
    'profile_athena.json',
    'profile_campaign.json',
    'profile_collections.json',
    'profile_common_core.json',
    'profile_common_public.json',
    'profile_creative.json',
    'profile_metadata.json',
    'profile_outpost0.json',
    'profile_profile0.json',
    'profile_theater0.json',
  };
  static const String _profileTemplateBackupDirName = '.defaults';

  static Future<void> clearBackendData(BuildContext context) async {
    final confirm = await _confirmDialog(
      context,
      'Clear all backend data? This will reset user Profiles, Client settings, CurveTables, and Straight Bloom.',
    );
    if (!confirm) return;
    final profilesDir = Directory(
      joinPath([getBackendRoot(), 'static', 'profiles']),
    );
    final clientSettingsDir = Directory(
      joinPath([getBackendRoot(), 'static', 'ClientSettings']),
    );
    final iniFile = File(BackendPaths.defaultGameIni);
    final curvesFile = File(BackendPaths.curvesJson);
    final backupFile = File(BackendPaths.modificationsBackup);
    final sniperFile = File(BackendPaths.sniperJson);

    if (await profilesDir.exists()) {
      await _ensureProfileTemplateBackup(profilesDir);
      await for (final entity in profilesDir.list()) {
        final name = entity.uri.pathSegments.last;
        if (_profileTemplateFiles.contains(name)) continue;
        await entity.delete(recursive: true);
      }
      await _restoreProfileTemplates(profilesDir);
    }

    if (await clientSettingsDir.exists()) {
      await for (final entity in clientSettingsDir.list()) {
        final name = entity.uri.pathSegments.last;
        if (name.toLowerCase() == 'config') continue;
        await entity.delete(recursive: true);
      }
    }

    if (await iniFile.exists()) {
      if (await sniperFile.exists()) {
        await StraightBloomService.setEnabled(false);
      }
    }

    if (await iniFile.exists() && await curvesFile.exists()) {
      var content = await iniFile.readAsString();
      content = content.replaceAll(
        RegExp('^\\+CurveTable=.*\$', multiLine: true),
        '',
      );
      content = content.replaceAll(RegExp('\n\n+'), '\n');
      await iniFile.writeAsString(content);
      final curves =
          jsonDecode(await curvesFile.readAsString()) as Map<String, dynamic>;
      final keysToRemove = curves.entries
          .where((e) => (e.value as Map<String, dynamic>)['isCustom'] == true)
          .map((e) => e.key)
          .toList();
      for (final key in keysToRemove) {
        curves.remove(key);
      }
      await curvesFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(curves),
      );
      await backupFile.writeAsString(jsonEncode({'curveTableLines': []}));
    }
    final current = await ConfigService.load();
    await ConfigService.save(
      current.copyWith(
        backgroundImagePath: '',
        backgroundBlur: 15,
        backgroundParticlesOpacity: 1.0,
      ),
    );
    appBackgroundPath.value = '';
    appBackgroundBlur.value = 15;
    appBackgroundParticlesOpacity.value = 1.0;

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backend data cleared.')));
    }
  }

  static Future<void> exportData(BuildContext context) async {
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    final defaultGameDir = Directory(
      joinPath([exportsRoot.path, 'DefaultGame']),
    );
    final profilesDir = Directory(joinPath([exportsRoot.path, 'Profiles']));
    final clientDir = Directory(joinPath([exportsRoot.path, 'ClientSettings']));
    if (await _hasExistingExport(defaultGameDir, profilesDir, clientDir)) {
      final confirm = await _confirmDialog(
        context,
        'Exports already exist. Overwrite them?',
      );
      if (!confirm) return;
      await _clearDirectory(defaultGameDir);
      await _clearDirectory(profilesDir);
      await _clearDirectory(clientDir);
    }
    await defaultGameDir.create(recursive: true);
    await profilesDir.create(recursive: true);
    await clientDir.create(recursive: true);
    await _clearNonDirectoryEntries(profilesDir);
    await _clearNonDirectoryEntries(clientDir);

    final iniSource = File(BackendPaths.defaultGameIni);
    var exportedDefaultGame = false;
    if (await iniSource.exists()) {
      await iniSource.copy(joinPath([defaultGameDir.path, 'DefaultGame.ini']));
      exportedDefaultGame = true;
    }

    final profilesExported = await _copyNonEmptyChildDirs(
      Directory(joinPath([getBackendRoot(), 'static', 'profiles'])),
      profilesDir,
      skipDirs: {_profileTemplateBackupDirName},
    );
    final clientExported = await _copyNonEmptyChildDirs(
      Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings'])),
      clientDir,
    );

    await _clearNonDirectoryEntries(profilesDir);
    await _clearNonDirectoryEntries(clientDir);

    if (!exportedDefaultGame && profilesExported == 0 && clientExported == 0) {
      await _deleteIfEmpty(profilesDir);
      await _deleteIfEmpty(clientDir);
      await _deleteIfEmpty(defaultGameDir);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No data found to export.')),
        );
      }
      return;
    }

    if (context.mounted) {
      await _showExportSummary(
        context,
        exportedDefaultGame: exportedDefaultGame,
        profilesExported: profilesExported,
        clientExported: clientExported,
      );
    }
  }

  static Future<void> importData(BuildContext context) async {
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    final defaultGameDir = Directory(
      joinPath([exportsRoot.path, 'DefaultGame']),
    );
    final profilesDir = Directory(joinPath([exportsRoot.path, 'Profiles']));
    final clientDir = Directory(joinPath([exportsRoot.path, 'ClientSettings']));
    if (!await _hasExistingExport(defaultGameDir, profilesDir, clientDir)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No exported data found.')),
        );
      }
      return;
    }
    final confirm = await _confirmDialog(
      context,
      'Importing will overwrite existing data. Continue?',
    );
    if (!confirm) return;

    await _importFolderChildren(
      profilesDir,
      Directory(joinPath([getBackendRoot(), 'static', 'profiles'])),
      skipFiles: _profileTemplateFiles,
      skipDirs: {_profileTemplateBackupDirName},
      onlyDirs: true,
    );
    await _importFolderChildren(
      clientDir,
      Directory(joinPath([getBackendRoot(), 'static', 'ClientSettings'])),
      onlyDirs: true,
    );
    // Profiles + client settings only: skip DefaultGame.ini imports.

    // Clear profile cache on backend
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:3551/atlas/clear-profile-cache'),
      );
      await request.close();
      client.close();
    } catch (_) {
      // Backend might not be running, that's okay
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Import complete. Changes will be visible on next login.',
          ),
        ),
      );
    }
  }

  static Future<void> clearExportedData(BuildContext context) async {
    final confirm = await _confirmDialog(
      context,
      'Clear exported data? This will remove all user Profiles, Client Settings, and DefaultGame.ini from exports/.',
    );
    if (!confirm) return;
    final exportsRoot = Directory(joinPath([getBackendRoot(), 'exports']));
    await _clearDirectory(exportsRoot);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Exported data cleared.')));
    }
  }

  static Future<bool> _hasExistingExport(
    Directory a,
    Directory b,
    Directory c,
  ) async {
    final aHas = a.existsSync() && a.listSync().isNotEmpty;
    final bHas = b.existsSync() && b.listSync().isNotEmpty;
    final cHas = c.existsSync() && c.listSync().isNotEmpty;
    return aHas || bHas || cHas;
  }

  static Future<void> _showExportSummary(
    BuildContext context, {
    required bool exportedDefaultGame,
    required int profilesExported,
    required int clientExported,
  }) async {
    final lines = <String>[];
    if (exportedDefaultGame) {
      lines.add('DefaultGame.ini');
    }
    if (profilesExported > 0) {
      lines.add(
        'Profiles: $profilesExported folder${profilesExported == 1 ? '' : 's'}',
      );
    }
    if (clientExported > 0) {
      lines.add(
        'ClientSettings: $clientExported folder${clientExported == 1 ? '' : 's'}',
      );
    }
    await _showBlurDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Exported items:'),
            const SizedBox(height: 12),
            for (final line in lines) Text('• $line'),
          ],
        ),
        actions: [
          _HoverScale(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _copyDir(Directory src, Directory dest) async {
    if (!await src.exists()) return;
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final name = entity.uri.pathSegments.last;
      final destPath = joinPath([dest.path, name]);
      if (entity is Directory) {
        await _copyDir(entity, Directory(destPath));
      } else if (entity is File) {
        await entity.copy(destPath);
      }
    }
  }

  static Future<int> _copyNonEmptyChildDirs(
    Directory src,
    Directory dest, {
    Set<String> skipDirs = const {},
  }) async {
    if (!await src.exists()) return 0;
    var copied = 0;
    await for (final entity in src.list(recursive: false)) {
      if (entity is Directory) {
        final name = _basename(entity.path);
        if (skipDirs.contains(name) || name.startsWith('.')) continue;
        if (!await _dirHasFiles(entity)) continue;
        await dest.create(recursive: true);
        await _copyDir(entity, Directory(joinPath([dest.path, name])));
        copied++;
      }
    }
    return copied;
  }

  static Future<bool> _dirHasFiles(Directory dir) async {
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) return true;
    }
    return false;
  }

  static Future<void> _clearDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: false)) {
      await entity.delete(recursive: true);
    }
  }

  static Future<void> _clearNonDirectoryEntries(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: false)) {
      if (entity is! Directory) {
        await entity.delete();
      }
    }
  }

  static Future<void> _deleteIfEmpty(Directory dir) async {
    if (!await dir.exists()) return;
    final isEmpty = await dir.list(recursive: false).isEmpty;
    if (isEmpty) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> _importFolderChildren(
    Directory src,
    Directory dest, {
    Set<String> skipFiles = const {},
    Set<String> skipDirs = const {},
    bool onlyDirs = false,
  }) async {
    if (!await src.exists()) return;
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final name = _basename(entity.path);
      if (entity is Directory) {
        if (skipDirs.contains(name)) continue;
        await _copyDir(entity, Directory(joinPath([dest.path, name])));
      } else if (!onlyDirs && entity is File) {
        if (skipFiles.contains(name)) continue;
        await entity.copy(joinPath([dest.path, name]));
      }
    }
  }

  static Future<void> _reorderDefaultGameHotfixBlocks(String iniPath) async {
    final iniFile = File(iniPath);
    if (!await iniFile.exists()) return;
    var content = await iniFile.readAsString();
    final curveRegex = RegExp('^;?\\+CurveTable=.*\$', multiLine: true);
    final curveLines = curveRegex
        .allMatches(content)
        .map((m) => m.group(0)!)
        .toList();
    content = content.replaceAll(curveRegex, '');

    final sniperFile = File(BackendPaths.sniperJson);
    final straightLines = <String>[];
    if (await sniperFile.exists()) {
      final lines =
          (jsonDecode(await sniperFile.readAsString())
                  as Map<String, dynamic>)['lines']
              as List<dynamic>;
      for (final line in lines.cast<String>()) {
        if (content.contains(line)) {
          straightLines.add(line);
          content = content.replaceAll(line, '');
        }
        final commented = ';$line';
        if (content.contains(commented)) {
          straightLines.add(commented);
          content = content.replaceAll(commented, '');
        }
      }
    }

    content = content.replaceAll(BackendPaths.straightBloomComment, '');
    content = content.replaceAll(BackendPaths.curveTableComment, '');
    content = content.replaceAll(RegExp('\n\n+'), '\n');

    final linesOut = content.split('\n').toList();
    var assetIndex = linesOut.indexWhere(
      (line) => line.trim() == '[AssetHotfix]',
    );
    if (assetIndex == -1) {
      linesOut.add('[AssetHotfix]');
      assetIndex = linesOut.length - 1;
    }

    var insertAt = assetIndex + 1;
    final block = <String>[];
    if (straightLines.isNotEmpty) {
      block.add(BackendPaths.straightBloomComment);
      block.addAll(straightLines);
    }
    if (curveLines.isNotEmpty) {
      if (block.isNotEmpty) block.add('');
      block.add(BackendPaths.curveTableComment);
      block.addAll(curveLines);
    }
    if (block.isNotEmpty) {
      linesOut.insertAll(insertAt, block);
    }
    await iniFile.writeAsString(linesOut.join('\n'));
  }

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    for (var i = parts.length - 1; i >= 0; i--) {
      final part = parts[i].trim();
      if (part.isNotEmpty) return part;
    }
    return path;
  }

  static Future<void> _ensureProfileTemplateBackup(
    Directory profilesDir,
  ) async {
    final backupDir = Directory(
      joinPath([profilesDir.path, _profileTemplateBackupDirName]),
    );
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    for (final name in _profileTemplateFiles) {
      final source = File(joinPath([profilesDir.path, name]));
      if (!await source.exists()) continue;
      final backup = File(joinPath([backupDir.path, name]));
      if (!await backup.exists()) {
        await source.copy(backup.path);
      }
    }
  }

  static Future<void> _restoreProfileTemplates(Directory profilesDir) async {
    final backupDir = Directory(
      joinPath([profilesDir.path, _profileTemplateBackupDirName]),
    );
    if (!await backupDir.exists()) return;
    for (final name in _profileTemplateFiles) {
      final backup = File(joinPath([backupDir.path, name]));
      if (!await backup.exists()) continue;
      await backup.copy(joinPath([profilesDir.path, name]));
    }
  }

  static Future<bool> _confirmDialog(
    BuildContext context,
    String message,
  ) async {
    return (await _showBlurDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(message),
            actions: [
              _HoverScale(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              _HoverScale(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes'),
                ),
              ),
            ],
          ),
        )) ??
        false;
  }
}

Future<String?> _promptValue(
  BuildContext context,
  String name, {
  String? defaultValue,
}) async {
  bool isValidNumeric(String value) =>
      RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(value.trim());
  final controller = TextEditingController();
  final result = await _showBlurDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Set value for $name'),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-.]')),
        ],
        decoration: InputDecoration(
          labelText: 'Value',
          hintText: defaultValue,
          hintStyle: TextStyle(color: Colors.grey.shade600),
        ),
      ),
      actions: [
        _HoverScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
        _HoverScale(
          child: ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty || !isValidNumeric(value)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid numeric value.')),
                );
                return;
              }
              Navigator.pop(context, value);
            },
            child: const Text('Save'),
          ),
        ),
      ],
    ),
  );
  return result?.isEmpty == true ? null : result;
}

Future<Map<String, String>?> _promptAdvancedSettings(
  BuildContext context,
  List<String> fields,
  Map<String, String> currentValues,
  String defaultValue,
) async {
  bool isValidNumeric(String value) =>
      RegExp(r'^[+-]?(?:\d+\.?\d*|\.\d+)$').hasMatch(value.trim());

  final controllers = <String, TextEditingController>{};
  for (final field in fields) {
    controllers[field] = TextEditingController(
      text: currentValues[field] ?? defaultValue,
    );
  }

  final result = await _showBlurDialog<Map<String, String>>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Advanced Settings'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: fields.map((field) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controllers[field],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: field,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        _HoverScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
        _HoverScale(
          child: ElevatedButton(
            onPressed: () {
              final values = <String, String>{};
              for (final field in fields) {
                final value = controllers[field]!.text.trim();
                if (value.isEmpty || !isValidNumeric(value)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Enter a valid numeric value for $field.'),
                    ),
                  );
                  return;
                }
                values[field] = value;
              }
              Navigator.pop(context, values);
            },
            child: const Text('Save All'),
          ),
        ),
      ],
    ),
  );

  // Dispose controllers
  for (final controller in controllers.values) {
    controller.dispose();
  }

  return result;
}

Future<void> _showCurveImportSummary(
  BuildContext context,
  Map<String, List<String>> grouped, {
  required List<_ImportCurveDraft> missing,
}) async {
  if (grouped.isEmpty) return;
  final lines = _buildCurveImportSummaryLines(grouped, missing);

  await _showBlurDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('CurveTables imported'),
      content: SizedBox(
        width: 320,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${grouped.length} CurveTable${grouped.length == 1 ? '' : 's'} imported.',
                ),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('New entries: ${missing.length}'),
                ],
                const SizedBox(height: 12),
                for (final line in lines) Text('• $line'),
              ],
            ),
          ),
        ),
      ),
      actions: [
        _HoverScale(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ),
      ],
    ),
  );
}

List<String> _buildCurveImportSummaryLines(
  Map<String, List<String>> grouped,
  List<_ImportCurveDraft> missing,
) {
  if (grouped.isEmpty) return const [];
  final missingKeys = missing
      .map((entry) => '${entry.pathPart}|||${entry.key}')
      .toSet();
  final labels = <String, Map<String, dynamic>>{};
  for (final entry in grouped.entries) {
    final parts = entry.key.split('|||');
    final key = parts.length > 1 ? parts[1] : entry.key;
    final label = _humanizeCurveKey(key);
    final count = entry.value.length;
    final isNew = missingKeys.contains(entry.key);
    final existing = labels[label];
    if (existing == null) {
      labels[label] = {'count': 1, 'lines': count, 'isNew': isNew};
    } else {
      labels[label] = {
        'count': (existing['count'] as int) + 1,
        'lines': (existing['lines'] as int) + count,
        'isNew': (existing['isNew'] as bool) || isNew,
      };
    }
  }
  return labels.entries.map((entry) {
    final label = entry.key;
    final count = entry.value['count'] as int;
    final totalLines = entry.value['lines'] as int;
    final isNew = entry.value['isNew'] as bool;
    final countSuffix = count > 1 ? ' ×$count' : '';
    final linesSuffix = totalLines > count ? ' ($totalLines lines)' : '';
    return '${isNew ? "New: " : ""}$label$countSuffix$linesSuffix';
  }).toList();
}

Future<void> _showModificationsIniImportSummary(
  BuildContext context, {
  required bool attemptedCurves,
  required bool attemptedDataTables,
  required Map<String, List<String>> curveGrouped,
  required List<_ImportCurveDraft> curveMissing,
  required int curveLines,
  required int dataTableLines,
}) async {
  final curveSummary = _buildCurveImportSummaryLines(curveGrouped, curveMissing);

  await _showBlurDialog<void>(
    context: context,
    builder: (dialogContext) {
      Widget buildCard({
        required IconData icon,
        required String title,
        required Widget child,
      }) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _onSurface(dialogContext, 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: _onSurface(dialogContext, 0.65)),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        );
      }

      final curveSummaryScrollController = ScrollController();

      final curvesCard = buildCard(
        icon: Icons.show_chart_rounded,
        title: 'CurveTables',
        child: !attemptedCurves
            ? Text(
                'Disabled in Modifications.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color: _onSurface(dialogContext, 0.6),
                    ),
              )
            : curveLines == 0
                ? Text(
                    'No CurveTable entries found.',
                    style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                          color: _onSurface(dialogContext, 0.6),
                        ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${curveGrouped.length} CurveTable${curveGrouped.length == 1 ? '' : 's'} imported ($curveLines lines).',
                      ),
                      if (curveMissing.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('New entries: ${curveMissing.length}'),
                      ],
                      if (curveSummary.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: Scrollbar(
                              controller: curveSummaryScrollController,
                              thumbVisibility: true,
                              thickness: 6,
                              radius: const Radius.circular(12),
                              child: SingleChildScrollView(
                                controller: curveSummaryScrollController,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final line in curveSummary)
                                      Text(
                                        '• $line',
                                        style: Theme.of(dialogContext)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: _onSurface(
                                                dialogContext,
                                                0.82,
                                              ),
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
      );

      final dataTablesCard = buildCard(
        icon: Icons.grid_view_rounded,
        title: 'DataTables',
        child: !attemptedDataTables
            ? Text(
                'Disabled in Modifications.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color: _onSurface(dialogContext, 0.6),
                    ),
              )
            : dataTableLines == 0
                ? Text(
                    'No DataTable entries found.',
                    style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                          color: _onSurface(dialogContext, 0.6),
                        ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$dataTableLines DataTable ${dataTableLines == 1 ? 'entry' : 'entries'} imported.',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You can view and edit these in the DataTables tab.',
                        style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                              color: _onSurface(dialogContext, 0.72),
                            ),
                      ),
                    ],
                  ),
      );

      return AlertDialog(
        title: const Text('DefaultGame.ini imported'),
        content: SizedBox(
          width: 720,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 680;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: curvesCard),
                    const SizedBox(width: 12),
                    Expanded(child: dataTablesCard),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  curvesCard,
                  const SizedBox(height: 12),
                  dataTablesCard,
                ],
              );
            },
          ),
        ),
        actions: [
          _HoverScale(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ),
        ],
      );
    },
  );
}

class _ParsedCurveLines {
  const _ParsedCurveLines({
    required this.pathPart,
    required this.key,
    required this.lines,
    required this.staticValue,
  });

  final String pathPart;
  final String key;
  final List<String> lines;
  final String staticValue;
}

class _CurveLineParts {
  const _CurveLineParts({
    required this.pathPart,
    required this.key,
    required this.row,
    required this.value,
  });

  final String pathPart;
  final String key;
  final String row;
  final String value;
}

_CurveLineParts? _splitCurveLine(String line) {
  final regex = RegExp('^\\+CurveTable=(.+?);RowUpdate;(.+?);(\\d+);(.+)\$');
  final match = regex.firstMatch(line.trim());
  if (match == null) return null;
  return _CurveLineParts(
    pathPart: match.group(1)!,
    key: match.group(2)!,
    row: match.group(3)!,
    value: match.group(4)!,
  );
}

String _replaceCurveLineValue(String line, String value) {
  final parts = _splitCurveLine(line);
  if (parts == null) return line;
  return '+CurveTable=${parts.pathPart};RowUpdate;${parts.key};${parts.row};$value';
}

_ParsedCurveLines? _parseCurveLines(String raw) {
  final cleaned = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (cleaned.isEmpty) return null;
  String? pathPart;
  String? key;
  String? staticValue;
  for (final line in cleaned) {
    final parts = _splitCurveLine(line);
    if (parts == null) return null;
    final currentPath = parts.pathPart;
    final currentKey = parts.key;
    final value = parts.value;
    pathPart ??= currentPath;
    key ??= currentKey;
    staticValue ??= value;
    if (pathPart != currentPath || key != currentKey) return null;
  }
  return _ParsedCurveLines(
    pathPart: pathPart!,
    key: key!,
    lines: cleaned,
    staticValue: staticValue ?? '0',
  );
}

String _extractLastHotfixBlock(String content) {
  final lines = content.split('\n');
  final assetIndex = lines.indexWhere((line) => line.trim() == '[AssetHotfix]');
  if (assetIndex == -1) return '';
  var lastCommentIndex = -1;
  for (var i = assetIndex + 1; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed.startsWith('#')) {
      lastCommentIndex = i;
    }
  }
  if (lastCommentIndex == -1) return '';
  final buffer = <String>[];
  for (var i = lastCommentIndex + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().startsWith('#') || line.trim().startsWith('[')) break;
    buffer.add(line);
  }
  return buffer.join('\n');
}

Future<List<CustomCurveInput>?> _promptCustomCurves(
  BuildContext context,
  List<CustomCurveGroupInfo> groups,
) async {
  final drafts = <_CustomCurveDraft>[_CustomCurveDraft()];
  final groupNameController = TextEditingController();
  String? newGroupImagePath;
  String selectedGroupId = '_new';
  String? errorText;

  final result = await _showBlurDialog<List<CustomCurveInput>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add Custom Curves'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedGroupId,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: [
                    ...groups.map(
                      (group) => DropdownMenuItem(
                        value: group.id,
                        child: Text(group.name),
                      ),
                    ),
                    const DropdownMenuItem(
                      value: '_new',
                      child: Text('Create new group'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      selectedGroupId = value;
                      errorText = null;
                    });
                  },
                ),
                if (selectedGroupId == '_new') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: groupNameController,
                    decoration: const InputDecoration(labelText: 'Group name'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          newGroupImagePath == null
                              ? 'No group image selected'
                              : newGroupImagePath!
                                    .split(Platform.pathSeparator)
                                    .last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      _HoverScale(
                        child: TextButton.icon(
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                            );
                            if (picked == null ||
                                picked.files.single.path == null) {
                              return;
                            }
                            setState(() {
                              newGroupImagePath = picked.files.single.path;
                              errorText = null;
                            });
                          },
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Choose image'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Curves',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                ...drafts.asMap().entries.map((entry) {
                  final index = entry.key;
                  final draft = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: draft.nameController,
                                  decoration: InputDecoration(
                                    labelText: 'Curve name ${index + 1}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                children: [
                                  const Text('Static'),
                                  Switch(
                                    value: draft.isStatic,
                                    onChanged: (value) =>
                                        setState(() => draft.isStatic = value),
                                  ),
                                ],
                              ),
                              if (drafts.length > 1)
                                _HoverScale(
                                  child: IconButton(
                                    tooltip: 'Remove curve',
                                    onPressed: () =>
                                        setState(() => drafts.removeAt(index)),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: draft.linesController,
                            minLines: 3,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'CurveTable line(s)',
                              hintText:
                                  '+CurveTable=/Game/...;RowUpdate;Key;0;Value',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _HoverScale(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => drafts.add(_CustomCurveDraft())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add another curve'),
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final isNewGroup = selectedGroupId == '_new';
                final groupName = isNewGroup
                    ? groupNameController.text.trim()
                    : groups
                          .firstWhere((group) => group.id == selectedGroupId)
                          .name;
                final groupImagePath = isNewGroup
                    ? ''
                    : (groups
                              .firstWhere(
                                (group) => group.id == selectedGroupId,
                              )
                              .imagePath ??
                          '');
                final groupImageSourcePath = isNewGroup
                    ? (newGroupImagePath ?? '')
                    : '';

                if (isNewGroup && groupName.isEmpty) {
                  setState(() => errorText = 'Group name is required.');
                  return;
                }
                if (isNewGroup &&
                    (newGroupImagePath == null ||
                        newGroupImagePath!.trim().isEmpty)) {
                  setState(() => errorText = 'Group image is required.');
                  return;
                }
                if (drafts.isEmpty) {
                  setState(() => errorText = 'Add at least one curve.');
                  return;
                }

                final groupId = isNewGroup
                    ? 'custom-${DateTime.now().millisecondsSinceEpoch}'
                    : selectedGroupId;
                final inputs = <CustomCurveInput>[];
                for (final draft in drafts) {
                  final curveName = draft.nameController.text.trim();
                  if (curveName.isEmpty) {
                    setState(() => errorText = 'Each curve must have a name.');
                    return;
                  }
                  final parsed = _parseCurveLines(draft.linesController.text);
                  if (parsed == null) {
                    setState(
                      () => errorText =
                          'Enter valid +CurveTable line(s) with matching path/key.',
                    );
                    return;
                  }
                  inputs.add(
                    CustomCurveInput(
                      name: curveName,
                      key: parsed.key,
                      pathPart: parsed.pathPart,
                      lines: parsed.lines,
                      staticValue: parsed.staticValue,
                      isStatic: draft.isStatic,
                      groupId: groupId,
                      groupName: groupName,
                      groupImagePath: groupImagePath,
                      groupImageSourcePath: groupImageSourcePath,
                    ),
                  );
                }
                Navigator.pop(context, inputs);
              },
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<CustomDataTableInput?> _promptCustomDataTable(
  BuildContext context, {
  CustomDataTableInput? existingInput,
}) async {
  // Determine which fields to show based on existing data
  final bool hasDamageFields = existingInput == null || 
      (existingInput.damagePB.isNotEmpty || existingInput.envDamage.isNotEmpty);
  final bool hasClipSize = existingInput == null || 
      (existingInput.clipSize?.isNotEmpty ?? false);
  final bool hasReloadTime = existingInput == null || 
      (existingInput.reloadTime?.isNotEmpty ?? false);

  final weaponNameController = TextEditingController(
    text: existingInput?.weaponName ?? '',
  );
  final weaponIdController = TextEditingController(
    text: existingInput?.weaponIdLine ?? '',
  );
  final damagePBController = TextEditingController(
    text: existingInput?.damagePB ?? '50',
  );
  final envDamageController = TextEditingController(
    text: existingInput?.envDamage ?? '50',
  );
  final damageMidController = TextEditingController(
    text: existingInput?.damageMid ?? '40',
  );
  final damageLongController = TextEditingController(
    text: existingInput?.damageLong ?? '30',
  );
  final damageMaxRangeController = TextEditingController(
    text: existingInput?.damageMaxRange ?? '20',
  );
  final clipSizeController = TextEditingController(
    text: existingInput?.clipSize ?? '30',
  );
  final reloadTimeController = TextEditingController(
    text: existingInput?.reloadTime ?? '2.0',
  );

  // Rarity configuration
  final rarities = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary'];
  final raritySuffixes = {
    'Common': 'C',
    'Uncommon': 'UC',
    'Rare': 'R',
    'Epic': 'VR',
    'Legendary': 'SR',
  };
  String selectedRarity = 'Common';

  // Store damage values per rarity
  final rarityDamageValues = <String, Map<String, String>>{};
  if (existingInput?.rarityConfigs != null) {
    rarityDamageValues.addAll(existingInput!.rarityConfigs!);
  }

  // Helper to save current values to the selected rarity
  void saveCurrentRarityValues() {
    if (hasDamageFields) {
      rarityDamageValues[selectedRarity] = {
        'damagePB': damagePBController.text,
        'envDamage': envDamageController.text,
        'damageMid': damageMidController.text,
        'damageLong': damageLongController.text,
        'damageMaxRange': damageMaxRangeController.text,
        'weaponIdLine': weaponIdController.text,
      };
    }
  }

  // Helper to load values for a rarity
  void loadRarityValues(String rarity) {
    if (!hasDamageFields) return;
    
    final values = rarityDamageValues[rarity];
    if (values != null) {
      damagePBController.text = values['damagePB'] ?? '50';
      envDamageController.text = values['envDamage'] ?? '50';
      damageMidController.text = values['damageMid'] ?? '40';
      damageLongController.text = values['damageLong'] ?? '30';
      damageMaxRangeController.text = values['damageMaxRange'] ?? '20';
      weaponIdController.text = values['weaponIdLine'] ?? '';
    } else {
      // Default values
      damagePBController.text = '50';
      envDamageController.text = '50';
      damageMidController.text = '40';
      damageLongController.text = '30';
      damageMaxRangeController.text = '20';
    }
  }

  // Helper to update weaponId based on rarity
  void updateWeaponIdForRarity(String newRarity) {
    final currentId = weaponIdController.text.trim();
    if (currentId.isEmpty) return;

    // Replace the rarity suffix in the weapon ID
    String newId = currentId;
    for (final entry in raritySuffixes.entries) {
      final pattern = '_${entry.value}_';
      if (currentId.contains(pattern)) {
        newId = currentId.replaceFirst(
          pattern,
          '_${raritySuffixes[newRarity]}_',
        );
        weaponIdController.text = newId;
        return;
      }
    }
  }

  String? imagePath = existingInput?.imageSourcePath;
  bool advancedMode = existingInput?.advancedMode ?? false;
  String? errorText;

  final result = await _showBlurDialog<CustomDataTableInput>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add Custom DataTable'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: weaponNameController,
                  decoration: InputDecoration(
                    labelText: 'Weapon Name',
                    hintText: 'Assault Rifle',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weaponIdController,
                  decoration: InputDecoration(
                    labelText: 'DataTable RowName',
                    hintText: 'Assault_Auto_Athena_C_Ore_T03',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  onChanged: (value) {
                    // If user manually edits, update it for current rarity
                    setState(() => errorText = null);
                  },
                ),
                const SizedBox(height: 12),
                if (hasDamageFields) ...[DropdownButtonFormField<String>(
                  value: selectedRarity,
                  decoration: const InputDecoration(
                    labelText: 'Rarity',
                    border: OutlineInputBorder(),
                  ),
                  items: rarities.map((rarity) {
                    return DropdownMenuItem(
                      value: rarity,
                      child: Row(
                        children: [
                          Text(rarity),
                          const SizedBox(width: 8),
                          Text(
                            '(${raritySuffixes[rarity]})',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (newRarity) {
                    if (newRarity == null) return;
                    setState(() {
                      // Save current rarity's values before switching
                      saveCurrentRarityValues();

                      // Switch to new rarity
                      selectedRarity = newRarity;

                      // Load values for new rarity (or defaults)
                      loadRarityValues(newRarity);

                      // Update weaponId to match new rarity
                      updateWeaponIdForRarity(newRarity);

                      errorText = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                ],
                if (!hasDamageFields) const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        imagePath == null
                            ? 'No image selected'
                            : imagePath!.split(Platform.pathSeparator).last,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _HoverScale(
                      child: TextButton.icon(
                        onPressed: () async {
                          final picked = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                          );
                          if (picked == null ||
                              picked.files.single.path == null) {
                            return;
                          }
                          setState(() {
                            imagePath = picked.files.single.path;
                            errorText = null;
                          });
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Choose image'),
                      ),
                    ),
                  ],
                ),
                if (hasDamageFields) ...[const SizedBox(height: 16),
                TextField(
                  controller: damagePBController,
                  decoration: InputDecoration(
                    labelText: advancedMode ? 'DamagePB' : 'Base Damage',
                    hintText: '50',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  keyboardType: TextInputType.number,
                ),],
                if (hasDamageFields && advancedMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: damageMidController,
                    decoration: InputDecoration(
                      labelText: 'DamageMid',
                      hintText: '40',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: damageLongController,
                    decoration: InputDecoration(
                      labelText: 'DamageLong',
                      hintText: '30',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: damageMaxRangeController,
                    decoration: InputDecoration(
                      labelText: 'DamageMaxRange',
                      hintText: '20',
                      hintStyle: TextStyle(color: Colors.grey.shade600),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                if (hasDamageFields) ...[const SizedBox(height: 12),
                TextField(
                  controller: envDamageController,
                  decoration: InputDecoration(
                    labelText: 'Base Environmental Damage',
                    hintText: '50',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  keyboardType: TextInputType.number,
                ),],
                if (hasClipSize) ...[const SizedBox(height: 16),
                TextField(
                  controller: clipSizeController,
                  decoration: InputDecoration(
                    labelText: 'Clip Size',
                    hintText: '30',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  keyboardType: TextInputType.number,
                ),],
                if (hasReloadTime) ...[const SizedBox(height: 12),
                TextField(
                  controller: reloadTimeController,
                  decoration: InputDecoration(
                    labelText: 'Reload Time',
                    hintText: '2.0',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),],
                if (hasDamageFields) ...[const SizedBox(height: 16),
                SwitchListTile(
                  value: advancedMode,
                  onChanged: (value) => setState(() => advancedMode = value),
                  title: const Text('Advanced Options'),
                  subtitle: const Text('Configure damage for different ranges'),
                ),],
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final weaponName = weaponNameController.text.trim();
                final weaponId = weaponIdController.text.trim();
                final damagePB = hasDamageFields ? damagePBController.text.trim() : '';
                final envDamage = hasDamageFields ? envDamageController.text.trim() : '';

                if (weaponName.isEmpty) {
                  setState(() => errorText = 'Weapon name is required.');
                  return;
                }
                if (weaponId.isEmpty) {
                  setState(
                    () => errorText = 'DataTable line (weaponId) is required.',
                  );
                  return;
                }
                if (hasDamageFields && damagePB.isEmpty) {
                  setState(() => errorText = 'Base DamagePB is required.');
                  return;
                }
                if (hasDamageFields && envDamage.isEmpty) {
                  setState(
                    () => errorText = 'Base Environmental Damage is required.',
                  );
                  return;
                }

                // Save the current rarity's values before submitting
                if (hasDamageFields) {
                  saveCurrentRarityValues();
                }

                Navigator.pop(
                  context,
                  CustomDataTableInput(
                    weaponName: weaponName,
                    weaponIdLine: weaponId,
                    damagePB: damagePB,
                    envDamage: envDamage,
                    advancedMode: hasDamageFields && advancedMode,
                    imageSourcePath: imagePath,
                    damageMid: (hasDamageFields && advancedMode)
                        ? damageMidController.text.trim()
                        : null,
                    damageLong: (hasDamageFields && advancedMode)
                        ? damageLongController.text.trim()
                        : null,
                    damageMaxRange: (hasDamageFields && advancedMode)
                        ? damageMaxRangeController.text.trim()
                        : null,
                    rarityConfigs: (hasDamageFields && rarityDamageValues.isNotEmpty)
                        ? Map.from(rarityDamageValues)
                        : null,
                    clipSize: (hasClipSize && clipSizeController.text.trim().isNotEmpty)
                        ? clipSizeController.text.trim()
                        : null,
                    reloadTime: (hasReloadTime && reloadTimeController.text.trim().isNotEmpty)
                        ? reloadTimeController.text.trim()
                        : null,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<_CustomGroupEditResult?> _promptEditCustomGroup(
  BuildContext context,
  String groupId,
  String groupName,
) async {
  final nameController = TextEditingController(text: groupName);
  String? newImagePath;
  String? errorText;
  final result = await _showBlurDialog<_CustomGroupEditResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Group'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      newImagePath == null
                          ? 'No new image selected'
                          : newImagePath!.split(Platform.pathSeparator).last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HoverScale(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                        );
                        if (picked == null ||
                            picked.files.single.path == null) {
                          return;
                        }
                        setState(() {
                          newImagePath = picked.files.single.path;
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose image'),
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Group name is required.');
                  return;
                }
                Navigator.pop(
                  context,
                  _CustomGroupEditResult(name: name, imagePath: newImagePath),
                );
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<_CustomCurveEditResult?> _promptEditCustomCurve(
  BuildContext context,
  CurveEntry entry,
  List<CustomCurveGroupInfo> groups,
) async {
  final nameController = TextEditingController(text: entry.name);
  final linesController = TextEditingController(
    text: entry.multiLines.join('\n'),
  );
  bool isStatic = entry.type == 'static';
  String selectedGroupId = entry.groupId ?? groups.first.id;
  String? errorText;

  final result = await _showBlurDialog<_CustomCurveEditResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Edit Custom Curve'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedGroupId,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: groups
                      .map(
                        (group) => DropdownMenuItem(
                          value: group.id,
                          child: Text(group.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      selectedGroupId = value;
                      errorText = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Curve name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Static'),
                    const SizedBox(width: 12),
                    Switch(
                      value: isStatic,
                      onChanged: (value) => setState(() => isStatic = value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linesController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'CurveTable line(s)',
                    hintText: '+CurveTable=/Game/...;RowUpdate;Key;0;Value',
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Curve name is required.');
                  return;
                }
                final parsed = _parseCurveLines(linesController.text);
                if (parsed == null) {
                  setState(
                    () => errorText =
                        'Enter valid +CurveTable line(s) with matching path/key.',
                  );
                  return;
                }
                final groupInfo = groups.firstWhere(
                  (group) => group.id == selectedGroupId,
                );
                Navigator.pop(
                  context,
                  _CustomCurveEditResult(
                    name: name,
                    lines: parsed.lines,
                    staticValue: parsed.staticValue,
                    isStatic: isStatic,
                    key: parsed.key,
                    pathPart: parsed.pathPart,
                    groupId: groupInfo.id,
                    groupName: groupInfo.name,
                    groupImagePath: groupInfo.imagePath,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<CustomCurveGroupInfo?> _promptCreateCustomGroup(
  BuildContext context,
) async {
  final nameController = TextEditingController();
  String? imagePath;
  String? errorText;
  final result = await _showBlurDialog<CustomCurveGroupInfo>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Create Group'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      imagePath == null
                          ? 'No image selected'
                          : imagePath!.split(Platform.pathSeparator).last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _HoverScale(
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                        );
                        if (picked == null ||
                            picked.files.single.path == null) {
                          return;
                        }
                        setState(() {
                          imagePath = picked.files.single.path;
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Choose image'),
                    ),
                  ),
                ],
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
        actions: [
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setState(() => errorText = 'Group name is required.');
                  return;
                }
                if (imagePath == null || imagePath!.trim().isEmpty) {
                  setState(() => errorText = 'Group image is required.');
                  return;
                }
                Navigator.pop(
                  context,
                  CustomCurveGroupInfo(
                    id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    imagePath: imagePath,
                  ),
                );
              },
              child: const Text('Create'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<List<CustomCurveInput>?> _promptImportMissingCurves(
  BuildContext context,
  List<_ImportCurveDraft> missing,
  List<CustomCurveGroupInfo> groups,
) async {
  String? errorText;
  final groupOptions = [...groups];
  if (!groupOptions.any((group) => group.id == 'other')) {
    groupOptions.add(
      const CustomCurveGroupInfo(id: 'other', name: 'Other', imagePath: null),
    );
  }
  if (groupOptions.isNotEmpty) {
    for (final draft in missing) {
      draft.selectedGroupId = '';
    }
  }

  final result = await _showBlurDialog<List<CustomCurveInput>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Name Imported Curves'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...missing.map((draft) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            draft.key,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            draft.pathPart,
                            style: TextStyle(
                              fontSize: 12,
                              color: _onSurface(context, 0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: draft.nameController,
                            decoration: const InputDecoration(
                              labelText: 'Curve name',
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: draft.selectedGroupId.isEmpty
                                ? null
                                : draft.selectedGroupId,
                            decoration: const InputDecoration(
                              labelText: 'Group',
                            ),
                            items: [
                              ...groupOptions.map(
                                (group) => DropdownMenuItem(
                                  value: group.id,
                                  child: Text(group.name),
                                ),
                              ),
                              const DropdownMenuItem(
                                value: '__new__',
                                child: Text('Create new group'),
                              ),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              if (value == '__new__') {
                                final newGroup = await _promptCreateCustomGroup(
                                  context,
                                );
                                if (newGroup != null) {
                                  setState(() {
                                    groupOptions.add(newGroup);
                                    draft.selectedGroupId = newGroup.id;
                                  });
                                }
                                return;
                              }
                              setState(() => draft.selectedGroupId = value);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          _HoverScale(
            child: OutlinedButton(
              onPressed: () {
                final inputs = <CustomCurveInput>[];
                for (final draft in missing) {
                  final name = _humanizeCurveKey(draft.key);
                  final group = groupOptions.firstWhere((g) => g.id == 'other');
                  inputs.add(
                    CustomCurveInput(
                      name: name,
                      key: draft.key,
                      pathPart: draft.pathPart,
                      lines: draft.lines,
                      staticValue: draft.staticValue,
                      isStatic: false,
                      groupId: group.id,
                      groupName: group.name,
                      groupImagePath: '',
                      groupImageSourcePath: '',
                    ),
                  );
                }
                Navigator.pop(context, inputs);
              },
              child: const Text('Continue without naming'),
            ),
          ),
          _HoverScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          _HoverScale(
            child: ElevatedButton(
              onPressed: () {
                final inputs = <CustomCurveInput>[];
                for (final draft in missing) {
                  final name = draft.nameController.text.trim().isEmpty
                      ? _humanizeCurveKey(draft.key)
                      : draft.nameController.text.trim();
                  final groupId = draft.selectedGroupId.isEmpty
                      ? 'other'
                      : draft.selectedGroupId;
                  final group = groupOptions.firstWhere((g) => g.id == groupId);
                  final groupImageSourcePath =
                      (group.imagePath != null &&
                          File(group.imagePath!).existsSync())
                      ? group.imagePath!
                      : '';
                  final groupImagePath = groupImageSourcePath.isEmpty
                      ? (group.imagePath ?? '')
                      : '';
                  inputs.add(
                    CustomCurveInput(
                      name: name,
                      key: draft.key,
                      pathPart: draft.pathPart,
                      lines: draft.lines,
                      staticValue: draft.staticValue,
                      isStatic: false,
                      groupId: group.id,
                      groupName: group.name,
                      groupImagePath: groupImagePath,
                      groupImageSourcePath: groupImageSourcePath,
                    ),
                  );
                }
                Navigator.pop(context, inputs);
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );
  return result;
}

class BackendController extends ChangeNotifier {
  BackendController() {
    _logStore.clear();
  }

  Process? _process;
  Timer? _pollTimer;
  bool isRunning = false;
  bool isStarting = false;
  bool isStopping = false;
  bool isRestarting = false;
  String _statusText = 'Offline';
  Color _statusColor = Colors.redAccent;
  final LogStore _logStore = LogStore.instance;
  DateTime? _backendStartedAt;
  Timer? _logNotifyTimer;
  bool _logNotifyQueued = false;

  String get statusText => _statusText;
  Color get statusColor => _statusColor;
  DateTime? get backendStartedAt => _backendStartedAt;
  List<String> get recentLogs => _logStore.recentLogs;
  List<String> get allLogs => _logStore.allLogs;
  bool get hasProcess => _process != null;
  String get activeProfilesLabel => '28';
  String get exportsLabel => '1,024 files';
  String get lastSyncLabel => '2 minutes ago';

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkBackend(),
    );
    _checkBackend();
  }

  Future<void> ensureStoppedOnLaunch() async {
    final ok = await _pingBackend();
    if (!ok) return;
    _addLog('Backend detected on launch. Stopping until Start is pressed.');
    await _killBackendOnPort(3551);
    _backendStartedAt = null;
    isRunning = false;
    _setStatus('Offline', Colors.redAccent);
    notifyListeners();
  }

  Future<void> startBackend() async {
    if (isStarting || isRestarting || isStopping) return;
    if (isRunning) {
      _addLog('Backend is already running.');
      return;
    }
    if (_process != null) {
      _addLog('Backend is already starting.');
      return;
    }
    if (await _pingBackend(timeout: const Duration(milliseconds: 350))) {
      isRunning = true;
      _backendStartedAt ??= DateTime.now();
      _setStatus('Running', Colors.greenAccent);
      _addLog('Backend already running.');
      notifyListeners();
      return;
    }
    isStarting = true;
    _logStore.clear();
    _backendStartedAt = null;
    _setStatus('Starting...', Colors.orangeAccent);
    _addLog('Starting backend...');
    notifyListeners();

    final backendRoot = getBackendRoot();
    final bunPath = _resolveBunPath(backendRoot);
    final bunAvailable = await _checkBunAvailable(backendRoot, bunPath);
    if (!bunAvailable) {
      _addLog('Bun not found. Install Bun or include tools\\bun\\bun.exe.');
      isStarting = false;
      _setStatus('Bun missing', Colors.redAccent);
      notifyListeners();
      return;
    }

    final nodeModules = Directory('$backendRoot/node_modules');
    if (!nodeModules.existsSync()) {
      _addLog('Installing dependencies (bun install)...');
      final install = await Process.run(bunPath ?? 'bun', [
        'install',
      ], workingDirectory: backendRoot);
      if (install.exitCode != 0) {
        _addLog('Dependency install failed: ${install.stderr}');
        isStarting = false;
        _setStatus('Install failed', Colors.redAccent);
        notifyListeners();
        return;
      }
      _addLog('Dependencies installed.');
    }

    final config = await ConfigService.load();
    final env = Map<String, String>.from(Platform.environment);
    if (config.disableBackendUpdateCheck) {
      env['ATLAS_DISABLE_UPDATE_CHECK'] = '1';
    }

    try {
      _process = await Process.start(
        bunPath ?? 'bun',
        ['run', 'src/index.ts'],
        workingDirectory: backendRoot,
        environment: env,
        mode: ProcessStartMode.detachedWithStdio,
      );
      _backendStartedAt = DateTime.now();
      _setStatus('Starting...', Colors.orangeAccent);
      notifyListeners();
      try {
        _process?.stdout.transform(utf8.decoder).listen(_addLog);
        _process?.stderr.transform(utf8.decoder).listen(_addLog);
      } catch (_) {
        // Detached process may not expose stdio on some platforms.
      }
      _process?.exitCode.then((code) {
        _addLog('Backend exited with code $code');
        _process = null;
        isRunning = false;
        isStarting = false;
        _backendStartedAt = null;
        _setStatus('Offline', Colors.redAccent);
        notifyListeners();
      });

      // Avoid the perceived "startup lag" caused by the 3s poll cadence.
      // Ping aggressively for a short window so the UI flips to Running asap.
      final ready = await _waitForBackendReady();
      if (ready) {
        isRunning = true;
        isStarting = false;
        _backendStartedAt ??= DateTime.now();
        _setStatus('Running', Colors.greenAccent);
        notifyListeners();
      }
    } catch (error) {
      _backendStartedAt = null;
      if (_process != null) {
        // Suppress detached process warning in GUI logs.
        isRunning = false;
        isStarting = false;
        _setStatus('Starting...', Colors.orangeAccent);
        notifyListeners();
      } else {
        _addLog('Failed to start backend: $error');
        isRunning = false;
        isStarting = false;
        _setStatus('Start failed', Colors.redAccent);
        notifyListeners();
      }
    }
  }

  Future<bool> _waitForBackendReady({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _pingBackend(timeout: const Duration(milliseconds: 350))) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  Future<void> stopBackend() async {
    if (isStopping) return;
    isStopping = true;
    _setStatus('Stopping...', Colors.orangeAccent);
    _addLog('Stopping backend...');
    notifyListeners();

    final process = _process;
    if (process == null) {
      _addLog('No active process found.');
      await _killBackendOnPort(3551);
      isStopping = false;
      _setStatus('Offline', Colors.redAccent);
      notifyListeners();
      return;
    }

    final pid = process.pid;
    bool exited = false;
    try {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(const Duration(seconds: 4));
      exited = true;
    } catch (_) {
      exited = false;
    }

    if (!exited) {
      await Process.run('taskkill', ['/PID', pid.toString(), '/T', '/F']);
      try {
        await process.exitCode.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }

    _process = null;
    await _killBackendOnPort(3551);
    isStopping = false;
    isRunning = false;
    _backendStartedAt = null;
    _setStatus('Offline', Colors.redAccent);
    notifyListeners();
  }

  Future<void> closeFortnite() async {
    if (!Platform.isWindows) {
      _addLog('Close Fortnite is only supported on Windows.');
      return;
    }

    _addLog('Closing Fortnite...');
    const processes = <String>[
      'FortniteClient-Win64-Shipping.exe',
      'FortniteLauncher.exe',
      'FortniteClient-Win64-Shipping_BE.exe',
      'FortniteClient-Win64-Shipping_EAC.exe',
      'EasyAntiCheat.exe',
      'BEService.exe',
      'BattlEye.exe',
      'EpicGamesLauncher.exe',
      'EpicWebHelper.exe',
      'CrashReportClient.exe',
      'UnrealCEFSubProcess.exe',
    ];

    for (final process in processes) {
      try {
        await Process.run('taskkill', ['/F', '/IM', process]);
      } catch (_) {
        // Ignore failures (process not running, permissions, etc.).
      }
    }

    _addLog('Done.');
  }

  Future<void> restartBackend() async {
    if (isRestarting || isStarting || isStopping) return;
    isRestarting = true;
    _logStore.clear();
    _setStatus('Restarting...', Colors.orangeAccent);
    _addLog('Restarting backend...');
    notifyListeners();

    await stopBackend();
    await Future.delayed(const Duration(seconds: 1));
    isRestarting = false;
    notifyListeners();
    await startBackend();

    isRestarting = false;
    notifyListeners();
  }

  Future<void> _checkBackend() async {
    final ok = await _pingBackend();
    if (ok) {
      var changed = false;
      if (!isRunning) {
        isRunning = true;
        _backendStartedAt ??= DateTime.now();
        _setStatus('Running', Colors.greenAccent);
        changed = true;
      }
      if (isStarting) {
        isStarting = false;
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
    } else if (!ok && isRunning && !isStarting) {
      isRunning = false;
      _backendStartedAt = null;
      _setStatus('Offline', Colors.redAccent);
      notifyListeners();
    }
  }

  Future<bool> _pingBackend({Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:3551/unknown'),
      );
      final response = await request.close().timeout(timeout);
      client.close();
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkBunAvailable(
    String workingDirectory,
    String? bunPath,
  ) async {
    if (bunPath != null) {
      return File(bunPath).existsSync();
    }
    try {
      final result = await Process.run('bun', [
        '--version',
      ], workingDirectory: workingDirectory);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> _killBackendOnPort(int port) async {
    if (!Platform.isWindows) return;
    try {
      final result = await Process.run('netstat', ['-ano']);
      if (result.exitCode != 0) return;
      final lines = result.stdout.toString().split('\n');
      final pids = <int>{};
      for (final raw in lines) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 5) continue;
        final localAddress = parts[1];
        if (!localAddress.endsWith(':$port')) continue;
        final pid = int.tryParse(parts.last);
        if (pid != null && pid > 0) {
          pids.add(pid);
        }
      }
      for (final pid in pids) {
        await Process.run('taskkill', ['/PID', pid.toString(), '/T', '/F']);
      }
    } catch (_) {
      // Ignore failures; status will reflect actual backend state on next poll.
    }
  }

  void _setStatus(String text, Color color) {
    _statusText = text;
    _statusColor = color;
  }

  void _addLog(String log) {
    final sanitized = log
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .trim();

    if (sanitized.isEmpty) return;

    final lines = sanitized
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return;

    final now = DateTime.now();
    final hour = now.hour;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final timezoneAbbr = now.timeZoneName.replaceAll(RegExp(r'[^A-Z]'), '');
    final timestamp =
        '[${hour12.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} $period $timezoneAbbr]';

    for (final line in lines) {
      _logStore.addLog('$timestamp $line');
    }
    _queueLogRefresh();
  }

  void _queueLogRefresh() {
    if (_logNotifyQueued) return;
    _logNotifyQueued = true;
    _logNotifyTimer = Timer(const Duration(milliseconds: 120), () {
      _logNotifyQueued = false;
      notifyListeners();
    });
  }

  Future<void> forceKillBackendPort() async {
    await _killBackendOnPort(3551);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _logNotifyTimer?.cancel();
    super.dispose();
  }
}

String getBackendRoot() {
  // Check if running from an installed location (not from source)
  // If running from Program Files or AppData Local, use separate app data directory
  final executablePath = File(Platform.resolvedExecutable).parent.path;
  if (executablePath.contains(r'Program Files') ||
      executablePath.contains(r'AppData\Local\Programs')) {
    // Running from installed MSI - use AppData for data storage
    final appDataDir = Platform.environment['APPDATA'];
    if (appDataDir != null) {
      final atlasDataDir = Directory(joinPath([appDataDir, 'ATLAS']));
      // Ensure the directory exists
      if (!atlasDataDir.existsSync()) {
        atlasDataDir.createSync(recursive: true);
      }
      return atlasDataDir.path;
    }
  }

  // Development/source mode - look for static and src directories
  final candidates = <Directory>[
    Directory.current,
    Directory.current.parent,
    Directory(File(Platform.resolvedExecutable).parent.path),
    Directory(File(Platform.resolvedExecutable).parent.parent.path),
  ];

  for (final start in candidates) {
    var current = start;
    while (true) {
      final staticDir = Directory(joinPath([current.path, 'static']));
      final srcDir = Directory(joinPath([current.path, 'src']));
      if (staticDir.existsSync() && srcDir.existsSync()) {
        return current.path;
      }
      if (current.parent.path == current.path) {
        break;
      }
      current = current.parent;
    }
  }
  return Directory.current.path;
}

String getInstallationRoot() {
  // Returns the directory where the backend code/assets are installed
  // This is different from getBackendRoot() which returns the data directory
  final candidates = <Directory>[
    Directory.current,
    Directory.current.parent,
    Directory(File(Platform.resolvedExecutable).parent.path),
    Directory(File(Platform.resolvedExecutable).parent.parent.path),
  ];

  for (final start in candidates) {
    var current = start;
    while (true) {
      final staticDir = Directory(joinPath([current.path, 'static']));
      final srcDir = Directory(joinPath([current.path, 'src']));
      if (staticDir.existsSync() && srcDir.existsSync()) {
        return current.path;
      }
      if (current.parent.path == current.path) {
        break;
      }
      current = current.parent;
    }
  }
  return Directory.current.path;
}

String joinPath(List<String> parts) {
  return parts.join(Platform.pathSeparator);
}

String? _resolveBunPath(String backendRoot) {
  // Check local bundled Bun first
  final candidates = [
    joinPath([backendRoot, 'tools', 'bun', 'bun.exe']),
    joinPath([backendRoot, 'tools', 'bun', 'bun']),
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }

  // Return null to let _checkBunAvailable try to find it in PATH
  return null;
}

String? _resolveBackgroundPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  final direct = File(trimmed);
  if (direct.existsSync()) return direct.path;
  final backendRoot = getBackendRoot();
  final relative = File(joinPath([backendRoot, trimmed]));
  if (relative.existsSync()) return relative.path;
  final publicImage = File(
    joinPath([backendRoot, 'public', 'images', trimmed]),
  );
  if (publicImage.existsSync()) return publicImage.path;
  return null;
}

class VpnService {
  static Future<String> getVpnIpAddress() async {
    try {
      // Use PowerShell to query Radmin VPN adapter IP address
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        r'Get-NetIPAddress | Where-Object {$_.InterfaceAlias -like "*Radmin*" -and $_.AddressFamily -eq "IPv4"} | Select-Object -First 1 -ExpandProperty IPAddress',
      ]);

      if (result.exitCode == 0) {
        final ip = result.stdout.toString().trim();
        if (ip.isNotEmpty && !ip.contains('Error')) {
          return ip;
        }
      }

      // Fallback: Try alternative command for older Windows versions
      final fallbackResult = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        r'Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.Description -like "*Radmin*" -and $_.IPAddress -ne $null} | Select-Object -First 1 -ExpandProperty IPAddress',
      ]);

      if (fallbackResult.exitCode == 0) {
        final ip = fallbackResult.stdout.toString().trim();
        if (ip.isNotEmpty && !ip.contains('Error')) {
          // WMI returns array format, extract first IPv4
          final match = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b').firstMatch(ip);
          if (match != null) {
            return match.group(0)!;
          }
        }
      }

      return 'Error: Radmin VPN adapter not found';
    } catch (e) {
      return 'Error: Failed to detect VPN IP - $e';
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const AvhaApp());

const gold = Color(0xFFD6AD55);
const bg = Color(0xFF101014);
const panel = Color(0xFF1B1B24);
const blue = Color(0xFF477BFF);
const purple = Color(0xFF8957E5);

const String apiBaseUrl = String.fromEnvironment(
  'KNUAF_API_URL',
  defaultValue: 'https://knuaf-ai-studio.fastapicloud.dev',
);

class AvhaApp extends StatelessWidget {
  const AvhaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AVHA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
          surface: panel,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: gold,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
      home: const AvhaHome(),
    );
  }
}

class AvhaHome extends StatefulWidget {
  const AvhaHome({super.key});

  @override
  State<AvhaHome> createState() => _AvhaHomeState();
}

class _AvhaHomeState extends State<AvhaHome> {
  int tab = 0;
  String workspace = 'شخصی';
  bool workspaceSelected = false;

  File? videoFile;
  File? activeProjectClip;
  Timer? projectAutosaveTimer;
  bool projectSaving = false;
  VideoPlayerController? videoController;
  bool busy = false;
  String status = 'برای شروع، یک ویدئو انتخاب کنید.';

  String transcript = '';
  bool transcriptApproved = false;
  double subtitleFontSize = 22;
  double subtitleVerticalPosition = 0.82;
  String subtitleColorChoice = 'سفید';
  String subtitleBackgroundChoice = 'نیمه‌شفاف';
  String subtitleAnimation = 'کلمه‌به‌کلمه';
  String subtitleFontFamily = 'پیش‌فرض';

  Color get subtitleColor {
    switch (subtitleColorChoice) {
      case 'طلایی': return gold;
      case 'زرد': return Colors.yellow;
      case 'آبی': return Colors.lightBlueAccent;
      case 'مشکی': return Colors.black;
      default: return Colors.white;
    }
  }

  String get subtitleSample {
    final clean = transcript.trim();
    if (clean.isEmpty) return 'پیش‌نمایش زیرنویس';
    final firstLine = clean.split(RegExp(r'[.!؟?\n]')).first.trim();
    return firstLine.length > 48 ? '${firstLine.substring(0, 48)}…' : firstLine;
  }
  String ideas = '';
  String caption = '';
  String topic = '';
  String hashtags = '';
  String voiceResult = '';
  String voiceFilePath = '';
  List<File> voiceLibrary = [];
  List<File> clipsLibrary = [];
  String clipsFilter = 'همه';
  String selectedVoice = 'fa-IR-FaridNeural';

  final voiceController = TextEditingController();

  // Local preferences. Login and password are intentionally not included.
  bool darkTheme = true;
  bool autoSave = true;
  bool notifications = true;
  String accentChoice = 'طلایی';
  String language = 'فارسی';
  String outputQuality = '1080p';
  String aspectRatio = '9:16';
  String aiTone = 'دوستانه';

  @override
  void initState() {
    super.initState();
    loadClipsLibrary();
  }

  @override
  void dispose() {
    projectAutosaveTimer?.cancel();
    if (activeProjectClip != null) {
      _writeProjectData();
    }
    videoController?.dispose();
    voiceController.dispose();
    super.dispose();
  }

  String responseText(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  Map<String, dynamic> decodeJson(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw Exception('پاسخ سرور معتبر نیست.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> runTask(Future<void> Function() task, String label) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = label;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => status = 'خطا: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickVideo() async {
    try {
      await _flushProjectAutosave();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: false,
      );
      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      await videoController?.dispose();
      final controller = VideoPlayerController.file(file);
      setState(() {
        videoFile = file;
        activeProjectClip = null;
        videoController = controller;
        transcript = '';
        transcriptApproved = false;
        ideas = '';
        caption = '';
        topic = '';
        hashtags = '';
        voiceResult = '';
        voiceFilePath = '';
        status = 'ویدئو انتخاب شد.';
        tab = 0;
      });
      await controller.initialize();
      await controller.setLooping(true);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => status = 'خطا در انتخاب ویدئو: $e');
    }
  }

  Future<Map<String, dynamic>> uploadVideoForTranscription() async {
    if (videoFile == null) throw Exception('ابتدا یک ویدئو انتخاب کنید.');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBaseUrl/transcribe'),
    );
    request.headers['Accept'] = 'application/json';
    request.files.add(await http.MultipartFile.fromPath('video', videoFile!.path));
    final streamed = await request.send().timeout(const Duration(minutes: 10));
    final body = utf8.decode(await streamed.stream.toBytes(), allowMalformed: true);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('خطای سرور (${streamed.statusCode}): $body');
    }
    return decodeJson(body);
  }

  Future<void> transcribe() => runTask(() async {
        final data = await uploadVideoForTranscription();
        final text = (data['text'] ?? '').toString();
        if (text.trim().isEmpty) throw Exception('متنی از ویدئو استخراج نشد.');
        setState(() {
          transcript = text;
          transcriptApproved = false;
          status = 'متن ویدئو با موفقیت استخراج شد.';
          scheduleProjectAutosave();
        });
      }, 'در حال استخراج گفتار ویدئو...');

  Future<void> createIdeas() => runTask(() async {
        if (transcript.trim().isEmpty) {
          throw Exception('ابتدا متن ویدئو را استخراج یا وارد کنید.');
        }
        if (!transcriptApproved) {
          throw Exception('ابتدا زیرنویس را بررسی و تأیید کنید.');
        }
        final response = await http
            .post(
              Uri.parse('$apiBaseUrl/content'),
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
              },
              body: utf8.encode(jsonEncode({
                'transcript': transcript.trim(),
                'business': workspace == 'کاری' ? 'AVHA Business' : 'AVHA Personal',
              })),
            )
            .timeout(const Duration(minutes: 3));
        final body = responseText(response);
        if (response.statusCode != 200) {
          throw Exception('خطای تولید محتوا (${response.statusCode}): $body');
        }
        final data = decodeJson(body);
        if (data['ok'] != true || data['content'] is! Map) {
          throw Exception('ساختار پاسخ سرور معتبر نیست.');
        }
        final content = Map<String, dynamic>.from(data['content']);
        final tags = content['hashtags'];
        setState(() {
          topic = (content['topic'] ?? '').toString();
          ideas = (content['idea'] ?? '').toString();
          caption = (content['caption'] ?? '').toString();
          hashtags = tags is List ? tags.join('  ') : '';
          status = 'ایده و کپشن آماده شد.';
          scheduleProjectAutosave();
        });
      }, 'در حال ساخت ایده و کپشن با هوش مصنوعی...');

  Future<void> createVoice() => runTask(() async {
        final text = voiceController.text.trim();
        if (text.isEmpty) throw Exception('متن موردنظر را وارد کنید.');
        final response = await http
            .post(
              Uri.parse('$apiBaseUrl/tts'),
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'audio/mpeg',
              },
              body: utf8.encode(jsonEncode({
                'text': text,
                'voice': selectedVoice,
              })),
            )
            .timeout(const Duration(minutes: 3));
        if (response.statusCode != 200) {
          throw Exception('تولید صدا ناموفق بود: ${responseText(response)}');
        }
        if (response.bodyBytes.isEmpty) throw Exception('فایل صوتی خالی است.');
        final audioDir = await voiceDirectory();
        await audioDir.create(recursive: true);
        final file = File(
          '${audioDir.path}${Platform.pathSeparator}AVHA_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await loadVoiceLibrary();
        setState(() {
          voiceFilePath = file.path;
          voiceResult = 'فایل صوتی در پوشه فضای ${workspace == 'کاری' ? 'کاری' : 'شخصی'} ذخیره شد.';
          status = 'تولید صدا با موفقیت انجام شد.';
        });
      }, 'در حال تولید فایل صوتی...');

  Future<Directory> voiceDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(
      '${appDir.path}${Platform.pathSeparator}AVHA'
      '${Platform.pathSeparator}Audio${Platform.pathSeparator}$workspace',
    );
  }

  Future<void> loadVoiceLibrary() async {
    try {
      final dir = await voiceDirectory();
      if (!await dir.exists()) await dir.create(recursive: true);
      final files = dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.mp3'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (mounted) setState(() => voiceLibrary = files);
    } catch (e) {
      if (mounted) setState(() => status = 'خطا در بارگذاری فایل‌های صوتی: $e');
    }
  }

  Future<void> saveVoiceFile(File file) async {
    try {
      final name = file.path.split(Platform.pathSeparator).last;
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره فایل صوتی',
        fileName: name,
        bytes: await file.readAsBytes(),
      );
      if (destination != null && mounted) {
        setState(() => status = 'فایل صوتی ذخیره شد.');
      }
    } catch (e) {
      if (mounted) setState(() => status = 'ذخیره فایل ناموفق بود: $e');
    }
  }

  Future<void> deleteVoiceFile(File file) async {
    final name = file.path.split(Platform.pathSeparator).last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('حذف فایل صوتی'),
        content: Text('فایل «$name» حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await file.delete();
      await loadVoiceLibrary();
      if (mounted) {
        setState(() {
          if (voiceFilePath == file.path) {
            voiceFilePath = '';
            voiceResult = '';
          }
          status = 'فایل صوتی حذف شد.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'حذف فایل ناموفق بود: $e');
    }
  }

  Future<Directory> clipsRootDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}${Platform.pathSeparator}AVHA${Platform.pathSeparator}Clips');
  }

  Future<void> loadClipsLibrary() async {
    try {
      final root = await clipsRootDirectory();
      for (final name in ['شخصی', 'کاری']) {
        await Directory('${root.path}${Platform.pathSeparator}$name').create(recursive: true);
      }
      final files = root.listSync(recursive: true).whereType<File>().where((f) {
        final ext = f.path.toLowerCase();
        return ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.m4v') || ext.endsWith('.mkv');
      }).toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (mounted) setState(() => clipsLibrary = files);
    } catch (e) {
      if (mounted) setState(() => status = 'خطا در بارگذاری کلیپ‌ها: $e');
    }
  }

  String clipWorkspace(File file) => file.parent.path.split(Platform.pathSeparator).last;

  Future<File> _projectSidecar(File clip) async =>
      File('${clip.path}.avha.json');

  Map<String, dynamic> _projectData() => {
        'version': 1,
        'workspace': workspace,
        'transcript': transcript,
        'transcriptApproved': transcriptApproved,
        'subtitleFontSize': subtitleFontSize,
        'subtitleVerticalPosition': subtitleVerticalPosition,
        'subtitleColorChoice': subtitleColorChoice,
        'subtitleBackgroundChoice': subtitleBackgroundChoice,
        'subtitleAnimation': subtitleAnimation,
        'subtitleFontFamily': subtitleFontFamily,
        'ideas': ideas,
        'caption': caption,
        'topic': topic,
        'hashtags': hashtags,
        'videoPositionMs': videoController?.value.position.inMilliseconds ?? 0,
        'savedAt': DateTime.now().toIso8601String(),
      };

  Future<void> _writeProjectData({bool showMessage = false}) async {
    final clip = activeProjectClip;
    if (clip == null) return;
    // A concurrent write is allowed to finish; _flushProjectAutosave will
    // perform one final write afterwards so the newest state is not lost.
    if (projectSaving) return;
    projectSaving = true;
    try {
      if (!await clip.exists()) return;
      final sidecar = await _projectSidecar(clip);
      final snapshot = _projectData();
      await sidecar.writeAsString(
        const JsonEncoder.withIndent('  ').convert(snapshot),
        flush: true,
      );
      if (showMessage && mounted) {
        setState(() => status = 'پروژه و تنظیمات تدوین ذخیره شد.');
        showInfo('پروژه ذخیره شد', 'ویدئو و تنظیمات آن در فضای $workspace ذخیره شدند. هر تغییری که از این به بعد انجام بدهی، به‌صورت خودکار ذخیره می‌شود.');
      }
    } catch (e) {
      if (mounted) setState(() => status = 'ذخیره تغییرات پروژه ناموفق بود: $e');
    } finally {
      projectSaving = false;
    }
  }

  Future<void> _flushProjectAutosave() async {
    projectAutosaveTimer?.cancel();
    projectAutosaveTimer = null;
    // Wait for an already-running write, then persist the latest state.
    while (projectSaving) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (activeProjectClip != null) await _writeProjectData();
  }

  void scheduleProjectAutosave() {
    if (activeProjectClip == null) return;
    projectAutosaveTimer?.cancel();
    projectAutosaveTimer = Timer(const Duration(milliseconds: 800), () async {
      await _writeProjectData();
    });
  }

  Future<void> _restoreProjectData(File clip) async {
    try {
      final sidecar = await _projectSidecar(clip);
      if (!await sidecar.exists()) {
        if (mounted) setState(() {
          transcript = '';
          transcriptApproved = false;
          ideas = caption = topic = hashtags = '';
          subtitleFontSize = 22;
          subtitleVerticalPosition = 0.82;
          subtitleColorChoice = 'سفید';
          subtitleBackgroundChoice = 'نیمه‌شفاف';
          subtitleAnimation = 'کلمه‌به‌کلمه';
          subtitleFontFamily = 'پیش‌فرض';
        });
        return;
      }
      final raw = jsonDecode(await sidecar.readAsString());
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      if (!mounted) return;
      setState(() {
        transcript = (data['transcript'] ?? '').toString();
        transcriptApproved = data['transcriptApproved'] == true;
        subtitleFontSize = (data['subtitleFontSize'] as num?)?.toDouble() ?? 22;
        subtitleVerticalPosition = (data['subtitleVerticalPosition'] as num?)?.toDouble() ?? 0.82;
        subtitleColorChoice = (data['subtitleColorChoice'] ?? 'سفید').toString();
        subtitleBackgroundChoice = (data['subtitleBackgroundChoice'] ?? 'نیمه‌شفاف').toString();
        subtitleAnimation = (data['subtitleAnimation'] ?? 'کلمه‌به‌کلمه').toString();
        subtitleFontFamily = (data['subtitleFontFamily'] ?? 'پیش‌فرض').toString();
        ideas = (data['ideas'] ?? '').toString();
        caption = (data['caption'] ?? '').toString();
        topic = (data['topic'] ?? '').toString();
        hashtags = (data['hashtags'] ?? '').toString();
        status = 'پروژه قبلی همراه با تنظیماتش بازیابی شد؛ می‌توانی تدوین را ادامه بدهی.';
      });
      final savedPosition = (data['videoPositionMs'] as num?)?.toInt() ?? 0;
      final duration = videoController?.value.duration.inMilliseconds ?? 0;
      if (savedPosition > 0 && duration > 0) {
        await videoController?.seekTo(Duration(milliseconds: savedPosition.clamp(0, duration).toInt()));
      }
    } catch (e) {
      if (mounted) setState(() => status = 'فایل ویدئو باز شد، اما بازیابی تنظیمات پروژه انجام نشد: $e');
    }
  }

  Future<void> saveCurrentClipToLibrary() async {
    if (videoFile == null) {
      showInfo('ذخیره پروژه', 'ابتدا یک ویدئو انتخاب کن.');
      return;
    }
    try {
      await _flushProjectAutosave();
      final root = await clipsRootDirectory();
      final dir = Directory('${root.path}${Platform.pathSeparator}$workspace');
      await dir.create(recursive: true);
      File projectClip;
      final currentPath = videoFile!.absolute.path;
      final expectedPrefix = '${dir.absolute.path}${Platform.pathSeparator}';
      if (currentPath.startsWith(expectedPrefix) && await videoFile!.exists()) {
        projectClip = videoFile!;
      } else {
        final original = videoFile!.path.split(Platform.pathSeparator).last;
        final dot = original.lastIndexOf('.');
        final base = dot > 0 ? original.substring(0, dot) : original;
        final ext = dot > 0 ? original.substring(dot) : '.mp4';
        final target = File('${dir.path}${Platform.pathSeparator}${base}_${DateTime.now().millisecondsSinceEpoch}$ext');
        projectClip = await videoFile!.copy(target.path);
        await videoController?.pause();
        await videoController?.dispose();
        final controller = VideoPlayerController.file(projectClip);
        await controller.initialize();
        await controller.setLooping(true);
        if (!mounted) { await controller.dispose(); return; }
        setState(() {
          videoFile = projectClip;
          videoController = controller;
        });
      }
      activeProjectClip = projectClip;
      await _writeProjectData(showMessage: true);
      await loadClipsLibrary();
    } catch (e) {
      if (mounted) setState(() => status = 'ذخیره پروژه ناموفق بود: $e');
    }
  }

  Future<void> renameClip(File file) async {
    final controller = TextEditingController(text: file.uri.pathSegments.last);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: panel,
      title: const Text('تغییر نام کلیپ'),
      content: TextField(controller: controller, textDirection: TextDirection.rtl, decoration: const InputDecoration(hintText: 'نام فایل')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')), TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ذخیره'))],
    ));
    controller.dispose();
    if (value == null || value.isEmpty) return;
    try {
      final safe = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final oldPath = file.path;
      final dot = file.path.lastIndexOf('.');
      final requested = safe.contains('.') || dot < 0 ? safe : '$safe${file.path.substring(dot)}';
      final target = File('${file.parent.path}${Platform.pathSeparator}$requested');
      final isActive = activeProjectClip?.path == oldPath || videoFile?.path == oldPath;
      if (isActive) await _flushProjectAutosave();
      if (isActive) {
        await videoController?.pause();
        await videoController?.dispose();
        videoController = null;
      }
      final renamed = await file.rename(target.path);
      final oldSidecar = await _projectSidecar(file);
      if (await oldSidecar.exists()) {
        final newSidecar = await _projectSidecar(renamed);
        await oldSidecar.rename(newSidecar.path);
      }
      if (isActive) {
        final nextController = VideoPlayerController.file(renamed);
        await nextController.initialize();
        await nextController.setLooping(true);
        if (!mounted) { await nextController.dispose(); return; }
        setState(() {
          videoFile = renamed;
          activeProjectClip = renamed;
          videoController = nextController;
        });
      }
      await loadClipsLibrary();
    } catch (e) {
      if (mounted) showInfo('خطا', 'تغییر نام انجام نشد: $e');
    }
  }

  Future<void> deleteClip(File file) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: panel, title: const Text('حذف کلیپ'), content: const Text('این فایل از کتابخانه AVHA حذف شود؟'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.redAccent)))],
    ));
    if (ok != true) return;
    try {
      final isActive = activeProjectClip?.path == file.path || videoFile?.path == file.path;
      if (isActive) {
        await _flushProjectAutosave();
        await videoController?.pause();
        await videoController?.dispose();
        videoController = null;
      }
      final sidecar = await _projectSidecar(file);
      if (await file.exists()) await file.delete();
      if (await sidecar.exists()) await sidecar.delete();
      if (isActive && mounted) {
        setState(() {
          videoFile = null;
          activeProjectClip = null;
          transcript = '';
          transcriptApproved = false;
          ideas = caption = topic = hashtags = '';
          subtitleFontSize = 22;
          subtitleVerticalPosition = 0.82;
          subtitleColorChoice = 'سفید';
          subtitleBackgroundChoice = 'نیمه‌شفاف';
          subtitleAnimation = 'کلمه‌به‌کلمه';
          subtitleFontFamily = 'پیش‌فرض';
          status = 'پروژه حذف شد.';
        });
      }
      await loadClipsLibrary();
    } catch (e) {
      if (mounted) showInfo('خطا', 'حذف کلیپ انجام نشد: $e');
    }
  }

  Future<void> openClip(File file) async {
    try {
      // Save the currently open project before switching to another one.
      await _flushProjectAutosave();
      await videoController?.pause();
      await videoController?.dispose();
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) { await controller.dispose(); return; }
      setState(() {
        videoFile = file;
        activeProjectClip = file;
        videoController = controller;
        workspace = clipWorkspace(file);
        workspaceSelected = true;
        clipsFilter = workspace;
        tab = 5;
      });
      await _restoreProjectData(file);
      await loadVoiceLibrary();
    } catch (e) {
      if (mounted) showInfo('خطا در پخش', '$e');
    }
  }

  void go(int index) => setState(() => tab = index);

  Widget sectionTitle(String title, {String? subtitle}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(color: Colors.white60)),
            ],
          ],
        ),
      );

  Widget goldButton(String text, VoidCallback? action, {IconData icon = Icons.auto_awesome}) =>
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: busy ? null : action,
          icon: Icon(icon),
          label: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );

  Widget card({required Widget child, EdgeInsets padding = const EdgeInsets.all(15)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(.06)),
        ),
        child: child,
      );

  Widget videoPreview({double height = 205}) {
    final c = videoController;
    if (c == null || !c.value.isInitialized) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18)),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: 48, color: gold),
            SizedBox(height: 9),
            Text('پیش‌نمایش ویدئو', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(c),
            if (transcript.trim().isNotEmpty)
              Align(
                alignment: Alignment(0, subtitleVerticalPosition),
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      subtitleVerticalPosition = (subtitleVerticalPosition +
                          details.delta.dy / 180).clamp(-0.9, 0.9);
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: subtitleBackgroundChoice == 'بدون پس‌زمینه'
                          ? Colors.transparent
                          : Colors.black.withOpacity(
                              subtitleBackgroundChoice == 'پررنگ' ? .85 : .55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      subtitleSample,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: subtitleFontSize,
                        fontFamily: subtitleFontFamily == 'پیش‌فرض' ? null : subtitleFontFamily,
                        fontWeight: FontWeight.bold,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ),
            VideoProgressIndicator(c, allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: gold)),
            Center(
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                iconSize: 38,
                onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
                icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget modeCard(String title, String subtitle, IconData icon, Color color) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          if (busy) return;
          setState(() {
            workspace = title == 'فضای کاری' ? 'کاری' : 'شخصی';
            workspaceSelected = true;
            tab = 0;
            clipsFilter = workspace;
          });
          await loadVoiceLibrary();
          await loadClipsLibrary();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [color.withOpacity(.30), panel, panel],
            ),
            border: Border.all(color: color.withOpacity(.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 31),
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white60)),
              const SizedBox(height: 12),
              Row(children: [
                Text('ورود به فضا', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                const Icon(Icons.chevron_left, size: 18),
              ]),
            ],
          ),
        ),
      );

  Future<void> changeWorkspace() async {
    if (busy) return;
    await _flushProjectAutosave();
    await videoController?.pause();
    await videoController?.dispose();
    voiceController.clear();
    if (!mounted) return;
    setState(() {
      workspaceSelected = false;
      tab = 0;
      videoController = null;
      videoFile = null;
      activeProjectClip = null;
      transcript = '';
      transcriptApproved = false;
      ideas = '';
      caption = '';
      topic = '';
      hashtags = '';
      voiceResult = '';
      voiceFilePath = '';
      voiceLibrary = [];
      clipsFilter = workspace;
      status = 'فضای جدید را انتخاب کنید.';
    });
  }

  Widget workspaceSelectionPage() => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 56),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.auto_awesome, color: gold, size: 54),
                const SizedBox(height: 12),
                const Center(child: Text('AVHA', style: TextStyle(
                  color: gold, fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 4,
                ))),
                const SizedBox(height: 5),
                const Center(child: Text('AI CONTENT STUDIO', style: TextStyle(
                  color: Colors.white54, fontSize: 11, letterSpacing: 3,
                ))),
                const SizedBox(height: 14),
                const Center(child: Text('خلق کن، متفاوت باش.', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600,
                ))),
                const SizedBox(height: 10),
                const Center(child: Text('برای شروع، نوع پروژه خود را انتخاب کنید.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))),
                const SizedBox(height: 30),
                modeCard('فضای شخصی', 'برای ولاگ، سفر و محتوای شبکه‌های اجتماعی',
                    Icons.person_outline, blue),
                const SizedBox(height: 14),
                modeCard('فضای کاری', 'برای پروژه‌ها، برند و محتوای کسب‌وکار',
                    Icons.business_center_outlined, gold),
                const SizedBox(height: 22),
                const Center(child: Text('فضاها و فایل‌های ذخیره‌شده از یکدیگر جدا هستند.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11))),
              ],
            ),
          ),
        ),
      );

  Widget homePage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('AVHA', style: TextStyle(color: gold, fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  Text('AI CONTENT STUDIO', style: TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 2)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: workspace == 'کاری' ? gold.withOpacity(.14) : blue.withOpacity(.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: workspace == 'کاری' ? gold : blue)),
                child: Text(workspace == 'کاری' ? 'فضای کاری' : 'فضای شخصی',
                  style: TextStyle(color: workspace == 'کاری' ? gold : blue, fontSize: 11)),
              ),
              IconButton(
                tooltip: 'تغییر فضا',
                onPressed: changeWorkspace,
                icon: const Icon(Icons.swap_horiz, color: gold, size: 27),
              ),
              IconButton(
                tooltip: 'تنظیمات',
                onPressed: () => go(4),
                icon: const Icon(Icons.settings_outlined, color: gold, size: 27),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('سلام، کاربر عزیز 👋', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          const Text('به AVHA خوش آمدی؛ آماده‌ای چیزی متفاوت خلق کنی؟',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => go(6),
            icon: const Icon(Icons.folder_open, color: gold),
            label: const Text('کلیپ‌های من'),
          ),
          const SizedBox(height: 22),
          const Text('شروع سریع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          card(child: Column(children: [
            Row(children: [
              const Icon(Icons.video_library_outlined, color: gold, size: 30),
              const SizedBox(width: 10),
              const Expanded(child: Text('ویدئوی خود را انتخاب کن')),
              TextButton(onPressed: busy ? null : pickVideo, child: const Text('انتخاب ویدئو')),
            ]),
            if (videoFile != null) ...[
              const SizedBox(height: 10),
              videoPreview(),
              const SizedBox(height: 7),
              Text(videoFile!.path.split(Platform.pathSeparator).last,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 10),
              goldButton('رفتن به محیط تدوین', () => go(5), icon: Icons.movie_edit),
            ],
          ])),
          const SizedBox(height: 18),
          const Text('ابزارهای هوشمند', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          featureRow(Icons.subtitles, 'زیرنویس هوشمند', 'تبدیل گفتار ویدئو به متن', () => go(1), blue),
          featureRow(Icons.graphic_eq, 'متن به گفتار', 'تولید صدای فارسی', () => go(2), purple),
          featureRow(Icons.lightbulb_outline, 'ایده و کپشن', 'عنوان، سناریو، کپشن و هشتگ', () => go(3), gold),
          const SizedBox(height: 14),
          card(child: Row(children: [
            const Icon(Icons.info_outline, color: gold),
            const SizedBox(width: 10),
            Expanded(child: Text(status, style: const TextStyle(color: Colors.white70))),
          ])),
        ],
      );

  Widget featureRow(IconData icon, String title, String subtitle, VoidCallback onTap, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: card(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: color, size: 29),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            trailing: const Icon(Icons.chevron_left),
            onTap: onTap,
          ),
        ),
      );

  Widget captionsPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('استودیوی زیرنویس', subtitle: 'اول متن را اصلاح و تأیید کن؛ سپس ظاهر زیرنویس را تنظیم کن.'),
          card(child: Column(children: [
            goldButton('استخراج متن از ویدئو', videoFile == null ? null : transcribe, icon: Icons.subtitles),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transcriptEditor'),
              initialValue: transcript,
              maxLines: 8,
              onChanged: (v) => setState(() {
                transcript = v;
                transcriptApproved = false;
                scheduleProjectAutosave();
              }),
              decoration: const InputDecoration(
                hintText: 'متن تشخیص‌داده‌شده را اینجا اصلاح کن؛ مثلاً کناف، تراز سانت و ام‌دی‌اف...',
                labelText: 'متن قابل ویرایش زیرنویس',
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(transcriptApproved ? Icons.verified : Icons.edit_note,
                  color: transcriptApproved ? Colors.greenAccent : gold),
              const SizedBox(width: 8),
              Expanded(child: Text(
                transcriptApproved ? 'متن تأیید شده؛ هوش مصنوعی از همین متن استفاده می‌کند.'
                    : 'قبل از ساخت کپشن و ایده، متن را بررسی و تأیید کن.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              )),
            ]),
            const SizedBox(height: 10),
            goldButton(
              transcriptApproved ? 'متن تأیید شد' : 'تأیید متن اصلاح‌شده',
              transcript.trim().isEmpty ? null : () => setState(() {
                transcriptApproved = true;
                status = 'متن زیرنویس تأیید شد؛ حالا می‌توانی محتوای هوشمند بسازی.';
                scheduleProjectAutosave();
              }),
              icon: Icons.check_circle_outline,
            ),
          ])),
          const SizedBox(height: 16),
          sectionTitle('طراحی و جایگاه زیرنویس'),
          if (videoFile != null) ...[
            videoPreview(height: 230),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('برای جابه‌جایی، متن روی تصویر را با انگشت یا ماوس بکش.',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          ] else
            card(child: const Text('برای دیدن پیش‌نمایش، ابتدا یک ویدئو انتخاب کن.')),
          const SizedBox(height: 12),
          card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('اندازه فونت: ${subtitleFontSize.round()}',
                style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
            Slider(
              value: subtitleFontSize,
              min: 12,
              max: 42,
              divisions: 15,
              activeColor: gold,
              onChanged: (v) => setState(() { subtitleFontSize = v; scheduleProjectAutosave(); }),
            ),
            DropdownButtonFormField<String>(
              value: subtitleFontFamily,
              decoration: const InputDecoration(labelText: 'نوع فونت'),
              items: const [
                DropdownMenuItem(value: 'پیش‌فرض', child: Text('پیش‌فرض')),
                DropdownMenuItem(value: 'serif', child: Text('سریف')),
                DropdownMenuItem(value: 'monospace', child: Text('تک‌فاصله')),
              ],
              onChanged: (v) { if (v != null) setState(() { subtitleFontFamily = v; scheduleProjectAutosave(); }); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleColorChoice,
              decoration: const InputDecoration(labelText: 'رنگ نوشته'),
              items: ['سفید', 'طلایی', 'زرد', 'آبی', 'مشکی']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() { subtitleColorChoice = v; scheduleProjectAutosave(); }); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleBackgroundChoice,
              decoration: const InputDecoration(labelText: 'پس‌زمینه زیرنویس'),
              items: ['نیمه‌شفاف', 'پررنگ', 'بدون پس‌زمینه']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() { subtitleBackgroundChoice = v; scheduleProjectAutosave(); }); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleAnimation,
              decoration: const InputDecoration(labelText: 'نحوه نمایش متن'),
              items: ['یک‌جا', 'حرف‌به‌حرف', 'کلمه‌به‌کلمه', 'برجسته‌سازی کلمه فعال']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() { subtitleAnimation = v; scheduleProjectAutosave(); }); },
            ),
            const SizedBox(height: 10),
            Text('موقعیت عمودی: ${(subtitleVerticalPosition * 100).round()}%',
                style: const TextStyle(color: Colors.white70)),
            Slider(
              value: subtitleVerticalPosition,
              min: -0.9,
              max: 0.9,
              activeColor: gold,
              onChanged: (v) => setState(() { subtitleVerticalPosition = v; scheduleProjectAutosave(); }),
            ),
          ])),
          const SizedBox(height: 12),
          card(child: const Text(
            'نکته: در این مرحله ویرایش متن و پیش‌نمایش طراحی فعال است. زمان‌بندی دقیق کلمه‌ها و چسباندن دائمی زیرنویس به فایل خروجی، به دریافت زمان‌بندی کلمه‌ای از سرور و موتور رندر ویدئو نیاز دارد و در مرحله فنی بعدی وصل می‌شود.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          )),
        ],
      );

  Widget voicePage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('تبدیل متن به صدا', subtitle: 'متن خود را با صدای فارسی به فایل صوتی تبدیل کن.'),
          TextField(
            controller: voiceController,
            maxLines: 7,
            decoration: const InputDecoration(hintText: 'متن موردنظر برای تبدیل به صدا...'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: selectedVoice,
            decoration: const InputDecoration(labelText: 'صدای گوینده'),
            items: const [
              DropdownMenuItem(value: 'fa-IR-FaridNeural', child: Text('صدای مرد')),
              DropdownMenuItem(value: 'fa-IR-DilaraNeural', child: Text('صدای زن')),
            ],
            onChanged: (v) { if (v != null) setState(() => selectedVoice = v); },
          ),
          const SizedBox(height: 14),
          goldButton('تولید فایل صوتی', createVoice, icon: Icons.graphic_eq),
          if (voiceResult.isNotEmpty) ...[
            const SizedBox(height: 14),
            card(child: SelectableText(voiceResult, style: const TextStyle(color: gold))),
          ],
          const SizedBox(height: 22),
          Row(children: [
            const Expanded(child: Text('فایل‌های صوتی من', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(onPressed: loadVoiceLibrary, tooltip: 'به‌روزرسانی', icon: const Icon(Icons.refresh, color: gold)),
          ]),
          Text('فایل‌های ساخته‌شده در پوشه اختصاصی AVHA نگهداری می‌شوند.', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 10),
          if (voiceLibrary.isEmpty)
            card(child: const Row(children: [
              Icon(Icons.audio_file_outlined, color: gold, size: 30),
              SizedBox(width: 10),
              Expanded(child: Text('هنوز فایل صوتی ذخیره‌شده‌ای نداری.')),
            ]))
          else
            ...voiceLibrary.map((file) {
              final name = file.path.split(Platform.pathSeparator).last;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: card(child: Row(children: [
                  const Icon(Icons.audio_file, color: gold, size: 30),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${(file.lengthSync() / 1024).toStringAsFixed(0)} KB', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ])),
                  IconButton(tooltip: 'ذخیره در دستگاه', onPressed: () => saveVoiceFile(file), icon: const Icon(Icons.save_alt, color: blue)),
                  IconButton(tooltip: 'حذف فایل', onPressed: () => deleteVoiceFile(file), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                ])),
              );
            }),
        ],
      );

  Widget aiPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('استودیوی هوشمند AI', subtitle: 'برای فضای ${workspace == 'کاری' ? 'کاری' : 'شخصی'} محتوای مناسب بساز.'),
          card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.psychology_alt, color: purple, size: 48),
            const SizedBox(height: 8),
            const Text('تولید ایده، سناریو، کپشن و هشتگ', textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            goldButton('ساخت محتوای پیشنهادی', (transcript.trim().isEmpty || !transcriptApproved) ? null : createIdeas),
          ])),
          const SizedBox(height: 14),
          if (topic.isNotEmpty) resultCard('عنوان پیشنهادی', topic),
          if (ideas.isNotEmpty) resultCard('ایده و سناریو', ideas),
          if (caption.isNotEmpty) resultCard('کپشن', caption),
          if (hashtags.isNotEmpty) resultCard('هشتگ‌ها', hashtags),
          if (transcript.trim().isEmpty || !transcriptApproved)
            const Padding(
              padding: EdgeInsets.only(top: 15),
              child: Text('ابتدا در بخش زیرنویس، متن را اصلاح و تأیید کن.',
                  style: TextStyle(color: Colors.white54)),
            ),
        ],
      );

  Widget resultCard(String title, String value) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText(value),
        ])),
      );

  Widget projectsPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('کلیپ‌های من', subtitle: 'فایل‌های ذخیره‌شده در فضای ${workspace == 'کاری' ? 'کاری' : 'شخصی'}.'),
          if (clipsLibrary.where((f) => clipWorkspace(f) == workspace).isEmpty)
            card(child: const Column(children: [
              Icon(Icons.video_library_outlined, color: gold, size: 42),
              SizedBox(height: 8),
              Text('هنوز کلیپی در این فضا ذخیره نشده است.'),
              SizedBox(height: 6),
              Text('از محیط تدوین، گزینه «ذخیره در کلیپ‌های من» را بزن.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            ]))
          else
            ...clipsLibrary.where((f) => clipWorkspace(f) == workspace).map((file) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: card(child: Row(children: [
                const Icon(Icons.video_file_outlined, color: gold, size: 34),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(file.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} مگابایت',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ])),
                IconButton(tooltip: 'پخش و تدوین', onPressed: () => openClip(file),
                  icon: const Icon(Icons.play_circle_outline, color: gold)),
                PopupMenuButton<String>(
                  onSelected: (v) { if (v == 'rename') renameClip(file); if (v == 'delete') deleteClip(file); },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('تغییر نام')),
                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ])),
            )),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: loadClipsLibrary,
            icon: const Icon(Icons.refresh), label: const Text('به‌روزرسانی کتابخانه')),
        ],
      );

  Widget editorPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(children: [
            IconButton(onPressed: () => go(0), icon: const Icon(Icons.arrow_forward, color: gold)),
            const Expanded(child: Text('محیط تدوین', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
            TextButton(onPressed: saveCurrentClipToLibrary, child: const Text('ذخیره پروژه')),
          ]),
          if (videoFile == null) ...[
            card(child: const Text('برای شروع تدوین، ابتدا از صفحه خانه یک ویدئو انتخاب کن.')),
            const SizedBox(height: 10),
            goldButton('انتخاب ویدئو', pickVideo, icon: Icons.video_library),
          ] else ...[
            videoPreview(height: 230),
            const SizedBox(height: 12),
            card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('نوار زمان ویدئو', style: TextStyle(fontWeight: FontWeight.bold, color: gold)),
              const SizedBox(height: 10),
              VideoProgressIndicator(videoController!, allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: gold, bufferedColor: Colors.white24)),
              const SizedBox(height: 8),
              const Text('پیش‌نمایش و جابه‌جایی روی ویدئو فعال است؛ ابزارهای برش و لایه‌ها در فاز تدوین اضافه می‌شوند.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            const SizedBox(height: 12),
            goldButton('ذخیره پروژه و ادامه بعداً', saveCurrentClipToLibrary, icon: Icons.save_alt),
            const SizedBox(height: 6),
            const Text('پس از اولین ذخیره، تنظیمات و متن زیرنویس این پروژه خودکار ذخیره می‌شوند. از بخش «کلیپ‌های من» هر زمان خواستی دوباره بازش کن و ادامه بده.', style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 12),
            const Text('ابزارهای تدوین', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              'برش', 'تقسیم', 'موسیقی', 'متن', 'فیلتر', 'افکت',
              'تنظیم رنگ', 'ترنزیشن', 'زیرنویس', 'استیکر',
            ].map((name) => ActionChip(
              avatar: const Icon(Icons.construction, size: 17, color: gold),
              label: Text(name),
              onPressed: () => showInfo(name, 'ابزار $name در طراحی مشخص شده و اتصال عملکرد واقعی آن در مرحله تدوین انجام می‌شود.'),
              backgroundColor: panel,
            )).toList()),
          ],
        ],
      );

  void showInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: panel,
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('متوجه شدم'))],
      ),
    );
  }

  Widget settingsPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('تنظیمات', subtitle: 'شخصی‌سازی تجربه استفاده از AVHA'),
          card(child: Row(children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(color: gold.withOpacity(.15), shape: BoxShape.circle),
              child: const Icon(Icons.person_outline, color: gold, size: 30),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('کاربر AVHA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              Text('بدون نیاز به حساب کاربری', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            const Icon(Icons.check_circle, color: Colors.green),
          ])),
          const SizedBox(height: 12),
          settingsGroup('ظاهر برنامه', Icons.palette_outlined, [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('حالت تاریک'),
              value: darkTheme,
              activeColor: gold,
              onChanged: (v) => setState(() => darkTheme = v),
            ),
            dropdownSetting('رنگ رابط کاربری', accentChoice, ['طلایی', 'آبی', 'بنفش'],
                (v) => setState(() => accentChoice = v)),
            dropdownSetting('زبان برنامه', language, ['فارسی', 'English'],
                (v) => setState(() => language = v)),
          ]),
          settingsGroup('تنظیمات تدوین', Icons.movie_outlined, [
            dropdownSetting('کیفیت پیش‌فرض خروجی', outputQuality, ['720p', '1080p', '2K', '4K'],
                (v) => setState(() => outputQuality = v)),
            dropdownSetting('نسبت تصویر پیش‌فرض', aspectRatio, ['9:16', '16:9', '1:1', '4:5'],
                (v) => setState(() => aspectRatio = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ذخیره خودکار پروژه‌ها'),
              subtitle: const Text('فعال‌سازی ذخیره خودکار در نسخه آینده'),
              value: autoSave,
              activeColor: gold,
              onChanged: (v) => setState(() => autoSave = v),
            ),
          ]),
          settingsGroup('هوش مصنوعی', Icons.psychology_outlined, [
            dropdownSetting('زبان تولید محتوا', language, ['فارسی', 'English'],
                (v) => setState(() => language = v)),
            dropdownSetting('لحن متن', aiTone, ['دوستانه', 'رسمی', 'تبلیغاتی', 'صمیمی'],
                (v) => setState(() => aiTone = v)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('صدای گوینده'),
              subtitle: Text(selectedVoice == 'fa-IR-FaridNeural' ? 'صدای مرد' : 'صدای زن'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => setState(() => selectedVoice = selectedVoice == 'fa-IR-FaridNeural'
                  ? 'fa-IR-DilaraNeural' : 'fa-IR-FaridNeural'),
            ),
          ]),
          settingsGroup('اعلان‌ها', Icons.notifications_none, [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('دریافت اعلان‌ها'),
              value: notifications,
              activeColor: gold,
              onChanged: (v) => setState(() => notifications = v),
            ),
          ]),
          settingsGroup('فضای ذخیره‌سازی', Icons.storage_outlined, [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('مدیریت فایل‌های موقت'),
              subtitle: Text('پاک‌سازی و مدیریت فضای ذخیره‌سازی در مرحله بعد اضافه می‌شود.'),
            ),
          ]),
          settingsGroup('درباره AVHA', Icons.info_outline, [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('AVHA – AI Content Studio'),
              subtitle: Text('خلق کن، متفاوت باش.'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('ابوالفضل هاشمی'),
              subtitle: Text('Founder & Creator | ایده‌پرداز و سازنده AVHA'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.camera_alt_outlined, color: gold),
              title: const Text('اینستاگرام سازنده'),
              subtitle: const Text('@aboalfazl7852'),
              onTap: () => showInfo('اینستاگرام سازنده', 'https://www.instagram.com/aboalfazl7852/'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('نسخه برنامه'),
              subtitle: Text('نسخه آزمایشی توسعه'),
            ),
          ]),
          const SizedBox(height: 12),
          const Center(child: Text('حساب کاربری، کد ورود و رمز عبور فعلاً در برنامه وجود ندارد.',
              style: TextStyle(color: Colors.white38, fontSize: 11))),
        ],
      );

  Widget settingsGroup(String title, IconData icon, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: gold),
            const SizedBox(width: 9),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const Divider(height: 22, color: Colors.white12),
          ...children,
        ])),
      );

  Widget dropdownSetting(String title, String value, List<String> options, ValueChanged<String> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(labelText: title, isDense: true),
          items: options.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!workspaceSelected) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SafeArea(child: workspaceSelectionPage()),
        ),
      );
    }
    final pages = [
      homePage(),
      captionsPage(),
      voicePage(),
      aiPage(),
      settingsPage(),
      editorPage(),
      projectsPage(),
    ];
    final safeTab = tab.clamp(0, pages.length - 1) as int;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            IndexedStack(index: safeTab, children: pages),
            if (busy)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    color: panel,
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const CircularProgressIndicator(color: gold),
                        const SizedBox(height: 14),
                        Text(status, textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: panel,
          indicatorColor: gold.withOpacity(.18),
          selectedIndex: tab <= 4 ? tab : 0,
          onDestinationSelected: (i) => go(i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: gold), label: 'خانه'),
            NavigationDestination(icon: Icon(Icons.subtitles_outlined), selectedIcon: Icon(Icons.subtitles, color: gold), label: 'زیرنویس'),
            NavigationDestination(icon: Icon(Icons.record_voice_over_outlined), selectedIcon: Icon(Icons.record_voice_over, color: gold), label: 'صدا'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome, color: gold), label: 'هوش مصنوعی'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings, color: gold), label: 'تنظیمات'),
          ],
        ),
      ),
    );
  }
}

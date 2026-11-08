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
  bool inWorkspace = false;
  String workspace = 'Ø´Ø®ØµÛŒ';
  String exportQuality = '1080p';
  String exportRatio = '9:16';
  String exportMode = 'Ù¾Ø± Ú©Ø±Ø¯Ù† Ú©Ø§Ø¯Ø±';
  List<File> savedClips = [];
  String clipFilter = 'Ù‡Ù…Ù‡';


  File? videoFile;
  VideoPlayerController? videoController;
  bool busy = false;
  String status = 'Ø¨Ø±Ø§ÛŒ Ø´Ø±ÙˆØ¹ØŒ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯.';

  String transcript = '';
  bool transcriptApproved = false;
  double subtitleFontSize = 22;
  double subtitleVerticalPosition = 0.82;
  String subtitleColorChoice = 'Ø³ÙÛŒØ¯';
  String subtitleBackgroundChoice = 'Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù';
  String subtitleAnimation = 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡';
  String subtitleFontFamily = 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶';

  Color get subtitleColor {
    switch (subtitleColorChoice) {
      case 'Ø·Ù„Ø§ÛŒÛŒ': return gold;
      case 'Ø²Ø±Ø¯': return Colors.yellow;
      case 'Ø¢Ø¨ÛŒ': return Colors.lightBlueAccent;
      case 'Ù…Ø´Ú©ÛŒ': return Colors.black;
      default: return Colors.white;
    }
  }

  String get subtitleSample {
    final clean = transcript.trim();
    if (clean.isEmpty) return 'Ù¾ÛŒØ´â€ŒÙ†Ù…Ø§ÛŒØ´ Ø²ÛŒØ±Ù†ÙˆÛŒØ³';
    final firstLine = clean.split(RegExp(r'[.!ØŸ?\n]')).first.trim();
    return firstLine.length > 48 ? '${firstLine.substring(0, 48)}â€¦' : firstLine;
  }
  String ideas = '';
  String caption = '';
  String topic = '';
  String hashtags = '';
  String voiceResult = '';
  String voiceFilePath = '';
  List<File> voiceLibrary = [];
  String selectedVoice = 'fa-IR-FaridNeural';

  final voiceController = TextEditingController();

  // Local preferences. Login and password are intentionally not included.
  bool darkTheme = true;
  bool autoSave = true;
  bool notifications = true;
  String accentChoice = 'Ø·Ù„Ø§ÛŒÛŒ';
  String language = 'ÙØ§Ø±Ø³ÛŒ';
  String outputQuality = '1080p';
  String aspectRatio = '9:16';
  String aiTone = 'Ø¯ÙˆØ³ØªØ§Ù†Ù‡';

  @override
  void initState() {
    super.initState();
    loadVoiceLibrary();
  }

  @override
  void dispose() {
    videoController?.dispose();
    voiceController.dispose();
    super.dispose();
  }

  String responseText(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  Map<String, dynamic> decodeJson(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw Exception('Ù¾Ø§Ø³Ø® Ø³Ø±ÙˆØ± Ù…Ø¹ØªØ¨Ø± Ù†ÛŒØ³Øª.');
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
      if (mounted) setState(() => status = 'Ø®Ø·Ø§: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickVideo() async {
    try {
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
        videoController = controller;
        transcript = '';
        transcriptApproved = false;
        ideas = '';
        caption = '';
        topic = '';
        hashtags = '';
        voiceResult = '';
        voiceFilePath = '';
        status = 'ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ø´Ø¯.';
        tab = 0;
      });
      await controller.initialize();
      await controller.setLooping(true);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => status = 'Ø®Ø·Ø§ Ø¯Ø± Ø§Ù†ØªØ®Ø§Ø¨ ÙˆÛŒØ¯Ø¦Ùˆ: $e');
    }
  }

  Future<Map<String, dynamic>> uploadVideoForTranscription() async {
    if (videoFile == null) throw Exception('Ø§Ø¨ØªØ¯Ø§ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯.');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBaseUrl/transcribe'),
    );
    request.headers['Accept'] = 'application/json';
    request.files.add(await http.MultipartFile.fromPath('video', videoFile!.path));
    final streamed = await request.send().timeout(const Duration(minutes: 10));
    final body = utf8.decode(await streamed.stream.toBytes(), allowMalformed: true);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('Ø®Ø·Ø§ÛŒ Ø³Ø±ÙˆØ± (${streamed.statusCode}): $body');
    }
    return decodeJson(body);
  }

  Future<void> transcribe() => runTask(() async {
        final data = await uploadVideoForTranscription();
        final text = (data['text'] ?? '').toString();
        if (text.trim().isEmpty) throw Exception('Ù…ØªÙ†ÛŒ Ø§Ø² ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ù†Ø´Ø¯.');
        setState(() {
          transcript = text;
          transcriptApproved = false;
          status = 'Ù…ØªÙ† ÙˆÛŒØ¯Ø¦Ùˆ Ø¨Ø§ Ù…ÙˆÙÙ‚ÛŒØª Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ø´Ø¯.';
        });
      }, 'Ø¯Ø± Ø­Ø§Ù„ Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ú¯ÙØªØ§Ø± ÙˆÛŒØ¯Ø¦Ùˆ...');

  Future<void> createIdeas() => runTask(() async {
        if (transcript.trim().isEmpty) {
          throw Exception('Ø§Ø¨ØªØ¯Ø§ Ù…ØªÙ† ÙˆÛŒØ¯Ø¦Ùˆ Ø±Ø§ Ø§Ø³ØªØ®Ø±Ø§Ø¬ ÛŒØ§ ÙˆØ§Ø±Ø¯ Ú©Ù†ÛŒØ¯.');
        }
        if (!transcriptApproved) {
          throw Exception('Ø§Ø¨ØªØ¯Ø§ Ø²ÛŒØ±Ù†ÙˆÛŒØ³ Ø±Ø§ Ø¨Ø±Ø±Ø³ÛŒ Ùˆ ØªØ£ÛŒÛŒØ¯ Ú©Ù†ÛŒØ¯.');
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
                'business': workspace == 'Ú©Ø§Ø±ÛŒ' ? 'AVHA Business' : 'AVHA Personal',
              })),
            )
            .timeout(const Duration(minutes: 3));
        final body = responseText(response);
        if (response.statusCode != 200) {
          throw Exception('Ø®Ø·Ø§ÛŒ ØªÙˆÙ„ÛŒØ¯ Ù…Ø­ØªÙˆØ§ (${response.statusCode}): $body');
        }
        final data = decodeJson(body);
        if (data['ok'] != true || data['content'] is! Map) {
          throw Exception('Ø³Ø§Ø®ØªØ§Ø± Ù¾Ø§Ø³Ø® Ø³Ø±ÙˆØ± Ù…Ø¹ØªØ¨Ø± Ù†ÛŒØ³Øª.');
        }
        final content = Map<String, dynamic>.from(data['content']);
        final tags = content['hashtags'];
        setState(() {
          topic = (content['topic'] ?? '').toString();
          ideas = (content['idea'] ?? '').toString();
          caption = (content['caption'] ?? '').toString();
          hashtags = tags is List ? tags.join('  ') : '';
          status = 'Ø§ÛŒØ¯Ù‡ Ùˆ Ú©Ù¾Ø´Ù† Ø¢Ù…Ø§Ø¯Ù‡ Ø´Ø¯.';
        });
      }, 'Ø¯Ø± Ø­Ø§Ù„ Ø³Ø§Ø®Øª Ø§ÛŒØ¯Ù‡ Ùˆ Ú©Ù¾Ø´Ù† Ø¨Ø§ Ù‡ÙˆØ´ Ù…ØµÙ†ÙˆØ¹ÛŒ...');

  Future<void> createVoice() => runTask(() async {
        final text = voiceController.text.trim();
        if (text.isEmpty) throw Exception('Ù…ØªÙ† Ù…ÙˆØ±Ø¯Ù†Ø¸Ø± Ø±Ø§ ÙˆØ§Ø±Ø¯ Ú©Ù†ÛŒØ¯.');
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
          throw Exception('ØªÙˆÙ„ÛŒØ¯ ØµØ¯Ø§ Ù†Ø§Ù…ÙˆÙÙ‚ Ø¨ÙˆØ¯: ${responseText(response)}');
        }
        if (response.bodyBytes.isEmpty) throw Exception('ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ Ø®Ø§Ù„ÛŒ Ø§Ø³Øª.');
        final appDir = await getApplicationDocumentsDirectory();
        final audioDir = Directory('${appDir.path}${Platform.pathSeparator}AVHA${Platform.pathSeparator}Audio');
        await audioDir.create(recursive: true);
        final file = File(
          '${audioDir.path}${Platform.pathSeparator}AVHA_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await loadVoiceLibrary();
        setState(() {
          voiceFilePath = file.path;
          voiceResult = 'ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ Ø³Ø§Ø®ØªÙ‡ Ø´Ø¯ Ùˆ Ø¯Ø± Ù¾ÙˆØ´Ù‡ ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ ØµÙˆØªÛŒ AVHA Ø°Ø®ÛŒØ±Ù‡ Ø´Ø¯.';
          status = 'ØªÙˆÙ„ÛŒØ¯ ØµØ¯Ø§ Ø¨Ø§ Ù…ÙˆÙÙ‚ÛŒØª Ø§Ù†Ø¬Ø§Ù… Ø´Ø¯.';
        });
      }, 'Ø¯Ø± Ø­Ø§Ù„ ØªÙˆÙ„ÛŒØ¯ ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ...');

  Future<Directory> voiceDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}${Platform.pathSeparator}AVHA${Platform.pathSeparator}${workspace}${Platform.pathSeparator}Audio');
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
      if (mounted) setState(() => status = 'Ø®Ø·Ø§ Ø¯Ø± Ø¨Ø§Ø±Ú¯Ø°Ø§Ø±ÛŒ ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ ØµÙˆØªÛŒ: $e');
    }
  }

  Future<void> saveVoiceFile(File file) async {
    try {
      final name = file.path.split(Platform.pathSeparator).last;
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Ø°Ø®ÛŒØ±Ù‡ ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ',
        fileName: name,
        bytes: await file.readAsBytes(),
      );
      if (destination != null && mounted) {
        setState(() => status = 'ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ Ø°Ø®ÛŒØ±Ù‡ Ø´Ø¯.');
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Ø°Ø®ÛŒØ±Ù‡ ÙØ§ÛŒÙ„ Ù†Ø§Ù…ÙˆÙÙ‚ Ø¨ÙˆØ¯: $e');
    }
  }

  Future<void> deleteVoiceFile(File file) async {
    final name = file.path.split(Platform.pathSeparator).last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Ø­Ø°Ù ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ'),
        content: Text('ÙØ§ÛŒÙ„ Â«$nameÂ» Ø­Ø°Ù Ø´ÙˆØ¯ØŸ'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Ø§Ù†ØµØ±Ø§Ù')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Ø­Ø°Ù', style: TextStyle(color: Colors.redAccent))),
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
          status = 'ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ Ø­Ø°Ù Ø´Ø¯.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Ø­Ø°Ù ÙØ§ÛŒÙ„ Ù†Ø§Ù…ÙˆÙÙ‚ Ø¨ÙˆØ¯: $e');
    }
  }

  void go(int index) => setState(() => tab = index);

  Future<Directory> workspaceDirectory([String? name]) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}AVHA${Platform.pathSeparator}${name ?? workspace}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> enterWorkspace(String name) async {
    setState(() {
      workspace = name;
      inWorkspace = true;
      tab = 0;
      savedClips = [];
    });
    await loadSavedClips();
    await loadVoiceLibrary();
  }

  Future<void> loadSavedClips() async {
    try {
      // One unified library, while files remain physically separated by workspace.
      final personalDir = await workspaceDirectory('Ø´Ø®ØµÛŒ');
      final businessDir = await workspaceDirectory('Ú©Ø§Ø±ÛŒ');
      final files = <File>[];
      for (final dir in [personalDir, businessDir]) {
        files.addAll(dir.listSync().whereType<File>().where((f) {
          final path = f.path.toLowerCase();
          return path.endsWith('.mp4') || path.endsWith('.mov') || path.endsWith('.m4v');
        }));
      }
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (mounted) setState(() => savedClips = files);
    } catch (e) {
      if (mounted) setState(() => status = 'Ø®Ø·Ø§ Ø¯Ø± Ø¨Ø§Ø±Ú¯Ø°Ø§Ø±ÛŒ Ú©ØªØ§Ø¨Ø®Ø§Ù†Ù‡ Ú©Ù„ÛŒÙ¾â€ŒÙ‡Ø§: $e');
    }
  }

  String clipWorkspace(File file) {
    return file.path.contains('${Platform.pathSeparator}Ú©Ø§Ø±ÛŒ${Platform.pathSeparator}') ? 'Ú©Ø§Ø±ÛŒ' : 'Ø´Ø®ØµÛŒ';
  }

  Future<void> saveCurrentClip() async {
    if (videoFile == null) {
      setState(() => status = 'Ø§Ø¨ØªØ¯Ø§ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯.');
      return;
    }
    try {
      final dir = await workspaceDirectory();
      final sourceName = videoFile!.path.split(Platform.pathSeparator).last;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final cleanName = sourceName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final target = File('${dir.path}${Platform.pathSeparator}AVHA_${stamp}_$cleanName');
      await videoFile!.copy(target.path);
      await loadSavedClips();
      if (mounted) setState(() => status = 'Ù†Ø³Ø®Ù‡ Ø§ØµÙ„ÛŒ ÙˆÛŒØ¯Ø¦Ùˆ Ø¯Ø± ÙØ¶Ø§ÛŒ $workspace Ø°Ø®ÛŒØ±Ù‡ Ø´Ø¯.');
    } catch (e) {
      if (mounted) setState(() => status = 'Ø°Ø®ÛŒØ±Ù‡ ÙˆÛŒØ¯Ø¦Ùˆ Ù†Ø§Ù…ÙˆÙÙ‚ Ø¨ÙˆØ¯: $e');
    }
  }

  Future<void> exportToDevice() async {
    if (videoFile == null) {
      setState(() => status = 'Ø§Ø¨ØªØ¯Ø§ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯.');
      return;
    }
    try {
      final name = 'AVHA_${workspace}_${exportRatio.replaceAll(':','x')}_${exportQuality}.mp4';
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Ø°Ø®ÛŒØ±Ù‡ Ø®Ø±ÙˆØ¬ÛŒ ÙˆÛŒØ¯Ø¦Ùˆ',
        fileName: name,
        bytes: await videoFile!.readAsBytes(),
      );
      if (destination != null && mounted) {
        setState(() => status = 'ÙØ§ÛŒÙ„ Ø§ØµÙ„ÛŒ ØµØ§Ø¯Ø± Ø´Ø¯. ØªÙ†Ø¸ÛŒÙ…Ø§Øª Ø§Ù†ØªØ®Ø§Ø¨ÛŒ Ù†Ø³Ø¨Øª ØªØµÙˆÛŒØ± Ùˆ Ú©ÛŒÙÛŒØª Ù‡Ù†ÙˆØ² Ø¯Ø± Ø§ÛŒÙ† Ù†Ø³Ø®Ù‡ Ø±ÙˆÛŒ ÙˆÛŒØ¯Ø¦Ùˆ Ø±Ù†Ø¯Ø± Ù†Ù…ÛŒâ€ŒØ´ÙˆÙ†Ø¯.');
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Ø®Ø±ÙˆØ¬ÛŒ Ú¯Ø±ÙØªÙ† Ù†Ø§Ù…ÙˆÙÙ‚ Ø¨ÙˆØ¯: $e');
    }
  }

  Widget exportPage() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Row(children: [
        IconButton(onPressed: () => go(5), icon: const Icon(Icons.arrow_forward, color: gold)),
        const Expanded(child: Text('ØªÙ†Ø¸ÛŒÙ…Ø§Øª Ø®Ø±ÙˆØ¬ÛŒ', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
      ]),
      if (videoFile == null) card(child: const Text('Ø§Ø¨ØªØ¯Ø§ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯.')) else ...[
        card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ù†ÙˆØ¹ Ø§Ù†ØªØ´Ø§Ø± Ø¯Ø± Ø§ÛŒÙ†Ø³ØªØ§Ú¯Ø±Ø§Ù…', style: TextStyle(fontWeight: FontWeight.bold, color: gold)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: exportRatio, decoration: const InputDecoration(labelText: 'Ø§Ø¨Ø¹Ø§Ø¯ Ùˆ Ù†Ø³Ø¨Øª ØªØµÙˆÛŒØ±'),
            items: const [
              DropdownMenuItem(value: '9:16', child: Text('Ø±ÛŒÙ„Ø² Ùˆ Ø§Ø³ØªÙˆØ±ÛŒ â€” 9:16')),
              DropdownMenuItem(value: '1:1', child: Text('Ù¾Ø³Øª Ù…Ø±Ø¨Ø¹ÛŒ â€” 1:1')),
              DropdownMenuItem(value: '4:5', child: Text('Ù¾Ø³Øª Ø¹Ù…ÙˆØ¯ÛŒ ÙÛŒØ¯ â€” 4:5')),
              DropdownMenuItem(value: '16:9', child: Text('ÙˆÛŒØ¯Ø¦ÙˆÛŒ Ø§ÙÙ‚ÛŒ â€” 16:9')),
            ], onChanged: (v) { if (v != null) setState(() => exportRatio = v); }),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: exportMode, decoration: const InputDecoration(labelText: 'Ù†Ø­ÙˆÙ‡ Ù‚Ø±Ø§Ø±Ú¯ÛŒØ±ÛŒ ØªØµÙˆÛŒØ±'),
            items: const [DropdownMenuItem(value: 'Ù¾Ø± Ú©Ø±Ø¯Ù† Ú©Ø§Ø¯Ø±', child: Text('Ù¾Ø± Ú©Ø±Ø¯Ù† Ú©Ø§Ø¯Ø± (Ø¨Ø±Ø´ Ù„Ø¨Ù‡â€ŒÙ‡Ø§)')), DropdownMenuItem(value: 'Ø­ÙØ¸ Ú©Ø§Ù…Ù„ ØªØµÙˆÛŒØ±', child: Text('Ø­ÙØ¸ Ú©Ø§Ù…Ù„ ØªØµÙˆÛŒØ±'))],
            onChanged: (v) { if (v != null) setState(() => exportMode = v); }),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: exportQuality, decoration: const InputDecoration(labelText: 'Ú©ÛŒÙÛŒØª Ø®Ø±ÙˆØ¬ÛŒ'),
            items: const [DropdownMenuItem(value: '720p', child: Text('720p HD')), DropdownMenuItem(value: '1080p', child: Text('1080p Full HD')), DropdownMenuItem(value: '4K', child: Text('4K (Ø¯Ø± ØµÙˆØ±Øª Ù¾Ø´ØªÛŒØ¨Ø§Ù†ÛŒ)'))],
            onChanged: (v) { if (v != null) setState(() => exportQuality = v); }),
        ])),
        const SizedBox(height: 12),
        card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ù…Ø­Ù„ Ø°Ø®ÛŒØ±Ù‡', style: TextStyle(fontWeight: FontWeight.bold, color: gold)),
          const SizedBox(height: 6),
          Text('ÙØ¶Ø§ÛŒ $workspace â€” Ø°Ø®ÛŒØ±Ù‡â€ŒØ³Ø§Ø²ÛŒ Ø¯Ø§Ø®Ù„ÛŒ AVHA Ùˆ Ø¬Ø¯Ø§Ø³Ø§Ø²ÛŒ Ú©Ø§Ù…Ù„ Ø§Ø² ÙØ¶Ø§ÛŒ Ø¯ÛŒÚ¯Ø±'),
          const SizedBox(height: 12),
          goldButton('Ø°Ø®ÛŒØ±Ù‡ Ø¯Ø± ÙØ¶Ø§ÛŒ $workspace', saveCurrentClip, icon: Icons.folder_special),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: exportToDevice, icon: const Icon(Icons.save_alt), label: const Text('Ø°Ø®ÛŒØ±Ù‡ ÙØ§ÛŒÙ„ Ø¯Ø± Ù…Ø­Ù„ Ø¯Ù„Ø®ÙˆØ§Ù‡ Ú¯ÙˆØ´ÛŒ')),
        ])),
        const SizedBox(height: 12),
        const Text('ØªÙˆØ¬Ù‡: Ø¯Ø± Ø§ÛŒÙ† Ù†Ø³Ø®Ù‡ Ø°Ø®ÛŒØ±Ù‡â€ŒØ³Ø§Ø²ÛŒ ÙØ§ÛŒÙ„ Ø§ØµÙ„ÛŒ ÙØ¹Ø§Ù„ Ø§Ø³Øª. Ø§Ø¹Ù…Ø§Ù„ ÙˆØ§Ù‚Ø¹ÛŒ Ø¨Ø±Ø´ Ø§Ø¨Ø¹Ø§Ø¯ØŒ ØªØºÛŒÛŒØ± Ø±Ø²ÙˆÙ„ÙˆØ´Ù† Ùˆ Ø±Ù†Ø¯Ø± Ù†Ù‡Ø§ÛŒÛŒ Ø¨Ù‡ Ù…ÙˆØªÙˆØ± Ø®Ø±ÙˆØ¬ÛŒ ÙˆÛŒØ¯Ø¦Ùˆ Ù†ÛŒØ§Ø² Ø¯Ø§Ø±Ø¯ Ùˆ Ù‡Ù†ÙˆØ² ÙØ¹Ø§Ù„ Ù†Ø´Ø¯Ù‡ Ø§Ø³ØªØ› Ú¯Ø²ÛŒÙ†Ù‡â€ŒÙ‡Ø§ÛŒ Ø¨Ø§Ù„Ø§ ÙØ¹Ù„Ø§Ù‹ Ø§Ù†ØªØ®Ø§Ø¨ ØªÙ†Ø¸ÛŒÙ…Ø§Øª Ù‡Ø³ØªÙ†Ø¯.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
      ],
    ],
  );

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
            Text('Ù¾ÛŒØ´â€ŒÙ†Ù…Ø§ÛŒØ´ ÙˆÛŒØ¯Ø¦Ùˆ', style: TextStyle(color: Colors.white70)),
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
                      color: subtitleBackgroundChoice == 'Ø¨Ø¯ÙˆÙ† Ù¾Ø³â€ŒØ²Ù…ÛŒÙ†Ù‡'
                          ? Colors.transparent
                          : Colors.black.withOpacity(
                              subtitleBackgroundChoice == 'Ù¾Ø±Ø±Ù†Ú¯' ? .85 : .55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      subtitleSample,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: subtitleFontSize,
                        fontFamily: subtitleFontFamily == 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶' ? null : subtitleFontFamily,
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
        onTap: () => enterWorkspace(title == 'ÙØ¶Ø§ÛŒ Ú©Ø§Ø±ÛŒ' ? 'Ú©Ø§Ø±ÛŒ' : 'Ø´Ø®ØµÛŒ'),
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
                Text('ÙˆØ±ÙˆØ¯ Ø¨Ù‡ ÙØ¶Ø§', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                const Icon(Icons.chevron_left, size: 18),
              ]),
            ],
          ),
        ),
      );

  Widget homePage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SizedBox(height: 28),
      const Center(child: Text('AVHA', style: TextStyle(color: gold, fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: 3))),
      const SizedBox(height: 5),
      const Center(child: Text('CREATE â€¢ DIFFERENTLY', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 3))),
      const SizedBox(height: 48),
      const Text('Ø¨Ù‡ Ú©Ø¯Ø§Ù… ÙØ¶Ø§ ÙˆØ§Ø±Ø¯ Ù…ÛŒâ€ŒØ´ÙˆÛŒØ¯ØŸ', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 9),
      const Text('ÙØ¶Ø§ÛŒ Ø´Ø®ØµÛŒ Ùˆ Ú©Ø§Ø±ÛŒ Ù…Ø³ØªÙ‚Ù„ Ø§Ø² ÛŒÚ©Ø¯ÛŒÚ¯Ø± Ø°Ø®ÛŒØ±Ù‡ Ù…ÛŒâ€ŒØ´ÙˆÙ†Ø¯.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 28),
      Row(children: [
        Expanded(child: modeCard('ÙØ¶Ø§ÛŒ Ø´Ø®ØµÛŒ', 'Ù…Ø­ØªÙˆØ§ÛŒ Ø´Ø®ØµÛŒØŒ ÙˆÙ„Ø§Ú¯ Ùˆ Ø´Ø¨Ú©Ù‡â€ŒÙ‡Ø§ÛŒ Ø§Ø¬ØªÙ…Ø§Ø¹ÛŒ', Icons.person_outline, blue)),
        const SizedBox(width: 12),
        Expanded(child: modeCard('ÙØ¶Ø§ÛŒ Ú©Ø§Ø±ÛŒ', 'Ù¾Ø±ÙˆÚ˜Ù‡â€ŒÙ‡Ø§ Ùˆ Ù…Ø­ØªÙˆØ§ÛŒ Ú©Ø³Ø¨â€ŒÙˆÚ©Ø§Ø±', Icons.business_center_outlined, gold)),
      ]),
      const SizedBox(height: 24),
      const Center(child: Text('Ø®Ù„Ù‚ Ú©Ù†ØŒ Ù…ØªÙØ§ÙˆØª Ø¨Ø§Ø´.', style: TextStyle(color: gold, fontWeight: FontWeight.w600))),
    ],
  );

  Widget workspaceHomePage() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Row(children: [
        IconButton(onPressed: () => setState(() { inWorkspace = false; tab = 0; }), icon: const Icon(Icons.arrow_forward, color: gold)),
        Expanded(child: Text('ÙØ¶Ø§ÛŒ $workspace', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        const Icon(Icons.folder_special_outlined, color: gold),
      ]),
      const SizedBox(height: 14),
      card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ø§Ø³ØªÙˆØ¯ÛŒÙˆÛŒ Ù…Ø­ØªÙˆØ§ÛŒ AVHA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        const Text('Ø§Ø¨Ø²Ø§Ø±Ù‡Ø§ÛŒ ØªÙˆÙ„ÛŒØ¯ Ùˆ ØªØ¯ÙˆÛŒÙ† Ø¯Ø± ÙØ¶Ø§ÛŒ Ø§Ù†ØªØ®Ø§Ø¨â€ŒØ´Ø¯Ù‡ Ø¯Ø± Ø¯Ø³ØªØ±Ø³ Ù‡Ø³ØªÙ†Ø¯.' , style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 14),
        goldButton('Ø§Ù†ØªØ®Ø§Ø¨ ÙˆÛŒØ¯Ø¦Ùˆ Ø¨Ø±Ø§ÛŒ ØªØ¯ÙˆÛŒÙ†', pickVideo, icon: Icons.video_library_outlined),
        if (videoFile != null) ...[
          const SizedBox(height: 12), videoPreview(),
          const SizedBox(height: 8),
          goldButton('ÙˆØ±ÙˆØ¯ Ø¨Ù‡ Ù…Ø­ÛŒØ· ØªØ¯ÙˆÛŒÙ†', () => go(5), icon: Icons.movie_edit_outlined),
        ],
      ])),
      const SizedBox(height: 16),
      featureRow(Icons.subtitles, 'Ø²ÛŒØ±Ù†ÙˆÛŒØ³ Ù‡ÙˆØ´Ù…Ù†Ø¯', 'ØªØ¨Ø¯ÛŒÙ„ Ú¯ÙØªØ§Ø± ÙˆÛŒØ¯Ø¦Ùˆ Ø¨Ù‡ Ù…ØªÙ† Ùˆ ÙˆÛŒØ±Ø§ÛŒØ´ Ø¢Ù†', () => go(1), blue),
      featureRow(Icons.record_voice_over, 'Ù…ØªÙ† Ø¨Ù‡ Ú¯ÙØªØ§Ø±', 'ØªÙˆÙ„ÛŒØ¯ Ùˆ Ù…Ø¯ÛŒØ±ÛŒØª ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ ØµÙˆØªÛŒ', () => go(2), purple),
      featureRow(Icons.auto_awesome, 'Ø§ÛŒØ¯Ù‡ Ùˆ Ú©Ù¾Ø´Ù†', 'Ø§ÛŒØ¯Ù‡ØŒ Ø³Ù†Ø§Ø±ÛŒÙˆØŒ Ú©Ù¾Ø´Ù† Ùˆ Ù‡Ø´ØªÚ¯', () => go(3), gold),
      featureRow(Icons.folder_open, 'Ù¾Ø±ÙˆÚ˜Ù‡â€ŒÙ‡Ø§ Ùˆ Ø®Ø±ÙˆØ¬ÛŒâ€ŒÙ‡Ø§', 'ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ Ø°Ø®ÛŒØ±Ù‡â€ŒØ´Ø¯Ù‡ Ø¯Ø± ÙØ¶Ø§ÛŒ $workspace', () => go(6), blue),
      const SizedBox(height: 12),
      card(child: Text(status, style: const TextStyle(color: Colors.white70))),
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
          sectionTitle('Ø§Ø³ØªÙˆØ¯ÛŒÙˆÛŒ Ø²ÛŒØ±Ù†ÙˆÛŒØ³', subtitle: 'Ø§ÙˆÙ„ Ù…ØªÙ† Ø±Ø§ Ø§ØµÙ„Ø§Ø­ Ùˆ ØªØ£ÛŒÛŒØ¯ Ú©Ù†Ø› Ø³Ù¾Ø³ Ø¸Ø§Ù‡Ø± Ø²ÛŒØ±Ù†ÙˆÛŒØ³ Ø±Ø§ ØªÙ†Ø¸ÛŒÙ… Ú©Ù†.'),
          card(child: Column(children: [
            goldButton('Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ù…ØªÙ† Ø§Ø² ÙˆÛŒØ¯Ø¦Ùˆ', videoFile == null ? null : transcribe, icon: Icons.subtitles),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('transcriptEditor'),
              initialValue: transcript,
              maxLines: 8,
              onChanged: (v) => setState(() {
                transcript = v;
                transcriptApproved = false;
              }),
              decoration: const InputDecoration(
                hintText: 'Ù…ØªÙ† ØªØ´Ø®ÛŒØµâ€ŒØ¯Ø§Ø¯Ù‡â€ŒØ´Ø¯Ù‡ Ø±Ø§ Ø§ÛŒÙ†Ø¬Ø§ Ø§ØµÙ„Ø§Ø­ Ú©Ù†Ø› Ù…Ø«Ù„Ø§Ù‹ Ú©Ù†Ø§ÙØŒ ØªØ±Ø§Ø² Ø³Ø§Ù†Øª Ùˆ Ø§Ù…â€ŒØ¯ÛŒâ€ŒØ§Ù...',
                labelText: 'Ù…ØªÙ† Ù‚Ø§Ø¨Ù„ ÙˆÛŒØ±Ø§ÛŒØ´ Ø²ÛŒØ±Ù†ÙˆÛŒØ³',
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(transcriptApproved ? Icons.verified : Icons.edit_note,
                  color: transcriptApproved ? Colors.greenAccent : gold),
              const SizedBox(width: 8),
              Expanded(child: Text(
                transcriptApproved ? 'Ù…ØªÙ† ØªØ£ÛŒÛŒØ¯ Ø´Ø¯Ù‡Ø› Ù‡ÙˆØ´ Ù…ØµÙ†ÙˆØ¹ÛŒ Ø§Ø² Ù‡Ù…ÛŒÙ† Ù…ØªÙ† Ø§Ø³ØªÙØ§Ø¯Ù‡ Ù…ÛŒâ€ŒÚ©Ù†Ø¯.'
                    : 'Ù‚Ø¨Ù„ Ø§Ø² Ø³Ø§Ø®Øª Ú©Ù¾Ø´Ù† Ùˆ Ø§ÛŒØ¯Ù‡ØŒ Ù…ØªÙ† Ø±Ø§ Ø¨Ø±Ø±Ø³ÛŒ Ùˆ ØªØ£ÛŒÛŒØ¯ Ú©Ù†.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              )),
            ]),
            const SizedBox(height: 10),
            goldButton(
              transcriptApproved ? 'Ù…ØªÙ† ØªØ£ÛŒÛŒØ¯ Ø´Ø¯' : 'ØªØ£ÛŒÛŒØ¯ Ù…ØªÙ† Ø§ØµÙ„Ø§Ø­â€ŒØ´Ø¯Ù‡',
              transcript.trim().isEmpty ? null : () => setState(() {
                transcriptApproved = true;
                status = 'Ù…ØªÙ† Ø²ÛŒØ±Ù†ÙˆÛŒØ³ ØªØ£ÛŒÛŒØ¯ Ø´Ø¯Ø› Ø­Ø§Ù„Ø§ Ù…ÛŒâ€ŒØªÙˆØ§Ù†ÛŒ Ù…Ø­ØªÙˆØ§ÛŒ Ù‡ÙˆØ´Ù…Ù†Ø¯ Ø¨Ø³Ø§Ø²ÛŒ.';
              }),
              icon: Icons.check_circle_outline,
            ),
          ])),
          const SizedBox(height: 16),
          sectionTitle('Ø·Ø±Ø§Ø­ÛŒ Ùˆ Ø¬Ø§ÛŒÚ¯Ø§Ù‡ Ø²ÛŒØ±Ù†ÙˆÛŒØ³'),
          if (videoFile != null) ...[
            videoPreview(height: 230),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Ø¨Ø±Ø§ÛŒ Ø¬Ø§Ø¨Ù‡â€ŒØ¬Ø§ÛŒÛŒØŒ Ù…ØªÙ† Ø±ÙˆÛŒ ØªØµÙˆÛŒØ± Ø±Ø§ Ø¨Ø§ Ø§Ù†Ú¯Ø´Øª ÛŒØ§ Ù…Ø§ÙˆØ³ Ø¨Ú©Ø´.',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          ] else
            card(child: const Text('Ø¨Ø±Ø§ÛŒ Ø¯ÛŒØ¯Ù† Ù¾ÛŒØ´â€ŒÙ†Ù…Ø§ÛŒØ´ØŒ Ø§Ø¨ØªØ¯Ø§ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†.')),
          const SizedBox(height: 12),
          card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ø§Ù†Ø¯Ø§Ø²Ù‡ ÙÙˆÙ†Øª: ${subtitleFontSize.round()}',
                style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
            Slider(
              value: subtitleFontSize,
              min: 12,
              max: 42,
              divisions: 15,
              activeColor: gold,
              onChanged: (v) => setState(() => subtitleFontSize = v),
            ),
            DropdownButtonFormField<String>(
              value: subtitleFontFamily,
              decoration: const InputDecoration(labelText: 'Ù†ÙˆØ¹ ÙÙˆÙ†Øª'),
              items: const [
                DropdownMenuItem(value: 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶', child: Text('Ù¾ÛŒØ´â€ŒÙØ±Ø¶')),
                DropdownMenuItem(value: 'serif', child: Text('Ø³Ø±ÛŒÙ')),
                DropdownMenuItem(value: 'monospace', child: Text('ØªÚ©â€ŒÙØ§ØµÙ„Ù‡')),
              ],
              onChanged: (v) { if (v != null) setState(() => subtitleFontFamily = v); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleColorChoice,
              decoration: const InputDecoration(labelText: 'Ø±Ù†Ú¯ Ù†ÙˆØ´ØªÙ‡'),
              items: ['Ø³ÙÛŒØ¯', 'Ø·Ù„Ø§ÛŒÛŒ', 'Ø²Ø±Ø¯', 'Ø¢Ø¨ÛŒ', 'Ù…Ø´Ú©ÛŒ']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() => subtitleColorChoice = v); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleBackgroundChoice,
              decoration: const InputDecoration(labelText: 'Ù¾Ø³â€ŒØ²Ù…ÛŒÙ†Ù‡ Ø²ÛŒØ±Ù†ÙˆÛŒØ³'),
              items: ['Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù', 'Ù¾Ø±Ø±Ù†Ú¯', 'Ø¨Ø¯ÙˆÙ† Ù¾Ø³â€ŒØ²Ù…ÛŒÙ†Ù‡']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() => subtitleBackgroundChoice = v); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleAnimation,
              decoration: const InputDecoration(labelText: 'Ù†Ø­ÙˆÙ‡ Ù†Ù…Ø§ÛŒØ´ Ù…ØªÙ†'),
              items: ['ÛŒÚ©â€ŒØ¬Ø§', 'Ø­Ø±Ùâ€ŒØ¨Ù‡â€ŒØ­Ø±Ù', 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡', 'Ø¨Ø±Ø¬Ø³ØªÙ‡â€ŒØ³Ø§Ø²ÛŒ Ú©Ù„Ù…Ù‡ ÙØ¹Ø§Ù„']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() => subtitleAnimation = v); },
            ),
            const SizedBox(height: 10),
            Text('Ù…ÙˆÙ‚Ø¹ÛŒØª Ø¹Ù…ÙˆØ¯ÛŒ: ${(subtitleVerticalPosition * 100).round()}%',
                style: const TextStyle(color: Colors.white70)),
            Slider(
              value: subtitleVerticalPosition,
              min: -0.9,
              max: 0.9,
              activeColor: gold,
              onChanged: (v) => setState(() => subtitleVerticalPosition = v),
            ),
          ])),
          const SizedBox(height: 12),
          card(child: const Text(
            'Ù†Ú©ØªÙ‡: Ø¯Ø± Ø§ÛŒÙ† Ù…Ø±Ø­Ù„Ù‡ ÙˆÛŒØ±Ø§ÛŒØ´ Ù…ØªÙ† Ùˆ Ù¾ÛŒØ´â€ŒÙ†Ù…Ø§ÛŒØ´ Ø·Ø±Ø§Ø­ÛŒ ÙØ¹Ø§Ù„ Ø§Ø³Øª. Ø²Ù…Ø§Ù†â€ŒØ¨Ù†Ø¯ÛŒ Ø¯Ù‚ÛŒÙ‚ Ú©Ù„Ù…Ù‡â€ŒÙ‡Ø§ Ùˆ Ú†Ø³Ø¨Ø§Ù†Ø¯Ù† Ø¯Ø§Ø¦Ù…ÛŒ Ø²ÛŒØ±Ù†ÙˆÛŒØ³ Ø¨Ù‡ ÙØ§ÛŒÙ„ Ø®Ø±ÙˆØ¬ÛŒØŒ Ø¨Ù‡ Ø¯Ø±ÛŒØ§ÙØª Ø²Ù…Ø§Ù†â€ŒØ¨Ù†Ø¯ÛŒ Ú©Ù„Ù…Ù‡â€ŒØ§ÛŒ Ø§Ø² Ø³Ø±ÙˆØ± Ùˆ Ù…ÙˆØªÙˆØ± Ø±Ù†Ø¯Ø± ÙˆÛŒØ¯Ø¦Ùˆ Ù†ÛŒØ§Ø² Ø¯Ø§Ø±Ø¯ Ùˆ Ø¯Ø± Ù…Ø±Ø­Ù„Ù‡ ÙÙ†ÛŒ Ø¨Ø¹Ø¯ÛŒ ÙˆØµÙ„ Ù…ÛŒâ€ŒØ´ÙˆØ¯.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          )),
        ],
      );

  Widget voicePage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('ØªØ¨Ø¯ÛŒÙ„ Ù…ØªÙ† Ø¨Ù‡ ØµØ¯Ø§', subtitle: 'Ù…ØªÙ† Ø®ÙˆØ¯ Ø±Ø§ Ø¨Ø§ ØµØ¯Ø§ÛŒ ÙØ§Ø±Ø³ÛŒ Ø¨Ù‡ ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ ØªØ¨Ø¯ÛŒÙ„ Ú©Ù†.'),
          TextField(
            controller: voiceController,
            maxLines: 7,
            decoration: const InputDecoration(hintText: 'Ù…ØªÙ† Ù…ÙˆØ±Ø¯Ù†Ø¸Ø± Ø¨Ø±Ø§ÛŒ ØªØ¨Ø¯ÛŒÙ„ Ø¨Ù‡ ØµØ¯Ø§...'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: selectedVoice,
            decoration: const InputDecoration(labelText: 'ØµØ¯Ø§ÛŒ Ú¯ÙˆÛŒÙ†Ø¯Ù‡'),
            items: const [
              DropdownMenuItem(value: 'fa-IR-FaridNeural', child: Text('ØµØ¯Ø§ÛŒ Ù…Ø±Ø¯')),
              DropdownMenuItem(value: 'fa-IR-DilaraNeural', child: Text('ØµØ¯Ø§ÛŒ Ø²Ù†')),
            ],
            onChanged: (v) { if (v != null) setState(() => selectedVoice = v); },
          ),
          const SizedBox(height: 14),
          goldButton('ØªÙˆÙ„ÛŒØ¯ ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ', createVoice, icon: Icons.graphic_eq),
          if (voiceResult.isNotEmpty) ...[
            const SizedBox(height: 14),
            card(child: SelectableText(voiceResult, style: const TextStyle(color: gold))),
          ],
          const SizedBox(height: 22),
          Row(children: [
            const Expanded(child: Text('ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ ØµÙˆØªÛŒ Ù…Ù†', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(onPressed: loadVoiceLibrary, tooltip: 'Ø¨Ù‡â€ŒØ±ÙˆØ²Ø±Ø³Ø§Ù†ÛŒ', icon: const Icon(Icons.refresh, color: gold)),
          ]),
          Text('ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ Ø³Ø§Ø®ØªÙ‡â€ŒØ´Ø¯Ù‡ Ø¯Ø± Ù¾ÙˆØ´Ù‡ Ø§Ø®ØªØµØ§ØµÛŒ AVHA Ù†Ú¯Ù‡Ø¯Ø§Ø±ÛŒ Ù…ÛŒâ€ŒØ´ÙˆÙ†Ø¯.', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 10),
          if (voiceLibrary.isEmpty)
            card(child: const Row(children: [
              Icon(Icons.audio_file_outlined, color: gold, size: 30),
              SizedBox(width: 10),
              Expanded(child: Text('Ù‡Ù†ÙˆØ² ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ Ø°Ø®ÛŒØ±Ù‡â€ŒØ´Ø¯Ù‡â€ŒØ§ÛŒ Ù†Ø¯Ø§Ø±ÛŒ.')),
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
                  IconButton(tooltip: 'Ø°Ø®ÛŒØ±Ù‡ Ø¯Ø± Ø¯Ø³ØªÚ¯Ø§Ù‡', onPressed: () => saveVoiceFile(file), icon: const Icon(Icons.save_alt, color: blue)),
                  IconButton(tooltip: 'Ø­Ø°Ù ÙØ§ÛŒÙ„', onPressed: () => deleteVoiceFile(file), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                ])),
              );
            }),
        ],
      );

  Widget aiPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('Ø§Ø³ØªÙˆØ¯ÛŒÙˆÛŒ Ù‡ÙˆØ´Ù…Ù†Ø¯ AI', subtitle: 'Ø¨Ø±Ø§ÛŒ ÙØ¶Ø§ÛŒ ${workspace == 'Ú©Ø§Ø±ÛŒ' ? 'Ú©Ø§Ø±ÛŒ' : 'Ø´Ø®ØµÛŒ'} Ù…Ø­ØªÙˆØ§ÛŒ Ù…Ù†Ø§Ø³Ø¨ Ø¨Ø³Ø§Ø².'),
          card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.psychology_alt, color: purple, size: 48),
            const SizedBox(height: 8),
            const Text('ØªÙˆÙ„ÛŒØ¯ Ø§ÛŒØ¯Ù‡ØŒ Ø³Ù†Ø§Ø±ÛŒÙˆØŒ Ú©Ù¾Ø´Ù† Ùˆ Ù‡Ø´ØªÚ¯', textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            goldButton('Ø³Ø§Ø®Øª Ù…Ø­ØªÙˆØ§ÛŒ Ù¾ÛŒØ´Ù†Ù‡Ø§Ø¯ÛŒ', (transcript.trim().isEmpty || !transcriptApproved) ? null : createIdeas),
          ])),
          const SizedBox(height: 14),
          if (topic.isNotEmpty) resultCard('Ø¹Ù†ÙˆØ§Ù† Ù¾ÛŒØ´Ù†Ù‡Ø§Ø¯ÛŒ', topic),
          if (ideas.isNotEmpty) resultCard('Ø§ÛŒØ¯Ù‡ Ùˆ Ø³Ù†Ø§Ø±ÛŒÙˆ', ideas),
          if (caption.isNotEmpty) resultCard('Ú©Ù¾Ø´Ù†', caption),
          if (hashtags.isNotEmpty) resultCard('Ù‡Ø´ØªÚ¯â€ŒÙ‡Ø§', hashtags),
          if (transcript.trim().isEmpty || !transcriptApproved)
            const Padding(
              padding: EdgeInsets.only(top: 15),
              child: Text('Ø§Ø¨ØªØ¯Ø§ Ø¯Ø± Ø¨Ø®Ø´ Ø²ÛŒØ±Ù†ÙˆÛŒØ³ØŒ Ù…ØªÙ† Ø±Ø§ Ø§ØµÙ„Ø§Ø­ Ùˆ ØªØ£ÛŒÛŒØ¯ Ú©Ù†.',
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

  Widget projectsPage() {
    final visibleClips = savedClips.where((file) =>
      clipFilter == 'Ù‡Ù…Ù‡' || clipWorkspace(file) == clipFilter
    ).toList();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        sectionTitle('Ú©ØªØ§Ø¨Ø®Ø§Ù†Ù‡ Ú©Ù„ÛŒÙ¾â€ŒÙ‡Ø§ÛŒ Ù…Ù†', subtitle: 'Ù‡Ù…Ù‡ Ø®Ø±ÙˆØ¬ÛŒâ€ŒÙ‡Ø§ÛŒ ÙØ¶Ø§ÛŒ Ø´Ø®ØµÛŒ Ùˆ Ú©Ø§Ø±ÛŒ Ø¯Ø± ÛŒÚ©Ø¬Ø§Ø› Ø¨Ø§ Ø¯Ø³ØªÙ‡â€ŒØ¨Ù†Ø¯ÛŒ Ù…Ø³ØªÙ‚Ù„.'),
        Wrap(spacing: 8, children: [
          for (final filter in ['Ù‡Ù…Ù‡', 'Ø´Ø®ØµÛŒ', 'Ú©Ø§Ø±ÛŒ'])
            ChoiceChip(
              label: Text(filter == 'Ù‡Ù…Ù‡' ? 'Ù‡Ù…Ù‡ Ú©Ù„ÛŒÙ¾â€ŒÙ‡Ø§' : 'ÙØ¶Ø§ÛŒ $filter'),
              selected: clipFilter == filter,
              selectedColor: gold.withOpacity(0.22),
              onSelected: (_) => setState(() => clipFilter = filter),
            ),
        ]),
        const SizedBox(height: 12),
        if (visibleClips.isEmpty)
          card(child: Text(clipFilter == 'Ù‡Ù…Ù‡' ? 'Ù‡Ù†ÙˆØ² Ú©Ù„ÛŒÙ¾ÛŒ Ø°Ø®ÛŒØ±Ù‡ Ù†Ø´Ø¯Ù‡ Ø§Ø³Øª.' : 'Ø¯Ø± ÙØ¶Ø§ÛŒ $clipFilter Ù‡Ù†ÙˆØ² Ú©Ù„ÛŒÙ¾ÛŒ Ø°Ø®ÛŒØ±Ù‡ Ù†Ø´Ø¯Ù‡ Ø§Ø³Øª.'))
        else ...visibleClips.map((file) => card(child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.video_file, color: gold, size: 30),
          title: Text(file.uri.pathSegments.last, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('ÙØ¶Ø§ÛŒ ${clipWorkspace(file)}  â€¢  ${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} Ù…Ú¯Ø§Ø¨Ø§ÛŒØª'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              await file.delete();
              await loadSavedClips();
            },
          ),
        ))),
        const SizedBox(height: 12),
        if (videoFile != null)
          goldButton('Ø°Ø®ÛŒØ±Ù‡ ÙˆÛŒØ¯Ø¦ÙˆÛŒ ÙØ¹Ù„ÛŒ Ø¯Ø± ÙØ¶Ø§ÛŒ $workspace', saveCurrentClip, icon: Icons.save),
      ],
    );
  }

  Widget editorPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(children: [
            IconButton(onPressed: () => go(0), icon: const Icon(Icons.arrow_forward, color: gold)),
            const Expanded(child: Text('Ù…Ø­ÛŒØ· ØªØ¯ÙˆÛŒÙ†', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
            TextButton(onPressed: () => go(7), child: const Text('Ø®Ø±ÙˆØ¬ÛŒ')),
          ]),
          if (videoFile == null) ...[
            card(child: const Text('Ø¨Ø±Ø§ÛŒ Ø´Ø±ÙˆØ¹ ØªØ¯ÙˆÛŒÙ†ØŒ Ø§Ø¨ØªØ¯Ø§ Ø§Ø² ØµÙØ­Ù‡ Ø®Ø§Ù†Ù‡ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†.')),
            const SizedBox(height: 10),
            goldButton('Ø§Ù†ØªØ®Ø§Ø¨ ÙˆÛŒØ¯Ø¦Ùˆ', pickVideo, icon: Icons.video_library),
          ] else ...[
            videoPreview(height: 230),
            const SizedBox(height: 12),
            card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ù†ÙˆØ§Ø± Ø²Ù…Ø§Ù† ÙˆÛŒØ¯Ø¦Ùˆ', style: TextStyle(fontWeight: FontWeight.bold, color: gold)),
              const SizedBox(height: 10),
              VideoProgressIndicator(videoController!, allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: gold, bufferedColor: Colors.white24)),
              const SizedBox(height: 8),
              const Text('Ù¾ÛŒØ´â€ŒÙ†Ù…Ø§ÛŒØ´ Ùˆ Ø¬Ø§Ø¨Ù‡â€ŒØ¬Ø§ÛŒÛŒ Ø±ÙˆÛŒ ÙˆÛŒØ¯Ø¦Ùˆ ÙØ¹Ø§Ù„ Ø§Ø³ØªØ› Ø§Ø¨Ø²Ø§Ø±Ù‡Ø§ÛŒ Ø¨Ø±Ø´ Ùˆ Ù„Ø§ÛŒÙ‡â€ŒÙ‡Ø§ Ø¯Ø± ÙØ§Ø² ØªØ¯ÙˆÛŒÙ† Ø§Ø¶Ø§ÙÙ‡ Ù…ÛŒâ€ŒØ´ÙˆÙ†Ø¯.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            const SizedBox(height: 12),
            const Text('Ø§Ø¨Ø²Ø§Ø±Ù‡Ø§ÛŒ ØªØ¯ÙˆÛŒÙ†', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              'Ø¨Ø±Ø´', 'ØªÙ‚Ø³ÛŒÙ…', 'Ù…ÙˆØ³ÛŒÙ‚ÛŒ', 'Ù…ØªÙ†', 'ÙÛŒÙ„ØªØ±', 'Ø§ÙÚ©Øª',
              'ØªÙ†Ø¸ÛŒÙ… Ø±Ù†Ú¯', 'ØªØ±Ù†Ø²ÛŒØ´Ù†', 'Ø²ÛŒØ±Ù†ÙˆÛŒØ³', 'Ø§Ø³ØªÛŒÚ©Ø±',
            ].map((name) => ActionChip(
              avatar: const Icon(Icons.construction, size: 17, color: gold),
              label: Text(name),
              onPressed: () => showInfo(name, 'Ø§Ø¨Ø²Ø§Ø± $name Ø¯Ø± Ø·Ø±Ø§Ø­ÛŒ Ù…Ø´Ø®Øµ Ø´Ø¯Ù‡ Ùˆ Ø§ØªØµØ§Ù„ Ø¹Ù…Ù„Ú©Ø±Ø¯ ÙˆØ§Ù‚Ø¹ÛŒ Ø¢Ù† Ø¯Ø± Ù…Ø±Ø­Ù„Ù‡ ØªØ¯ÙˆÛŒÙ† Ø§Ù†Ø¬Ø§Ù… Ù…ÛŒâ€ŒØ´ÙˆØ¯.'),
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
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ù…ØªÙˆØ¬Ù‡ Ø´Ø¯Ù…'))],
      ),
    );
  }

  Widget settingsPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('ØªÙ†Ø¸ÛŒÙ…Ø§Øª', subtitle: 'Ø´Ø®ØµÛŒâ€ŒØ³Ø§Ø²ÛŒ ØªØ¬Ø±Ø¨Ù‡ Ø§Ø³ØªÙØ§Ø¯Ù‡ Ø§Ø² AVHA'),
          card(child: Row(children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(color: gold.withOpacity(.15), shape: BoxShape.circle),
              child: const Icon(Icons.person_outline, color: gold, size: 30),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ú©Ø§Ø±Ø¨Ø± AVHA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              Text('Ø¨Ø¯ÙˆÙ† Ù†ÛŒØ§Ø² Ø¨Ù‡ Ø­Ø³Ø§Ø¨ Ú©Ø§Ø±Ø¨Ø±ÛŒ', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            const Icon(Icons.check_circle, color: Colors.green),
          ])),
          const SizedBox(height: 12),
          settingsGroup('Ø¸Ø§Ù‡Ø± Ø¨Ø±Ù†Ø§Ù…Ù‡', Icons.palette_outlined, [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ø­Ø§Ù„Øª ØªØ§Ø±ÛŒÚ©'),
              value: darkTheme,
              activeColor: gold,
              onChanged: (v) => setState(() => darkTheme = v),
            ),
            dropdownSetting('Ø±Ù†Ú¯ Ø±Ø§Ø¨Ø· Ú©Ø§Ø±Ø¨Ø±ÛŒ', accentChoice, ['Ø·Ù„Ø§ÛŒÛŒ', 'Ø¢Ø¨ÛŒ', 'Ø¨Ù†ÙØ´'],
                (v) => setState(() => accentChoice = v)),
            dropdownSetting('Ø²Ø¨Ø§Ù† Ø¨Ø±Ù†Ø§Ù…Ù‡', language, ['ÙØ§Ø±Ø³ÛŒ', 'English'],
                (v) => setState(() => language = v)),
          ]),
          settingsGroup('ØªÙ†Ø¸ÛŒÙ…Ø§Øª ØªØ¯ÙˆÛŒÙ†', Icons.movie_outlined, [
            dropdownSetting('Ú©ÛŒÙÛŒØª Ù¾ÛŒØ´â€ŒÙØ±Ø¶ Ø®Ø±ÙˆØ¬ÛŒ', outputQuality, ['720p', '1080p', '2K', '4K'],
                (v) => setState(() => outputQuality = v)),
            dropdownSetting('Ù†Ø³Ø¨Øª ØªØµÙˆÛŒØ± Ù¾ÛŒØ´â€ŒÙØ±Ø¶', aspectRatio, ['9:16', '16:9', '1:1', '4:5'],
                (v) => setState(() => aspectRatio = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ø°Ø®ÛŒØ±Ù‡ Ø®ÙˆØ¯Ú©Ø§Ø± Ù¾Ø±ÙˆÚ˜Ù‡â€ŒÙ‡Ø§'),
              subtitle: const Text('ÙØ¹Ø§Ù„â€ŒØ³Ø§Ø²ÛŒ Ø°Ø®ÛŒØ±Ù‡ Ø®ÙˆØ¯Ú©Ø§Ø± Ø¯Ø± Ù†Ø³Ø®Ù‡ Ø¢ÛŒÙ†Ø¯Ù‡'),
              value: autoSave,
              activeColor: gold,
              onChanged: (v) => setState(() => autoSave = v),
            ),
          ]),
          settingsGroup('Ù‡ÙˆØ´ Ù…ØµÙ†ÙˆØ¹ÛŒ', Icons.psychology_outlined, [
            dropdownSetting('Ø²Ø¨Ø§Ù† ØªÙˆÙ„ÛŒØ¯ Ù…Ø­ØªÙˆØ§', language, ['ÙØ§Ø±Ø³ÛŒ', 'English'],
                (v) => setState(() => language = v)),
            dropdownSetting('Ù„Ø­Ù† Ù…ØªÙ†', aiTone, ['Ø¯ÙˆØ³ØªØ§Ù†Ù‡', 'Ø±Ø³Ù…ÛŒ', 'ØªØ¨Ù„ÛŒØºØ§ØªÛŒ', 'ØµÙ…ÛŒÙ…ÛŒ'],
                (v) => setState(() => aiTone = v)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ØµØ¯Ø§ÛŒ Ú¯ÙˆÛŒÙ†Ø¯Ù‡'),
              subtitle: Text(selectedVoice == 'fa-IR-FaridNeural' ? 'ØµØ¯Ø§ÛŒ Ù…Ø±Ø¯' : 'ØµØ¯Ø§ÛŒ Ø²Ù†'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => setState(() => selectedVoice = selectedVoice == 'fa-IR-FaridNeural'
                  ? 'fa-IR-DilaraNeural' : 'fa-IR-FaridNeural'),
            ),
          ]),
          settingsGroup('Ø§Ø¹Ù„Ø§Ù†â€ŒÙ‡Ø§', Icons.notifications_none, [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ø¯Ø±ÛŒØ§ÙØª Ø§Ø¹Ù„Ø§Ù†â€ŒÙ‡Ø§'),
              value: notifications,
              activeColor: gold,
              onChanged: (v) => setState(() => notifications = v),
            ),
          ]),
          settingsGroup('ÙØ¶Ø§ÛŒ Ø°Ø®ÛŒØ±Ù‡â€ŒØ³Ø§Ø²ÛŒ', Icons.storage_outlined, [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Ù…Ø¯ÛŒØ±ÛŒØª ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ Ù…ÙˆÙ‚Øª'),
              subtitle: Text('Ù¾Ø§Ú©â€ŒØ³Ø§Ø²ÛŒ Ùˆ Ù…Ø¯ÛŒØ±ÛŒØª ÙØ¶Ø§ÛŒ Ø°Ø®ÛŒØ±Ù‡â€ŒØ³Ø§Ø²ÛŒ Ø¯Ø± Ù…Ø±Ø­Ù„Ù‡ Ø¨Ø¹Ø¯ Ø§Ø¶Ø§ÙÙ‡ Ù…ÛŒâ€ŒØ´ÙˆØ¯.'),
            ),
          ]),
          settingsGroup('Ø¯Ø±Ø¨Ø§Ø±Ù‡ AVHA', Icons.info_outline, [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('AVHA â€“ AI Content Studio'),
              subtitle: Text('Ø®Ù„Ù‚ Ú©Ù†ØŒ Ù…ØªÙØ§ÙˆØª Ø¨Ø§Ø´.'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Ø§Ø¨ÙˆØ§Ù„ÙØ¶Ù„ Ù‡Ø§Ø´Ù…ÛŒ'),
              subtitle: Text('Founder & Creator | Ø§ÛŒØ¯Ù‡â€ŒÙ¾Ø±Ø¯Ø§Ø² Ùˆ Ø³Ø§Ø²Ù†Ø¯Ù‡ AVHA'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.camera_alt_outlined, color: gold),
              title: const Text('Ø§ÛŒÙ†Ø³ØªØ§Ú¯Ø±Ø§Ù… Ø³Ø§Ø²Ù†Ø¯Ù‡'),
              subtitle: const Text('@aboalfazl7852'),
              onTap: () => showInfo('Ø§ÛŒÙ†Ø³ØªØ§Ú¯Ø±Ø§Ù… Ø³Ø§Ø²Ù†Ø¯Ù‡', 'https://www.instagram.com/aboalfazl7852/'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Ù†Ø³Ø®Ù‡ Ø¨Ø±Ù†Ø§Ù…Ù‡'),
              subtitle: Text('Ù†Ø³Ø®Ù‡ Ø¢Ø²Ù…Ø§ÛŒØ´ÛŒ ØªÙˆØ³Ø¹Ù‡'),
            ),
          ]),
          const SizedBox(height: 12),
          const Center(child: Text('Ø­Ø³Ø§Ø¨ Ú©Ø§Ø±Ø¨Ø±ÛŒØŒ Ú©Ø¯ ÙˆØ±ÙˆØ¯ Ùˆ Ø±Ù…Ø² Ø¹Ø¨ÙˆØ± ÙØ¹Ù„Ø§Ù‹ Ø¯Ø± Ø¨Ø±Ù†Ø§Ù…Ù‡ ÙˆØ¬ÙˆØ¯ Ù†Ø¯Ø§Ø±Ø¯.',
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
    final pages = [
      inWorkspace ? workspaceHomePage() : homePage(),
      captionsPage(),
      voicePage(),
      aiPage(),
      settingsPage(),
      editorPage(),
      projectsPage(),
      exportPage(),
    ];
    final visiblePages = inWorkspace ? pages : [homePage()];
    final safeTab = tab.clamp(0, pages.length - 1) as int;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Stack(children: [
            IndexedStack(index: inWorkspace ? safeTab : 0, children: visiblePages),
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
        bottomNavigationBar: inWorkspace ? NavigationBar(
          backgroundColor: panel,
          indicatorColor: gold.withOpacity(.18),
          selectedIndex: tab <= 4 ? tab : 0,
          onDestinationSelected: (i) => go(i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: gold), label: 'Ø®Ø§Ù†Ù‡'),
            NavigationDestination(icon: Icon(Icons.subtitles_outlined), selectedIcon: Icon(Icons.subtitles, color: gold), label: 'Ø²ÛŒØ±Ù†ÙˆÛŒØ³'),
            NavigationDestination(icon: Icon(Icons.record_voice_over_outlined), selectedIcon: Icon(Icons.record_voice_over, color: gold), label: 'ØµØ¯Ø§'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome, color: gold), label: 'Ù‡ÙˆØ´ Ù…ØµÙ†ÙˆØ¹ÛŒ'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings, color: gold), label: 'ØªÙ†Ø¸ÛŒÙ…Ø§Øª'),
          ],
        ) : null,
      ),
    );
  }
}

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
  String workspace = 'Ø´Ø®ØµÛŒ';
  bool workspaceSelected = false;

  File? videoFile;
  File? activeProjectClip;
  Timer? projectAutosaveTimer;
  bool projectSaving = false;
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
  List<File> clipsLibrary = [];
  String clipsFilter = 'Ù‡Ù…Ù‡';

  // Preserve the original on-device folder names for existing user files.
  String _legacyWorkspaceFolder(String value) => String.fromCharCodes(
        value == 'Ú©Ø§Ø±ÛŒ'
            ? [218, 169, 216, 167, 216, 177, 219, 338]
            : [216, 180, 216, 174, 216, 181, 219, 338],
      );

  String _normalizeSavedSubtitleOption(String value, String kind) {
    final legacy = <String, Map<String, String>>{
      'color': {
        String.fromCharCodes([216, 179, 217, 129, 219, 338, 216, 175]): 'Ø³ÙÛŒØ¯',
        String.fromCharCodes([216, 183, 217, 8222, 216, 167, 219, 338, 219, 338]): 'Ø·Ù„Ø§ÛŒÛŒ',
        String.fromCharCodes([216, 178, 216, 177, 216, 175]): 'Ø²Ø±Ø¯',
        String.fromCharCodes([216, 162, 216, 168, 219, 338]): 'Ø¢Ø¨ÛŒ',
        String.fromCharCodes([217, 8230, 216, 180, 218, 169, 219, 338]): 'Ù…Ø´Ú©ÛŒ',
      },
      'background': {
        String.fromCharCodes([217, 8224, 219, 338, 217, 8230, 217, 8225, 226, 8364, 338, 216, 180, 217, 129, 216, 167, 217, 129]): 'Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù',
        String.fromCharCodes([217, 190, 216, 177, 216, 177, 217, 8224, 218, 175]): 'Ù¾Ø±Ø±Ù†Ú¯',
        String.fromCharCodes([216, 168, 216, 175, 217, 710, 217, 8224, 32, 217, 190, 216, 179, 226, 8364, 338, 216, 178, 217, 8230, 219, 338, 217, 8224, 217, 8225]): 'Ø¨Ø¯ÙˆÙ† Ù¾Ø³â€ŒØ²Ù…ÛŒÙ†Ù‡',
      },
      'animation': {
        String.fromCharCodes([218, 169, 217, 8222, 217, 8230, 217, 8225, 226, 8364, 338, 216, 168, 217, 8225, 226, 8364, 338, 218, 169, 217, 8222, 217, 8230, 217, 8225]): 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡',
      },
      'font': {
        String.fromCharCodes([217, 190, 219, 338, 216, 180, 226, 8364, 338, 217, 129, 216, 177, 216, 182]): 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶',
      },
    };
    return legacy[kind]?[value] ?? value;
  }
  String selectedVoice = 'fa-IR-FaridNeural';

  final voiceController = TextEditingController();
  final transcriptController = TextEditingController();

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
    transcriptController.dispose();
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
        transcriptController.clear();
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
        transcriptController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        setState(() {
          transcript = text;
          transcriptApproved = false;
          status = 'Ù…ØªÙ† ÙˆÛŒØ¯Ø¦Ùˆ Ø¨Ø§ Ù…ÙˆÙÙ‚ÛŒØª Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ø´Ø¯.';
          scheduleProjectAutosave();
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
          scheduleProjectAutosave();
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
        final audioDir = await voiceDirectory();
        await audioDir.create(recursive: true);
        final file = File(
          '${audioDir.path}${Platform.pathSeparator}AVHA_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await loadVoiceLibrary();
        setState(() {
          voiceFilePath = file.path;
          voiceResult = 'ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ Ø¯Ø± Ù¾ÙˆØ´Ù‡ ÙØ¶Ø§ÛŒ ${workspace == 'Ú©Ø§Ø±ÛŒ' ? 'Ú©Ø§Ø±ÛŒ' : 'Ø´Ø®ØµÛŒ'} Ø°Ø®ÛŒØ±Ù‡ Ø´Ø¯.';
          status = 'ØªÙˆÙ„ÛŒØ¯ ØµØ¯Ø§ Ø¨Ø§ Ù…ÙˆÙÙ‚ÛŒØª Ø§Ù†Ø¬Ø§Ù… Ø´Ø¯.';
        });
      }, 'Ø¯Ø± Ø­Ø§Ù„ ØªÙˆÙ„ÛŒØ¯ ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ...');

  Future<Directory> voiceDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(
      '${appDir.path}${Platform.pathSeparator}AVHA'
      '${Platform.pathSeparator}Audio${Platform.pathSeparator}${_legacyWorkspaceFolder(workspace)}',
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

  Future<Directory> clipsRootDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}${Platform.pathSeparator}AVHA${Platform.pathSeparator}Clips');
  }

  Future<void> loadClipsLibrary() async {
    try {
      final root = await clipsRootDirectory();
      for (final name in [_legacyWorkspaceFolder('Ø´Ø®ØµÛŒ'), _legacyWorkspaceFolder('Ú©Ø§Ø±ÛŒ')]) {
        await Directory('${root.path}${Platform.pathSeparator}$name').create(recursive: true);
      }
      final files = root.listSync(recursive: true).whereType<File>().where((f) {
        final ext = f.path.toLowerCase();
        return ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.m4v') || ext.endsWith('.mkv');
      }).toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (mounted) setState(() => clipsLibrary = files);
    } catch (e) {
      if (mounted) setState(() => status = 'Ø®Ø·Ø§ Ø¯Ø± Ø¨Ø§Ø±Ú¯Ø°Ø§Ø±ÛŒ Ú©Ù„ÛŒÙ¾â€ŒÙ‡Ø§: $e');
    }
  }

  String clipWorkspace(File file) {
    final folder = file.parent.path.split(Platform.pathSeparator).last;
    if (folder == _legacyWorkspaceFolder('Ú©Ø§Ø±ÛŒ') || folder == 'Ú©Ø§Ø±ÛŒ') return 'Ú©Ø§Ø±ÛŒ';
    if (folder == _legacyWorkspaceFolder('Ø´Ø®ØµÛŒ') || folder == 'Ø´Ø®ØµÛŒ') return 'Ø´Ø®ØµÛŒ';
    return folder;
  }

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
        setState(() => status = 'Ù¾Ø±ÙˆÚ˜Ù‡ Ùˆ ØªÙ†Ø¸ÛŒÙ…Ø§Øª ØªØ¯ÙˆÛŒÙ† Ø°Ø®ÛŒØ±Ù‡ Ø´Ø¯.');
        showInfo('Ù¾Ø±ÙˆÚ˜Ù‡ Ø°Ø®ÛŒØ±Ù‡ Ø´Ø¯', 'ÙˆÛŒØ¯Ø¦Ùˆ Ùˆ ØªÙ†Ø¸ÛŒÙ…Ø§Øª Ø¢Ù† Ø¯Ø± ÙØ¶Ø§ÛŒ $workspace Ø°Ø®ÛŒØ±Ù‡ Ø´Ø¯Ù†Ø¯. Ù‡Ø± ØªØºÛŒÛŒØ±ÛŒ Ú©Ù‡ Ø§Ø² Ø§ÛŒÙ† Ø¨Ù‡ Ø¨Ø¹Ø¯ Ø§Ù†Ø¬Ø§Ù… Ø¨Ø¯Ù‡ÛŒØŒ Ø¨Ù‡â€ŒØµÙˆØ±Øª Ø®ÙˆØ¯Ú©Ø§Ø± Ø°Ø®ÛŒØ±Ù‡ Ù…ÛŒâ€ŒØ´ÙˆØ¯.');
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Ø°Ø®ÛŒØ±Ù‡ ØªØºÛŒÛŒØ±Ø§Øª Ù¾Ø±ÙˆÚ˜Ù‡ Ù†Ø§Ù…ÙˆÙÙ‚ Ø¨ÙˆØ¯: $e');
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
        transcriptController.clear();
        if (mounted) setState(() {
          transcript = '';
          transcriptApproved = false;
          ideas = caption = topic = hashtags = '';
          subtitleFontSize = 22;
          subtitleVerticalPosition = 0.82;
          subtitleColorChoice = 'Ø³ÙÛŒØ¯';
          subtitleBackgroundChoice = 'Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù';
          subtitleAnimation = 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡';
          subtitleFontFamily = 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶';
        });
        return;
      }
      final raw = jsonDecode(await sidecar.readAsString());
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      if (!mounted) return;
      final restoredTranscript = (data['transcript'] ?? '').toString();
      transcriptController.value = TextEditingValue(
        text: restoredTranscript,
        selection: TextSelection.collapsed(offset: restoredTranscript.length),
      );
      setState(() {
        transcript = restoredTranscript;
        transcriptApproved = data['transcriptApproved'] == true;
        subtitleFontSize = (data['subtitleFontSize'] as num?)?.toDouble() ?? 22;
        subtitleVerticalPosition = (data['subtitleVerticalPosition'] as num?)?.toDouble() ?? 0.82;
        subtitleColorChoice = _normalizeSavedSubtitleOption(
          (data['subtitleColorChoice'] ?? 'Ø³ÙÛŒØ¯').toString(), 'color');
        if (!['Ø³ÙÛŒØ¯', 'Ø·Ù„Ø§ÛŒÛŒ', 'Ø²Ø±Ø¯', 'Ø¢Ø¨ÛŒ', 'Ù…Ø´Ú©ÛŒ'].contains(subtitleColorChoice)) {
          subtitleColorChoice = 'Ø³ÙÛŒØ¯';
        }
        subtitleBackgroundChoice = _normalizeSavedSubtitleOption(
          (data['subtitleBackgroundChoice'] ?? 'Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù').toString(), 'background');
        if (!['Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù', 'Ù¾Ø±Ø±Ù†Ú¯', 'Ø¨Ø¯ÙˆÙ† Ù¾Ø³â€ŒØ²Ù…ÛŒÙ†Ù‡'].contains(subtitleBackgroundChoice)) {
          subtitleBackgroundChoice = 'Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù';
        }
        subtitleAnimation = _normalizeSavedSubtitleOption(
          (data['subtitleAnimation'] ?? 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡').toString(), 'animation');
        if (!['ÛŒÚ©â€ŒØ¬Ø§', 'Ø­Ø±Ùâ€ŒØ¨Ù‡â€ŒØ­Ø±Ù', 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡', 'Ø¨Ø±Ø¬Ø³ØªÙ‡â€ŒØ³Ø§Ø²ÛŒ Ú©Ù„Ù…Ù‡ ÙØ¹Ø§Ù„'].contains(subtitleAnimation)) {
          subtitleAnimation = 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡';
        }
        subtitleFontFamily = _normalizeSavedSubtitleOption(
          (data['subtitleFontFamily'] ?? 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶').toString(), 'font');
        if (!['Ù¾ÛŒØ´â€ŒÙØ±Ø¶', 'serif', 'monospace'].contains(subtitleFontFamily)) {
          subtitleFontFamily = 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶';
        }
        ideas = (data['ideas'] ?? '').toString();
        caption = (data['caption'] ?? '').toString();
        topic = (data['topic'] ?? '').toString();
        hashtags = (data['hashtags'] ?? '').toString();
        status = 'Ù¾Ø±ÙˆÚ˜Ù‡ Ù‚Ø¨Ù„ÛŒ Ù‡Ù…Ø±Ø§Ù‡ Ø¨Ø§ ØªÙ†Ø¸ÛŒÙ…Ø§ØªØ´ Ø¨Ø§Ø²ÛŒØ§Ø¨ÛŒ Ø´Ø¯Ø› Ù…ÛŒâ€ŒØªÙˆØ§Ù†ÛŒ ØªØ¯ÙˆÛŒÙ† Ø±Ø§ Ø§Ø¯Ø§Ù…Ù‡ Ø¨Ø¯Ù‡ÛŒ.';
      });
      final savedPosition = (data['videoPositionMs'] as num?)?.toInt() ?? 0;
      final duration = videoController?.value.duration.inMilliseconds ?? 0;
      if (savedPosition > 0 && duration > 0) {
        await videoController?.seekTo(Duration(milliseconds: savedPosition.clamp(0, duration).toInt()));
      }
    } catch (e) {
      if (mounted) setState(() => status = 'ÙØ§ÛŒÙ„ ÙˆÛŒØ¯Ø¦Ùˆ Ø¨Ø§Ø² Ø´Ø¯ØŒ Ø§Ù…Ø§ Ø¨Ø§Ø²ÛŒØ§Ø¨ÛŒ ØªÙ†Ø¸ÛŒÙ…Ø§Øª Ù¾Ø±ÙˆÚ˜Ù‡ Ø§Ù†Ø¬Ø§Ù… Ù†Ø´Ø¯: $e');
    }
  }

  Future<void> saveCurrentClipToLibrary() async {
    if (videoFile == null) {
      showInfo('Ø°Ø®ÛŒØ±Ù‡ Ù¾Ø±ÙˆÚ˜Ù‡', 'Ø§Ø¨ØªØ¯Ø§ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†.');
      return;
    }
    try {
      await _flushProjectAutosave();
      final root = await clipsRootDirectory();
      final dir = Directory('${root.path}${Platform.pathSeparator}${_legacyWorkspaceFolder(workspace)}');
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
      if (mounted) setState(() => status = 'Ø°Ø®ÛŒØ±Ù‡ Ù¾Ø±ÙˆÚ˜Ù‡ Ù†Ø§Ù…ÙˆÙÙ‚ Ø¨ÙˆØ¯: $e');
    }
  }

  Future<void> renameClip(File file) async {
    final controller = TextEditingController(text: file.uri.pathSegments.last);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: panel,
      title: const Text('ØªØºÛŒÛŒØ± Ù†Ø§Ù… Ú©Ù„ÛŒÙ¾'),
      content: TextField(controller: controller, textDirection: TextDirection.rtl, decoration: const InputDecoration(hintText: 'Ù†Ø§Ù… ÙØ§ÛŒÙ„')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ø§Ù†ØµØ±Ø§Ù')), TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Ø°Ø®ÛŒØ±Ù‡'))],
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
      if (mounted) showInfo('Ø®Ø·Ø§', 'ØªØºÛŒÛŒØ± Ù†Ø§Ù… Ø§Ù†Ø¬Ø§Ù… Ù†Ø´Ø¯: $e');
    }
  }

  Future<void> deleteClip(File file) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: panel, title: const Text('Ø­Ø°Ù Ú©Ù„ÛŒÙ¾'), content: const Text('Ø§ÛŒÙ† ÙØ§ÛŒÙ„ Ø§Ø² Ú©ØªØ§Ø¨Ø®Ø§Ù†Ù‡ AVHA Ø­Ø°Ù Ø´ÙˆØ¯ØŸ'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ø§Ù†ØµØ±Ø§Ù')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ø­Ø°Ù', style: TextStyle(color: Colors.redAccent)))],
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
          transcriptController.clear();
          ideas = caption = topic = hashtags = '';
          subtitleFontSize = 22;
          subtitleVerticalPosition = 0.82;
          subtitleColorChoice = 'Ø³ÙÛŒØ¯';
          subtitleBackgroundChoice = 'Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù';
          subtitleAnimation = 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡';
          subtitleFontFamily = 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶';
          status = 'Ù¾Ø±ÙˆÚ˜Ù‡ Ø­Ø°Ù Ø´Ø¯.';
        });
      }
      await loadClipsLibrary();
    } catch (e) {
      if (mounted) showInfo('Ø®Ø·Ø§', 'Ø­Ø°Ù Ú©Ù„ÛŒÙ¾ Ø§Ù†Ø¬Ø§Ù… Ù†Ø´Ø¯: $e');
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
      transcriptController.clear();
      setState(() {
        videoFile = file;
        activeProjectClip = file;
        videoController = controller;
        transcript = '';
        transcriptApproved = false;
        ideas = caption = topic = hashtags = '';
        workspace = clipWorkspace(file);
        workspaceSelected = true;
        clipsFilter = workspace;
        tab = 5;
      });
      await _restoreProjectData(file);
      await loadVoiceLibrary();
    } catch (e) {
      if (mounted) showInfo('Ø®Ø·Ø§ Ø¯Ø± Ù¾Ø®Ø´', '$e');
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
        onTap: () async {
          if (busy) return;
          setState(() {
            workspace = title == 'ÙØ¶Ø§ÛŒ Ú©Ø§Ø±ÛŒ' ? 'Ú©Ø§Ø±ÛŒ' : 'Ø´Ø®ØµÛŒ';
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
                Text('ÙˆØ±ÙˆØ¯ Ø¨Ù‡ ÙØ¶Ø§', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
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
      transcriptController.clear();
      ideas = '';
      caption = '';
      topic = '';
      hashtags = '';
      voiceResult = '';
      voiceFilePath = '';
      voiceLibrary = [];
      clipsFilter = workspace;
      status = 'ÙØ¶Ø§ÛŒ Ø¬Ø¯ÛŒØ¯ Ø±Ø§ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯.';
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
                const Center(child: Text('Ø®Ù„Ù‚ Ú©Ù†ØŒ Ù…ØªÙØ§ÙˆØª Ø¨Ø§Ø´.', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600,
                ))),
                const SizedBox(height: 10),
                const Center(child: Text('Ø¨Ø±Ø§ÛŒ Ø´Ø±ÙˆØ¹ØŒ Ù†ÙˆØ¹ Ù¾Ø±ÙˆÚ˜Ù‡ Ø®ÙˆØ¯ Ø±Ø§ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))),
                const SizedBox(height: 30),
                modeCard('ÙØ¶Ø§ÛŒ Ø´Ø®ØµÛŒ', 'Ø¨Ø±Ø§ÛŒ ÙˆÙ„Ø§Ú¯ØŒ Ø³ÙØ± Ùˆ Ù…Ø­ØªÙˆØ§ÛŒ Ø´Ø¨Ú©Ù‡â€ŒÙ‡Ø§ÛŒ Ø§Ø¬ØªÙ…Ø§Ø¹ÛŒ',
                    Icons.person_outline, blue),
                const SizedBox(height: 14),
                modeCard('ÙØ¶Ø§ÛŒ Ú©Ø§Ø±ÛŒ', 'Ø¨Ø±Ø§ÛŒ Ù¾Ø±ÙˆÚ˜Ù‡â€ŒÙ‡Ø§ØŒ Ø¨Ø±Ù†Ø¯ Ùˆ Ù…Ø­ØªÙˆØ§ÛŒ Ú©Ø³Ø¨â€ŒÙˆÚ©Ø§Ø±',
                    Icons.business_center_outlined, gold),
                const SizedBox(height: 22),
                const Center(child: Text('ÙØ¶Ø§Ù‡Ø§ Ùˆ ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ Ø°Ø®ÛŒØ±Ù‡â€ŒØ´Ø¯Ù‡ Ø§Ø² ÛŒÚ©Ø¯ÛŒÚ¯Ø± Ø¬Ø¯Ø§ Ù‡Ø³ØªÙ†Ø¯.',
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
                decoration: BoxDecoration(color: workspace == 'Ú©Ø§Ø±ÛŒ' ? gold.withOpacity(.14) : blue.withOpacity(.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: workspace == 'Ú©Ø§Ø±ÛŒ' ? gold : blue)),
                child: Text(workspace == 'Ú©Ø§Ø±ÛŒ' ? 'ÙØ¶Ø§ÛŒ Ú©Ø§Ø±ÛŒ' : 'ÙØ¶Ø§ÛŒ Ø´Ø®ØµÛŒ',
                  style: TextStyle(color: workspace == 'Ú©Ø§Ø±ÛŒ' ? gold : blue, fontSize: 11)),
              ),
              IconButton(
                tooltip: 'ØªØºÛŒÛŒØ± ÙØ¶Ø§',
                onPressed: changeWorkspace,
                icon: const Icon(Icons.swap_horiz, color: gold, size: 27),
              ),
              IconButton(
                tooltip: 'ØªÙ†Ø¸ÛŒÙ…Ø§Øª',
                onPressed: () => go(4),
                icon: const Icon(Icons.settings_outlined, color: gold, size: 27),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Ø³Ù„Ø§Ù…ØŒ Ú©Ø§Ø±Ø¨Ø± Ø¹Ø²ÛŒØ² ðŸ‘‹', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          const Text('Ø¨Ù‡ AVHA Ø®ÙˆØ´ Ø¢Ù…Ø¯ÛŒØ› Ø¢Ù…Ø§Ø¯Ù‡â€ŒØ§ÛŒ Ú†ÛŒØ²ÛŒ Ù…ØªÙØ§ÙˆØª Ø®Ù„Ù‚ Ú©Ù†ÛŒØŸ',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => go(6),
            icon: const Icon(Icons.folder_open, color: gold),
            label: const Text('Ú©Ù„ÛŒÙ¾â€ŒÙ‡Ø§ÛŒ Ù…Ù†'),
          ),
          const SizedBox(height: 22),
          const Text('Ø´Ø±ÙˆØ¹ Ø³Ø±ÛŒØ¹', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          card(child: Column(children: [
            Row(children: [
              const Icon(Icons.video_library_outlined, color: gold, size: 30),
              const SizedBox(width: 10),
              const Expanded(child: Text('ÙˆÛŒØ¯Ø¦ÙˆÛŒ Ø®ÙˆØ¯ Ø±Ø§ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†')),
              TextButton(onPressed: busy ? null : pickVideo, child: const Text('Ø§Ù†ØªØ®Ø§Ø¨ ÙˆÛŒØ¯Ø¦Ùˆ')),
            ]),
            if (videoFile != null) ...[
              const SizedBox(height: 10),
              videoPreview(),
              const SizedBox(height: 7),
              Text(videoFile!.path.split(Platform.pathSeparator).last,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 10),
              goldButton('Ø±ÙØªÙ† Ø¨Ù‡ Ù…Ø­ÛŒØ· ØªØ¯ÙˆÛŒÙ†', () => go(5), icon: Icons.movie_edit),
            ],
          ])),
          const SizedBox(height: 18),
          const Text('Ø§Ø¨Ø²Ø§Ø±Ù‡Ø§ÛŒ Ù‡ÙˆØ´Ù…Ù†Ø¯', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          featureRow(Icons.subtitles, 'Ø²ÛŒØ±Ù†ÙˆÛŒØ³ Ù‡ÙˆØ´Ù…Ù†Ø¯', 'ØªØ¨Ø¯ÛŒÙ„ Ú¯ÙØªØ§Ø± ÙˆÛŒØ¯Ø¦Ùˆ Ø¨Ù‡ Ù…ØªÙ†', () => go(1), blue),
          featureRow(Icons.graphic_eq, 'Ù…ØªÙ† Ø¨Ù‡ Ú¯ÙØªØ§Ø±', 'ØªÙˆÙ„ÛŒØ¯ ØµØ¯Ø§ÛŒ ÙØ§Ø±Ø³ÛŒ', () => go(2), purple),
          featureRow(Icons.lightbulb_outline, 'Ø§ÛŒØ¯Ù‡ Ùˆ Ú©Ù¾Ø´Ù†', 'Ø¹Ù†ÙˆØ§Ù†ØŒ Ø³Ù†Ø§Ø±ÛŒÙˆØŒ Ú©Ù¾Ø´Ù† Ùˆ Ù‡Ø´ØªÚ¯', () => go(3), gold),
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
          sectionTitle('Ø§Ø³ØªÙˆØ¯ÛŒÙˆÛŒ Ø²ÛŒØ±Ù†ÙˆÛŒØ³', subtitle: 'Ø§ÙˆÙ„ Ù…ØªÙ† Ø±Ø§ Ø§ØµÙ„Ø§Ø­ Ùˆ ØªØ£ÛŒÛŒØ¯ Ú©Ù†Ø› Ø³Ù¾Ø³ Ø¸Ø§Ù‡Ø± Ø²ÛŒØ±Ù†ÙˆÛŒØ³ Ø±Ø§ ØªÙ†Ø¸ÛŒÙ… Ú©Ù†.'),
          card(child: Column(children: [
            goldButton('Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ù…ØªÙ† Ø§Ø² ÙˆÛŒØ¯Ø¦Ùˆ', videoFile == null ? null : transcribe, icon: Icons.subtitles),
            const SizedBox(height: 12),
            TextFormField(
              controller: transcriptController,
              maxLines: 8,
              onChanged: (v) => setState(() {
                transcript = v;
                transcriptApproved = false;
                scheduleProjectAutosave();
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
                scheduleProjectAutosave();
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
              onChanged: (v) => setState(() { subtitleFontSize = v; scheduleProjectAutosave(); }),
            ),
            DropdownButtonFormField<String>(
              value: subtitleFontFamily,
              decoration: const InputDecoration(labelText: 'Ù†ÙˆØ¹ ÙÙˆÙ†Øª'),
              items: const [
                DropdownMenuItem(value: 'Ù¾ÛŒØ´â€ŒÙØ±Ø¶', child: Text('Ù¾ÛŒØ´â€ŒÙØ±Ø¶')),
                DropdownMenuItem(value: 'serif', child: Text('Ø³Ø±ÛŒÙ')),
                DropdownMenuItem(value: 'monospace', child: Text('ØªÚ©â€ŒÙØ§ØµÙ„Ù‡')),
              ],
              onChanged: (v) { if (v != null) setState(() { subtitleFontFamily = v; scheduleProjectAutosave(); }); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleColorChoice,
              decoration: const InputDecoration(labelText: 'Ø±Ù†Ú¯ Ù†ÙˆØ´ØªÙ‡'),
              items: ['Ø³ÙÛŒØ¯', 'Ø·Ù„Ø§ÛŒÛŒ', 'Ø²Ø±Ø¯', 'Ø¢Ø¨ÛŒ', 'Ù…Ø´Ú©ÛŒ']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() { subtitleColorChoice = v; scheduleProjectAutosave(); }); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleBackgroundChoice,
              decoration: const InputDecoration(labelText: 'Ù¾Ø³â€ŒØ²Ù…ÛŒÙ†Ù‡ Ø²ÛŒØ±Ù†ÙˆÛŒØ³'),
              items: ['Ù†ÛŒÙ…Ù‡â€ŒØ´ÙØ§Ù', 'Ù¾Ø±Ø±Ù†Ú¯', 'Ø¨Ø¯ÙˆÙ† Ù¾Ø³â€ŒØ²Ù…ÛŒÙ†Ù‡']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() { subtitleBackgroundChoice = v; scheduleProjectAutosave(); }); },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: subtitleAnimation,
              decoration: const InputDecoration(labelText: 'Ù†Ø­ÙˆÙ‡ Ù†Ù…Ø§ÛŒØ´ Ù…ØªÙ†'),
              items: ['ÛŒÚ©â€ŒØ¬Ø§', 'Ø­Ø±Ùâ€ŒØ¨Ù‡â€ŒØ­Ø±Ù', 'Ú©Ù„Ù…Ù‡â€ŒØ¨Ù‡â€ŒÚ©Ù„Ù…Ù‡', 'Ø¨Ø±Ø¬Ø³ØªÙ‡â€ŒØ³Ø§Ø²ÛŒ Ú©Ù„Ù…Ù‡ ÙØ¹Ø§Ù„']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) { if (v != null) setState(() { subtitleAnimation = v; scheduleProjectAutosave(); }); },
            ),
            const SizedBox(height: 10),
            Text('Ù…ÙˆÙ‚Ø¹ÛŒØª Ø¹Ù…ÙˆØ¯ÛŒ: ${(subtitleVerticalPosition * 100).round()}%',
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

  Widget projectsPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          sectionTitle('Ú©Ù„ÛŒÙ¾â€ŒÙ‡Ø§ÛŒ Ù…Ù†', subtitle: 'ÙØ§ÛŒÙ„â€ŒÙ‡Ø§ÛŒ Ø°Ø®ÛŒØ±Ù‡â€ŒØ´Ø¯Ù‡ Ø¯Ø± ÙØ¶Ø§ÛŒ ${workspace == 'Ú©Ø§Ø±ÛŒ' ? 'Ú©Ø§Ø±ÛŒ' : 'Ø´Ø®ØµÛŒ'}.'),
          if (clipsLibrary.where((f) => clipWorkspace(f) == workspace).isEmpty)
            card(child: const Column(children: [
              Icon(Icons.video_library_outlined, color: gold, size: 42),
              SizedBox(height: 8),
              Text('Ù‡Ù†ÙˆØ² Ú©Ù„ÛŒÙ¾ÛŒ Ø¯Ø± Ø§ÛŒÙ† ÙØ¶Ø§ Ø°Ø®ÛŒØ±Ù‡ Ù†Ø´Ø¯Ù‡ Ø§Ø³Øª.'),
              SizedBox(height: 6),
              Text('Ø§Ø² Ù…Ø­ÛŒØ· ØªØ¯ÙˆÛŒÙ†ØŒ Ú¯Ø²ÛŒÙ†Ù‡ Â«Ø°Ø®ÛŒØ±Ù‡ Ø¯Ø± Ú©Ù„ÛŒÙ¾â€ŒÙ‡Ø§ÛŒ Ù…Ù†Â» Ø±Ø§ Ø¨Ø²Ù†.',
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
                  Text('${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} Ù…Ú¯Ø§Ø¨Ø§ÛŒØª',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ])),
                IconButton(tooltip: 'Ù¾Ø®Ø´ Ùˆ ØªØ¯ÙˆÛŒÙ†', onPressed: () => openClip(file),
                  icon: const Icon(Icons.play_circle_outline, color: gold)),
                PopupMenuButton<String>(
                  onSelected: (v) { if (v == 'rename') renameClip(file); if (v == 'delete') deleteClip(file); },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('ØªØºÛŒÛŒØ± Ù†Ø§Ù…')),
                    PopupMenuItem(value: 'delete', child: Text('Ø­Ø°Ù')),
                  ],
                ),
              ])),
            )),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: loadClipsLibrary,
            icon: const Icon(Icons.refresh), label: const Text('Ø¨Ù‡â€ŒØ±ÙˆØ²Ø±Ø³Ø§Ù†ÛŒ Ú©ØªØ§Ø¨Ø®Ø§Ù†Ù‡')),
        ],
      );

  Widget editorPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(children: [
            IconButton(onPressed: () => go(0), icon: const Icon(Icons.arrow_forward, color: gold)),
            const Expanded(child: Text('Ù…Ø­ÛŒØ· ØªØ¯ÙˆÛŒÙ†', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
            TextButton(onPressed: saveCurrentClipToLibrary, child: const Text('Ø°Ø®ÛŒØ±Ù‡ Ù¾Ø±ÙˆÚ˜Ù‡')),
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
            goldButton('Ø°Ø®ÛŒØ±Ù‡ Ù¾Ø±ÙˆÚ˜Ù‡ Ùˆ Ø§Ø¯Ø§Ù…Ù‡ Ø¨Ø¹Ø¯Ø§Ù‹', saveCurrentClipToLibrary, icon: Icons.save_alt),
            const SizedBox(height: 6),
            const Text('Ù¾Ø³ Ø§Ø² Ø§ÙˆÙ„ÛŒÙ† Ø°Ø®ÛŒØ±Ù‡ØŒ ØªÙ†Ø¸ÛŒÙ…Ø§Øª Ùˆ Ù…ØªÙ† Ø²ÛŒØ±Ù†ÙˆÛŒØ³ Ø§ÛŒÙ† Ù¾Ø±ÙˆÚ˜Ù‡ Ø®ÙˆØ¯Ú©Ø§Ø± Ø°Ø®ÛŒØ±Ù‡ Ù…ÛŒâ€ŒØ´ÙˆÙ†Ø¯. Ø§Ø² Ø¨Ø®Ø´ Â«Ú©Ù„ÛŒÙ¾â€ŒÙ‡Ø§ÛŒ Ù…Ù†Â» Ù‡Ø± Ø²Ù…Ø§Ù† Ø®ÙˆØ§Ø³ØªÛŒ Ø¯ÙˆØ¨Ø§Ø±Ù‡ Ø¨Ø§Ø²Ø´ Ú©Ù† Ùˆ Ø§Ø¯Ø§Ù…Ù‡ Ø¨Ø¯Ù‡.', style: TextStyle(color: Colors.white54, fontSize: 11)),
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
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: gold), label: 'Ø®Ø§Ù†Ù‡'),
            NavigationDestination(icon: Icon(Icons.subtitles_outlined), selectedIcon: Icon(Icons.subtitles, color: gold), label: 'Ø²ÛŒØ±Ù†ÙˆÛŒØ³'),
            NavigationDestination(icon: Icon(Icons.record_voice_over_outlined), selectedIcon: Icon(Icons.record_voice_over, color: gold), label: 'ØµØ¯Ø§'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome, color: gold), label: 'Ù‡ÙˆØ´ Ù…ØµÙ†ÙˆØ¹ÛŒ'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings, color: gold), label: 'ØªÙ†Ø¸ÛŒÙ…Ø§Øª'),
          ],
        ),
      ),
    );
  }
}

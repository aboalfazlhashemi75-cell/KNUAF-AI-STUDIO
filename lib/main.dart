import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  File? videoFile;
  VideoPlayerController? videoController;
  bool busy = false;
  String status = 'Ø¨Ø±Ø§ÛŒ Ø´Ø±ÙˆØ¹ØŒ ÛŒÚ© ÙˆÛŒØ¯Ø¦Ùˆ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯.';

  String transcript = '';
  String ideas = '';
  String caption = '';
  String topic = '';
  String hashtags = '';
  String voiceResult = '';
  String voiceFilePath = '';
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
          status = 'Ù…ØªÙ† ÙˆÛŒØ¯Ø¦Ùˆ Ø¨Ø§ Ù…ÙˆÙÙ‚ÛŒØª Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ø´Ø¯.';
        });
      }, 'Ø¯Ø± Ø­Ø§Ù„ Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ú¯ÙØªØ§Ø± ÙˆÛŒØ¯Ø¦Ùˆ...');

  Future<void> createIdeas() => runTask(() async {
        if (transcript.trim().isEmpty) {
          throw Exception('Ø§Ø¨ØªØ¯Ø§ Ù…ØªÙ† ÙˆÛŒØ¯Ø¦Ùˆ Ø±Ø§ Ø§Ø³ØªØ®Ø±Ø§Ø¬ ÛŒØ§ ÙˆØ§Ø±Ø¯ Ú©Ù†ÛŒØ¯.');
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
        final dir = Directory.systemTemp;
        final file = File(
          '${dir.path}${Platform.pathSeparator}avha_audio_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(response.bodyBytes, flush: true);
        setState(() {
          voiceFilePath = file.path;
          voiceResult = 'ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ Ø³Ø§Ø®ØªÙ‡ Ø´Ø¯.\nÙ…Ø³ÛŒØ± Ù…ÙˆÙ‚Øª: ${file.path}';
          status = 'ØªÙˆÙ„ÛŒØ¯ ØµØ¯Ø§ Ø¨Ø§ Ù…ÙˆÙÙ‚ÛŒØª Ø§Ù†Ø¬Ø§Ù… Ø´Ø¯.';
        });
      }, 'Ø¯Ø± Ø­Ø§Ù„ ØªÙˆÙ„ÛŒØ¯ ÙØ§ÛŒÙ„ ØµÙˆØªÛŒ...');

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
        onTap: () => setState(() {
          workspace = title == 'ÙØ¶Ø§ÛŒ Ú©Ø§Ø±ÛŒ' ? 'Ú©Ø§Ø±ÛŒ' : 'Ø´Ø®ØµÛŒ';
          tab = 0;
        }),
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
          card(
            child: Row(children: [
              const Icon(Icons.auto_awesome, size: 42, color: purple),
              const SizedBox(width: 13),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ù‚Ø¯Ø±Øª Ù‡ÙˆØ´ Ù…ØµÙ†ÙˆØ¹ÛŒ Ø¯Ø± Ø¯Ø³ØªØ§Ù† ØªÙˆ', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Ø§ÛŒØ¯Ù‡â€ŒÙ¾Ø±Ø¯Ø§Ø²ÛŒØŒ Ù…ØªÙ† Ùˆ ØªÙˆÙ„ÛŒØ¯ Ù…Ø­ØªÙˆØ§ÛŒ Ù‡ÙˆØ´Ù…Ù†Ø¯', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ])),
              const Icon(Icons.arrow_forward_ios, size: 16, color: gold),
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: modeCard('ÙØ¶Ø§ÛŒ Ø´Ø®ØµÛŒ', 'ÙˆÙ„Ø§Ú¯ØŒ Ø³ÙØ± Ùˆ Ø´Ø¨Ú©Ù‡â€ŒÙ‡Ø§ÛŒ Ø§Ø¬ØªÙ…Ø§Ø¹ÛŒ', Icons.person_outline, blue)),
            const SizedBox(width: 12),
            Expanded(child: modeCard('ÙØ¶Ø§ÛŒ Ú©Ø§Ø±ÛŒ', 'Ù¾Ø±ÙˆÚ˜Ù‡â€ŒÙ‡Ø§ Ùˆ Ù…Ø­ØªÙˆØ§ÛŒ Ú©Ø³Ø¨â€ŒÙˆÚ©Ø§Ø±', Icons.business_center_outlined, gold)),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => go(6),
            icon: const Icon(Icons.folder_open, color: gold),
            label: const Text('Ù¾Ø±ÙˆÚ˜Ù‡â€ŒÙ‡Ø§ÛŒ Ù…Ù†'),
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
          sectionTitle('Ø²ÛŒØ±Ù†ÙˆÛŒØ³ Ù‡ÙˆØ´Ù…Ù†Ø¯', subtitle: 'Ú¯ÙØªØ§Ø± ÙˆÛŒØ¯Ø¦Ùˆ Ø±Ø§ Ø¨Ù‡ Ù…ØªÙ† ÙØ§Ø±Ø³ÛŒ ØªØ¨Ø¯ÛŒÙ„ Ùˆ Ø³Ù¾Ø³ ÙˆÛŒØ±Ø§ÛŒØ´ Ú©Ù†.'),
          card(child: Column(children: [
            goldButton('Ø§Ø³ØªØ®Ø±Ø§Ø¬ Ù…ØªÙ† Ø§Ø² ÙˆÛŒØ¯Ø¦Ùˆ', videoFile == null ? null : transcribe, icon: Icons.subtitles),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey(transcript),
              initialValue: transcript,
              maxLines: 10,
              onChanged: (v) => transcript = v,
              decoration: const InputDecoration(hintText: 'Ù…ØªÙ† Ø§Ø³ØªØ®Ø±Ø§Ø¬â€ŒØ´Ø¯Ù‡ ÛŒØ§ Ù…ØªÙ† Ø¯Ù„Ø®ÙˆØ§Ù‡ Ø±Ø§ ÙˆØ§Ø±Ø¯ Ú©Ù†...'),
            ),
          ])),
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
            goldButton('Ø³Ø§Ø®Øª Ù…Ø­ØªÙˆØ§ÛŒ Ù¾ÛŒØ´Ù†Ù‡Ø§Ø¯ÛŒ', transcript.trim().isEmpty ? null : createIdeas),
          ])),
          const SizedBox(height: 14),
          if (topic.isNotEmpty) resultCard('Ø¹Ù†ÙˆØ§Ù† Ù¾ÛŒØ´Ù†Ù‡Ø§Ø¯ÛŒ', topic),
          if (ideas.isNotEmpty) resultCard('Ø§ÛŒØ¯Ù‡ Ùˆ Ø³Ù†Ø§Ø±ÛŒÙˆ', ideas),
          if (caption.isNotEmpty) resultCard('Ú©Ù¾Ø´Ù†', caption),
          if (hashtags.isNotEmpty) resultCard('Ù‡Ø´ØªÚ¯â€ŒÙ‡Ø§', hashtags),
          if (transcript.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 15),
              child: Text('Ø§Ø¨ØªØ¯Ø§ Ø§Ø² Ø¨Ø®Ø´ Ø²ÛŒØ±Ù†ÙˆÛŒØ³ØŒ Ù…ØªÙ† ÙˆÛŒØ¯Ø¦Ùˆ Ø±Ø§ Ø§Ø³ØªØ®Ø±Ø§Ø¬ ÛŒØ§ ÙˆØ§Ø±Ø¯ Ú©Ù†.',
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
          sectionTitle('Ù¾Ø±ÙˆÚ˜Ù‡â€ŒÙ‡Ø§ÛŒ Ù…Ù†', subtitle: 'Ù¾Ø±ÙˆÚ˜Ù‡ Ø¬Ø§Ø±ÛŒ Ø¯Ø± Ø§ÛŒÙ† Ù†Ø³Ø®Ù‡ Ø¯Ø± Ù‡Ù…ÛŒÙ† Ù†Ø´Ø³Øª Ù‚Ø§Ø¨Ù„ Ø¯Ø³ØªØ±Ø³ÛŒ Ø§Ø³Øª.'),
          if (videoFile == null)
            card(child: const Column(children: [
              Icon(Icons.folder_open, color: gold, size: 42),
              SizedBox(height: 8),
              Text('Ù‡Ù†ÙˆØ² ÙˆÛŒØ¯Ø¦ÙˆÛŒÛŒ Ø§Ù†ØªØ®Ø§Ø¨ Ù†Ø´Ø¯Ù‡ Ø§Ø³Øª.'),
            ]))
          else
            card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              videoPreview(),
              const SizedBox(height: 10),
              Text(videoFile!.path.split(Platform.pathSeparator).last,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              goldButton('Ø¨Ø§Ø² Ú©Ø±Ø¯Ù† Ø¯Ø± ØªØ¯ÙˆÛŒÙ†', () => go(5), icon: Icons.edit),
            ])),
          const SizedBox(height: 12),
          const Text('Ø°Ø®ÛŒØ±Ù‡ Ø¯Ø§Ø¦Ù…ÛŒ Ù¾Ø±ÙˆÚ˜Ù‡â€ŒÙ‡Ø§ Ùˆ Ø§Ø¯Ø§Ù…Ù‡ ØªØ¯ÙˆÛŒÙ† Ù¾Ø³ Ø§Ø² Ø¨Ø³ØªÙ† Ø¨Ø±Ù†Ø§Ù…Ù‡ Ø¯Ø± Ù…Ø±Ø­Ù„Ù‡ Ø¨Ø¹Ø¯ Ø§Ø¶Ø§ÙÙ‡ Ù…ÛŒâ€ŒØ´ÙˆØ¯.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );

  Widget editorPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(children: [
            IconButton(onPressed: () => go(0), icon: const Icon(Icons.arrow_forward, color: gold)),
            const Expanded(child: Text('Ù…Ø­ÛŒØ· ØªØ¯ÙˆÛŒÙ†', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
            TextButton(onPressed: () => showInfo('Ø®Ø±ÙˆØ¬ÛŒ ÙˆÛŒØ¯Ø¦Ùˆ', 'Ø®Ø±ÙˆØ¬ÛŒ Ù†Ù‡Ø§ÛŒÛŒ Ùˆ Ø±Ù†Ø¯Ø± ØªØ¯ÙˆÛŒÙ† Ø¯Ø± Ù…Ø±Ø­Ù„Ù‡ Ø¨Ø¹Ø¯ ÙØ¹Ø§Ù„ Ù…ÛŒâ€ŒØ´ÙˆØ¯.'), child: const Text('Ø®Ø±ÙˆØ¬ÛŒ')),
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

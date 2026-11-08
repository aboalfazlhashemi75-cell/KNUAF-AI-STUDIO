import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() => runApp(const KnaufStudioApp());

// =========================
// SETTINGS
// =========================

const gold = Color(0xFFD6AD55);
const bg = Color(0xFF101010);
const panel = Color(0xFF1B1B1B);

const String apiBaseUrl = String.fromEnvironment(
  'KNUAF_API_URL',
  defaultValue: 'https://knuaf-ai-studio.fastapicloud.dev',
);

// =========================
// APP
// =========================

class KnaufStudioApp extends StatelessWidget {
  const KnaufStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KNUAF AI STUDIO',
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
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
      home: const StudioHome(),
    );
  }
}

// =========================
// HOME SCREEN
// =========================

class StudioHome extends StatefulWidget {
  const StudioHome({super.key});

  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  int tab = 0;

  File? videoFile;
  VideoPlayerController? videoController;

  bool busy = false;

  String status = '???? ????? ?? ????? ?????? ??.';

  String transcript = '';
  String ideas = '';
  String caption = '';
  String topic = '';
  String hashtags = '';

  String voiceResult = '';
  String voiceFilePath = '';

  String selectedVoice = 'fa-IR-FaridNeural';

  final voiceController = TextEditingController();

  // =========================
  // DISPOSE
  // =========================

  @override
  void dispose() {
    videoController?.dispose();
    voiceController.dispose();
    super.dispose();
  }

  // =========================
  // ERROR HANDLING
  // =========================

  String responseText(http.Response response) {
    return utf8.decode(
      response.bodyBytes,
      allowMalformed: true,
    );
  }

  Map<String, dynamic> decodeJson(String body) {
    final decoded = jsonDecode(body);

    if (decoded is! Map) {
      throw Exception('???? ???? ????? ????.');
    }

    return Map<String, dynamic>.from(decoded);
  }

  // =========================
  // SELECT VIDEO
  // =========================

  Future<void> pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: false,
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

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

        status = '????? ?????? ??.';
      });

      await controller.initialize();
      await controller.setLooping(true);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '??? ?? ?????? ?????: $e';
        });
      }
    }
  }

  // =========================
  // UPLOAD VIDEO
  // =========================

  Future<Map<String, dynamic>> uploadVideoForTranscription() async {
    if (videoFile == null) {
      throw Exception('????? ?? ????? ?????? ??.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$apiBaseUrl/transcribe'),
    );

    request.headers['Accept'] = 'application/json';

    request.files.add(
      await http.MultipartFile.fromPath(
        'video',
        videoFile!.path,
      ),
    );

    final streamed = await request.send().timeout(
      const Duration(minutes: 10),
    );

    final bytes = await streamed.stream.toBytes();

    final body = utf8.decode(
      bytes,
      allowMalformed: true,
    );

    if (streamed.statusCode < 200 ||
        streamed.statusCode >= 300) {
      throw Exception(
        '???? ???? (${streamed.statusCode}): $body',
      );
    }

    return decodeJson(body);
  }

  // =========================
  // RUN TASK
  // =========================

  Future<void> runTask(
    Future<void> Function() task,
    String label,
  ) async {
    if (busy) return;

    setState(() {
      busy = true;
      status = label;
    });

    try {
      await task();
    } catch (e) {
      if (mounted) {
        setState(() {
          status = '???: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  // =========================
  // TRANSCRIBE VIDEO
  // =========================

  Future<void> transcribe() {
    return runTask(() async {
      final data = await uploadVideoForTranscription();

      final text = (data['text'] ?? '').toString();

      if (text.trim().isEmpty) {
        throw Exception('???? ?? ????? ????? ???? ???.');
      }

      setState(() {
        transcript = text;
        status = '??? ????? ?? ?????? ??????? ??.';
      });
    }, '?? ??? ????? ????? ? ????? ????? ?????...');
  }

  // =========================
  // GENERATE AI CONTENT
  // =========================

  Future<void> createIdeas() {
    return runTask(() async {
      if (transcript.trim().isEmpty) {
        throw Exception('????? ??????? ????? ?? ??????? ??.');
      }

      final payload = {
        'transcript': transcript.trim(),
        'business': 'KNUAF HASHEMI',
      };

      final response = await http.post(
        Uri.parse('$apiBaseUrl/content'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        },
        body: utf8.encode(jsonEncode(payload)),
      ).timeout(
        const Duration(minutes: 3),
      );

      final body = responseText(response);

      if (response.statusCode != 200) {
        throw Exception(
          '???? ????? ????? (${response.statusCode}): $body',
        );
      }

      final data = decodeJson(body);

      if (data['ok'] != true || data['content'] is! Map) {
        throw Exception('?????? ???? ??? ?????? ????? ????.');
      }

      final content = Map<String, dynamic>.from(
        data['content'],
      );

      final topicText = (content['topic'] ?? '').toString();
      final ideaText = (content['idea'] ?? '').toString();
      final captionText = (content['caption'] ?? '').toString();

      final tagList = content['hashtags'];

      final tagText = tagList is List
          ? tagList.map((e) => e.toString()).join('  ')
          : '';

      setState(() {
        topic = topicText;
        ideas = ideaText;
        caption = captionText;
        hashtags = tagText;

        status = '?????? ???? ? ???? ????? ????.';
      });
    }, '??? ?????? ?? ??? ????? ? ????? ?????...');
  }

  // =========================
  // TEXT TO SPEECH
  // =========================

  Future<void> createVoice() {
    return runTask(() async {
      final text = voiceController.text.trim();

      if (text.isEmpty) {
        throw Exception('??? ??????? ?? ???? ??.');
      }

      final payload = {
        'text': text,
        'voice': selectedVoice,
      };

      final response = await http.post(
        Uri.parse('$apiBaseUrl/tts'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'audio/mpeg',
        },
        body: utf8.encode(jsonEncode(payload)),
      ).timeout(
        const Duration(minutes: 3),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '???? ????? ??? ?? ???: ${responseText(response)}',
        );
      }

      if (response.bodyBytes.isEmpty) {
        throw Exception('???? ???? ???? ?????? ??.');
      }

      final tempDirectory = Directory.systemTemp;

      final fileName =
          'knuaf_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final audioFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}$fileName',
      );

      await audioFile.writeAsBytes(
        response.bodyBytes,
        flush: true,
      );

      setState(() {
        voiceFilePath = audioFile.path;

        voiceResult =
            '???? ???? ?? ?????? ????? ??.\n'
            '??? ????: ${response.bodyBytes.length} ????\n'
            '???? ????: ${audioFile.path}';

        status = '????? ???? ????? ????? ??.';
      });
    }, '?? ??? ???? ???? ?????...');
  }

  // =========================
  // GOLD BUTTON
  // =========================

  Widget goldButton(
    String text,
    VoidCallback? onPressed, {
    IconData icon = Icons.auto_awesome,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: Icon(icon),
        label: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // =========================
  // VIDEO PREVIEW
  // =========================

  Widget videoPreview() {
    final c = videoController;

    if (c == null || !c.value.isInitialized) {
      return Container(
        height: 205,
        width: double.infinity,
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 48,
              color: gold,
            ),
            SizedBox(height: 10),
            Text(
              '????????? ?????',
              style: TextStyle(color: Colors.white70),
            ),
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

            VideoProgressIndicator(
              c,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: gold,
              ),
            ),

            Align(
              alignment: Alignment.center,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                iconSize: 38,
                onPressed: () {
                  setState(() {
                    c.value.isPlaying ? c.pause() : c.play();
                  });
                },
                icon: Icon(
                  c.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // FEATURE TILE
  // =========================

  Widget featureTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Card(
      color: panel,
      child: ListTile(
        leading: Icon(
          icon,
          color: gold,
          size: 29,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white60,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  // =========================
  // HOME PAGE
  // =========================

  Widget homePage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          '???????? ?????? ????? ????',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 6),

        const Text(
          '?? ???? ??? ????? ?? ?????? ????? ??????????',
          style: TextStyle(color: Colors.white60),
        ),

        const SizedBox(height: 18),

        videoPreview(),

        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: busy ? null : pickVideo,
          icon: const Icon(
            Icons.add_to_photos_outlined,
            color: gold,
          ),
          label: Text(
            videoFile == null
                ? '?????? ????? ?? ????'
                : '?????? ?????? ????',
          ),
        ),

        if (videoFile != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              videoFile!.path.split(Platform.pathSeparator).last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
              ),
            ),
          ),

        const SizedBox(height: 18),

        featureTile(
          Icons.subtitles,
          '??????? ??????',
          '????? ????? ????? ?? ??? ?????',
          () => setState(() => tab = 1),
        ),

        featureTile(
          Icons.graphic_eq,
          '????? ??? ?? ???',
          '???? ??????? ????? ?? ???? ?? ? ???',
          () => setState(() => tab = 2),
        ),

        featureTile(
          Icons.lightbulb_outline,
          '???? ? ???? ??????',
          '???? ????? ??????? ???? ? ????',
          () => setState(() => tab = 3),
        ),

        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: gold,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================
  // SUBTITLE PAGE
  // =========================

  Widget captionsPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          '??????? ?????? ?????',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          '???? ????? ?? ????? ????? ????? ?? ??? ????? ????? ??????.',
          style: TextStyle(color: Colors.white60),
        ),

        const SizedBox(height: 18),

        goldButton(
          '??????? ??????? ?? ?????',
          videoFile == null ? null : transcribe,
          icon: Icons.subtitles,
        ),

        const SizedBox(height: 16),

        TextFormField(
          initialValue: transcript,
          key: ValueKey(transcript),
          maxLines: 10,
          onChanged: (v) => transcript = v,
          decoration: const InputDecoration(
            hintText: '??? ????? ???????? ????? ????? ???? ??????...',
          ),
        ),

        const SizedBox(height: 12),

        const Text(
          '?? ?? ???????? ???????? ??? ?? ?????? ???.',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // =========================
  // VOICE PAGE
  // =========================

  Widget voicePage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          '???????? ????? ??? ?? ???',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          '??? ??????? ?? ????? ?? ?? ???? ????? ????? ???.',
          style: TextStyle(color: Colors.white60),
        ),

        const SizedBox(height: 16),

        TextField(
          controller: voiceController,
          maxLines: 7,
          decoration: const InputDecoration(
            hintText: '??? ??????? ???? ??????? ?? ???? ??...',
          ),
        ),

        const SizedBox(height: 16),

        const Text(
          '?????? ???? ??????',
          style: TextStyle(
            color: gold,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        DropdownButtonFormField<String>(
          value: selectedVoice,
          decoration: const InputDecoration(
            filled: true,
          ),
          items: const [
            DropdownMenuItem(
              value: 'fa-IR-FaridNeural',
              child: Text('???? ???'),
            ),
            DropdownMenuItem(
              value: 'fa-IR-DilaraNeural',
              child: Text('???? ??'),
            ),
          ],
          onChanged: busy
              ? null
              : (value) {
                  if (value != null) {
                    setState(() {
                      selectedVoice = value;
                    });
                  }
                },
        ),

        const SizedBox(height: 16),

        goldButton(
          '????? ???? ????',
          createVoice,
          icon: Icons.graphic_eq,
        ),

        if (voiceResult.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                voiceResult,
                style: const TextStyle(
                  color: gold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // =========================
  // AI PAGE
  // =========================

  Widget aiPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          '?????? ?????? ?????',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        const Text(
          '?? ??????? ?? ??????? ? ??????? ????????? '
          '???? ? ???? ????? ????? ????? ??????.',
          style: TextStyle(color: Colors.white60),
        ),

        const SizedBox(height: 16),

        goldButton(
          '????? ????? ? ???? ???? ? ????',
          transcript.trim().isEmpty ? null : createIdeas,
          icon: Icons.auto_awesome,
        ),

        const SizedBox(height: 18),

        if (topic.isNotEmpty) ...[
          const Text(
            '????? ?????',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: gold,
            ),
          ),

          const SizedBox(height: 8),

          SelectableText(topic),

          const SizedBox(height: 18),
        ],

        if (ideas.isNotEmpty) ...[
          const Text(
            '???? ????????',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: gold,
            ),
          ),

          const SizedBox(height: 8),

          SelectableText(ideas),

          const SizedBox(height: 18),
        ],

        if (caption.isNotEmpty) ...[
          const Text(
            '???? ????????',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: gold,
            ),
          ),

          const SizedBox(height: 8),

          SelectableText(caption),

          const SizedBox(height: 18),
        ],

        if (hashtags.isNotEmpty) ...[
          const Text(
            '???????',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: gold,
            ),
          ),

          const SizedBox(height: 8),

          SelectableText(hashtags),
        ],

        if (ideas.isEmpty && caption.isEmpty)
          const Text(
            '?? ?? ??????? ???????? ???? ? ???? ????? ????? ???? ??????.',
            style: TextStyle(color: Colors.white54),
          ),
      ],
    );
  }

  // =========================
  // BUILD
  // =========================

  @override
  Widget build(BuildContext context) {
    final pages = [
      homePage(),
      captionsPage(),
      voicePage(),
      aiPage(),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KNUAF AI STUDIO',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                'CREATE • EDIT • PUBLISH',
                style: TextStyle(
                  fontSize: 9,
                  color: gold,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          actions: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(
                Icons.auto_awesome,
                color: gold,
              ),
            ),
          ],
        ),

        body: SafeArea(
          child: Stack(
            children: [
              IndexedStack(
                index: tab,
                children: pages,
              ),

              if (busy)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Card(
                      color: panel,
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: gold,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              status,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        bottomNavigationBar: NavigationBar(
          backgroundColor: panel,
          indicatorColor: gold.withOpacity(.18),
          selectedIndex: tab,
          onDestinationSelected: (i) {
            setState(() {
              tab = i;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(
                Icons.home,
                color: gold,
              ),
              label: '????',
            ),

            NavigationDestination(
              icon: Icon(Icons.subtitles_outlined),
              selectedIcon: Icon(
                Icons.subtitles,
                color: gold,
              ),
              label: '???????',
            ),

            NavigationDestination(
              icon: Icon(Icons.record_voice_over_outlined),
              selectedIcon: Icon(
                Icons.record_voice_over,
                color: gold,
              ),
              label: '???',
            ),

            NavigationDestination(
              icon: Icon(Icons.psychology_outlined),
              selectedIcon: Icon(
                Icons.psychology,
                color: gold,
              ),
              label: '??? ??????',
            ),
          ],
        ),
      ),
    );
  }
}
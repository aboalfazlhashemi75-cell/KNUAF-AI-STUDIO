import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

void main() => runApp(const KnaufStudioApp());

const gold = Color(0xFFD6AD55);
const bg = Color(0xFF101010);
const panel = Color(0xFF1B1B1B);

const String apiBaseUrl = String.fromEnvironment(
  'KNUAF_API_URL',
  defaultValue: 'https://knuaf-ai-studio.fastapicloud.dev',
);

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

  String status = 'برای شروع، یک ویدئو انتخاب کنید.';

  String transcript = '';
  String ideas = '';
  String caption = '';
  String topic = '';
  String hashtags = '';

  String voiceResult = '';
  String voiceFilePath = '';

  String selectedVoice = 'fa-IR-FaridNeural';

  final voiceController = TextEditingController();

  @override
  void dispose() {
    videoController?.dispose();
    voiceController.dispose();
    super.dispose();
  }

  String responseText(http.Response response) {
    return utf8.decode(
      response.bodyBytes,
      allowMalformed: true,
    );
  }

  Map<String, dynamic> decodeJson(String body) {
    final decoded = jsonDecode(body);

    if (decoded is! Map) {
      throw Exception('پاسخ سرور معتبر نیست.');
    }

    return Map<String, dynamic>.from(decoded);
  }

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

        status = 'ویدئو انتخاب شد.';
      });

      await controller.initialize();
      await controller.setLooping(true);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          status = 'خطا در انتخاب ویدئو: $e';
        });
      }
    }
  }

  Future<Map<String, dynamic>> uploadVideoForTranscription() async {
    if (videoFile == null) {
      throw Exception('ابتدا یک ویدئو انتخاب کنید.');
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
        'خطای سرور (${streamed.statusCode}): $body',
      );
    }

    return decodeJson(body);
  }

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
          status = 'خطا: $e';
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

  Future<void> transcribe() {
    return runTask(() async {
      final data = await uploadVideoForTranscription();

      final text = (data['text'] ?? '').toString();

      if (text.trim().isEmpty) {
        throw Exception('متنی از ویدئو استخراج نشد.');
      }

      setState(() {
        transcript = text;
        status = 'متن ویدئو با موفقیت استخراج شد.';
      });
    }, 'در حال ارسال ویدئو و استخراج متن...');
  }

  Future<void> createIdeas() {
    return runTask(() async {
      if (transcript.trim().isEmpty) {
        throw Exception('ابتدا متن ویدئو را استخراج کنید.');
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
          'خطای تولید محتوا (${response.statusCode}): $body',
        );
      }

      final data = decodeJson(body);

      if (data['ok'] != true || data['content'] is! Map) {
        throw Exception('ساختار پاسخ سرور معتبر نیست.');
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

        status = 'محتوای پیشنهادی با موفقیت تولید شد.';
      });
    }, 'در حال ساخت ایده و کپشن با هوش مصنوعی...');
  }

  Future<void> createVoice() {
    return runTask(() async {
      final text = voiceController.text.trim();

      if (text.isEmpty) {
        throw Exception('متن موردنظر را وارد کنید.');
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
          'تولید صدا ناموفق بود: ${responseText(response)}',
        );
      }

      if (response.bodyBytes.isEmpty) {
        throw Exception('فایل صوتی خالی دریافت شد.');
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
            'فایل صوتی با موفقیت ساخته شد.\n'
            'حجم فایل: ${response.bodyBytes.length} بایت\n'
            'مسیر فایل: ${audioFile.path}';

        status = 'تولید صدا با موفقیت انجام شد.';
      });
    }, 'در حال تولید فایل صوتی...');
  }

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
              'پیش‌نمایش ویدئو',
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

  Widget homePage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'استودیوی هوشمند تولید محتوا',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'ویدئوهای خود را به محتوای حرفه‌ای تبدیل کنید.',
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
                ? 'انتخاب ویدئو از گوشی'
                : 'تغییر ویدئوی انتخاب‌شده',
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
          'زیرنویس هوشمند',
          'استخراج متن گفتار از روی ویدئو',
          () => setState(() => tab = 1),
        ),
        featureTile(
          Icons.graphic_eq,
          'تبدیل متن به صدا',
          'تولید فایل صوتی با صدای فارسی',
          () => setState(() => tab = 2),
        ),
        featureTile(
          Icons.lightbulb_outline,
          'ایده و تولید محتوا',
          'تولید عنوان، کپشن و هشتگ',
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

  Widget captionsPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'استخراج زیرنویس و متن',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'گفتار موجود در ویدئو را به متن فارسی تبدیل کنید.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 18),
        goldButton(
          'استخراج زیرنویس از ویدئو',
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
            hintText: 'متن استخراج‌شده یا متن دلخواه خود را وارد کنید...',
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'می‌توانید متن استخراج‌شده را ویرایش کنید.',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget voicePage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'تبدیل متن به صدای فارسی',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'متن دلخواه خود را وارد کنید تا به صدا تبدیل شود.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: voiceController,
          maxLines: 7,
          decoration: const InputDecoration(
            hintText: 'متن موردنظر برای تبدیل به صدا را بنویسید...',
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'انتخاب صدای گوینده',
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
              child: Text('صدای مرد'),
            ),
            DropdownMenuItem(
              value: 'fa-IR-DilaraNeural',
              child: Text('صدای زن'),
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
          'تولید فایل صوتی',
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

  Widget aiPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'تولید محتوای هوشمند',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'با استفاده از متن ویدئو، عنوان، ایده و کپشن مناسب تولید کنید.',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 16),
        goldButton(
          'تولید ایده، کپشن و هشتگ',
          transcript.trim().isEmpty ? null : createIdeas,
          icon: Icons.auto_awesome,
        ),
        const SizedBox(height: 18),
        if (topic.isNotEmpty) ...[
          const Text(
            'عنوان پیشنهادی',
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
            'ایده پیشنهادی',
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
            'متن کپشن',
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
            'هشتگ‌ها',
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
            'برای استفاده از این بخش ابتدا متن ویدئو را استخراج کنید.',
            style: TextStyle(color: Colors.white54),
          ),
      ],
    );
  }

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
              label: 'خانه',
            ),
            NavigationDestination(
              icon: Icon(Icons.subtitles_outlined),
              selectedIcon: Icon(
                Icons.subtitles,
                color: gold,
              ),
              label: 'زیرنویس',
            ),
            NavigationDestination(
              icon: Icon(Icons.record_voice_over_outlined),
              selectedIcon: Icon(
                Icons.record_voice_over,
                color: gold,
              ),
              label: 'صدا',
            ),
            NavigationDestination(
              icon: Icon(Icons.psychology_outlined),
              selectedIcon: Icon(
                Icons.psychology,
                color: gold,
              ),
              label: 'هوش مصنوعی',
            ),
          ],
        ),
      ),
    );
  }
}

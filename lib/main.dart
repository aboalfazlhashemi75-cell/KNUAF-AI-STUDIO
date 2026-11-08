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
  String workspace = 'شخصی';

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
  void dispose() {
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
          status = 'متن ویدئو با موفقیت استخراج شد.';
        });
      }, 'در حال استخراج گفتار ویدئو...');

  Future<void> createIdeas() => runTask(() async {
        if (transcript.trim().isEmpty) {
          throw Exception('ابتدا متن ویدئو را استخراج یا وارد کنید.');
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
        final dir = Directory.systemTemp;
        final file = File(
          '${dir.path}${Platform.pathSeparator}avha_audio_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(response.bodyBytes, flush: true);
        setState(() {
          voiceFilePath = file.path;
          voiceResult = 'فایل صوتی ساخته شد.\nمسیر موقت: ${file.path}';
          status = 'تولید صدا با موفقیت انجام شد.';
        });
      }, 'در حال تولید فایل صوتی...');

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
          workspace = title == 'فضای کاری' ? 'کاری' : 'شخصی';
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
                Text('ورود به فضا', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
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
          card(
            child: Row(children: [
              const Icon(Icons.auto_awesome, size: 42, color: purple),
              const SizedBox(width: 13),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('قدرت هوش مصنوعی در دستان تو', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('ایده‌پردازی، متن و تولید محتوای هوشمند', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ])),
              const Icon(Icons.arrow_forward_ios, size: 16, color: gold),
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: modeCard('فضای شخصی', 'ولاگ، سفر و شبکه‌های اجتماعی', Icons.person_outline, blue)),
            const SizedBox(width: 12),
            Expanded(child: modeCard('فضای کاری', 'پروژه‌ها و محتوای کسب‌وکار', Icons.business_center_outlined, gold)),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => go(6),
            icon: const Icon(Icons.folder_open, color: gold),
            label: const Text('پروژه‌های من'),
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
          sectionTitle('زیرنویس هوشمند', subtitle: 'گفتار ویدئو را به متن فارسی تبدیل و سپس ویرایش کن.'),
          card(child: Column(children: [
            goldButton('استخراج متن از ویدئو', videoFile == null ? null : transcribe, icon: Icons.subtitles),
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey(transcript),
              initialValue: transcript,
              maxLines: 10,
              onChanged: (v) => transcript = v,
              decoration: const InputDecoration(hintText: 'متن استخراج‌شده یا متن دلخواه را وارد کن...'),
            ),
          ])),
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
            goldButton('ساخت محتوای پیشنهادی', transcript.trim().isEmpty ? null : createIdeas),
          ])),
          const SizedBox(height: 14),
          if (topic.isNotEmpty) resultCard('عنوان پیشنهادی', topic),
          if (ideas.isNotEmpty) resultCard('ایده و سناریو', ideas),
          if (caption.isNotEmpty) resultCard('کپشن', caption),
          if (hashtags.isNotEmpty) resultCard('هشتگ‌ها', hashtags),
          if (transcript.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 15),
              child: Text('ابتدا از بخش زیرنویس، متن ویدئو را استخراج یا وارد کن.',
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
          sectionTitle('پروژه‌های من', subtitle: 'پروژه جاری در این نسخه در همین نشست قابل دسترسی است.'),
          if (videoFile == null)
            card(child: const Column(children: [
              Icon(Icons.folder_open, color: gold, size: 42),
              SizedBox(height: 8),
              Text('هنوز ویدئویی انتخاب نشده است.'),
            ]))
          else
            card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              videoPreview(),
              const SizedBox(height: 10),
              Text(videoFile!.path.split(Platform.pathSeparator).last,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              goldButton('باز کردن در تدوین', () => go(5), icon: Icons.edit),
            ])),
          const SizedBox(height: 12),
          const Text('ذخیره دائمی پروژه‌ها و ادامه تدوین پس از بستن برنامه در مرحله بعد اضافه می‌شود.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );

  Widget editorPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(children: [
            IconButton(onPressed: () => go(0), icon: const Icon(Icons.arrow_forward, color: gold)),
            const Expanded(child: Text('محیط تدوین', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
            TextButton(onPressed: () => showInfo('خروجی ویدئو', 'خروجی نهایی و رندر تدوین در مرحله بعد فعال می‌شود.'), child: const Text('خروجی')),
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

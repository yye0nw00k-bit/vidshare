import 'package:flutter/material.dart';

void main() {
  runApp(const VidShareApp());
}

const ink = Color(0xFF10131A);
const panel = Color(0xFF191E29);
const accent = Color(0xFF7C5CFF);
const muted = Color(0xFF9AA3B5);

class VidShareApp extends StatelessWidget {
  const VidShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VidShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ink,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: ink,
        ),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selected = 0;

  final pages = const [
    HomePage(),
    SubscriptionsPage(),
    UploadPage(),
    LibraryPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: pages[selected]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: panel,
        indicatorColor: accent.withValues(alpha: .22),
        selectedIndex: selected,
        onDestinationSelected: (value) => setState(() => selected = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: '홈'),
          NavigationDestination(icon: Icon(Icons.subscriptions_outlined), label: '구독'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: '업로드'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), label: '보관함'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: ink,
          title: const Brand(),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search_rounded),
              tooltip: '검색',
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: '내 계정',
            ),
            const SizedBox(width: 6),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('오늘은 어떤 영상을 볼까요?',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                const Text('관심 있는 크리에이터와 새로운 영상을 만나보세요.',
                    style: TextStyle(color: muted)),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF30265F), Color(0xFF1B2942)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR VIDEO SPACE',
                          style: TextStyle(letterSpacing: 1.5, fontSize: 11,
                              fontWeight: FontWeight.bold, color: Color(0xFFC9BCFF))),
                      SizedBox(height: 9),
                      Text('나만의 영상 세상,\nVidShare',
                          style: TextStyle(fontSize: 25, height: 1.2,
                              fontWeight: FontWeight.w900)),
                      SizedBox(height: 8),
                      Text('좋아하는 영상을 발견하고 공유해 보세요.',
                          style: TextStyle(color: Color(0xFFD3D7E5))),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('추천 영상',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const EmptyFeedCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class EmptyFeedCard extends StatelessWidget {
  const EmptyFeedCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: const Column(
        children: [
          Icon(Icons.play_circle_outline_rounded, size: 42, color: accent),
          SizedBox(height: 12),
          Text('영상 피드를 연결할 준비 중이에요',
              style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('기존 VidShare 영상 API를 연결하면\n여기에 영상 목록이 표시됩니다.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, height: 1.5)),
        ],
      ),
    );
  }
}

class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context) => const SimplePage(
    icon: Icons.subscriptions_outlined,
    title: '구독',
    description: '구독한 채널의 새 영상을 모아볼 수 있어요.',
  );
}

class UploadPage extends StatelessWidget {
  const UploadPage({super.key});

  @override
  Widget build(BuildContext context) => const SimplePage(
    icon: Icons.cloud_upload_outlined,
    title: '영상 업로드',
    description: '기존 VidShare 업로드 기능과 연결할 예정이에요.',
  );
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) => const SimplePage(
    icon: Icons.video_library_outlined,
    title: '보관함',
    description: '내 영상과 시청 기록을 확인할 수 있어요.',
  );
}

class SimplePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const SimplePage({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Brand(),
            const SizedBox(height: 38),
            Icon(icon, size: 48, color: accent),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center,
                style: const TextStyle(color: muted, height: 1.5)),
            const SizedBox(height: 18),
            const Text('모바일 앱 초기 화면',
                style: TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_circle_fill_rounded, color: accent, size: 29),
        SizedBox(width: 8),
        Text('vidshare',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                letterSpacing: -.8)),
      ],
    );
  }
}

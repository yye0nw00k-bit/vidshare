import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'api_client.dart';

const ink = Color(0xFF10131A);
const panel = Color(0xFF191E29);
const accent = Color(0xFF7C5CFF);
const muted = Color(0xFF9AA3B5);

void main() => runApp(const VidShareApp());

class VidShareApp extends StatefulWidget {
  const VidShareApp({super.key});

  @override
  State<VidShareApp> createState() => _VidShareAppState();
}

class _VidShareAppState extends State<VidShareApp> {
  final VidShareApi api = VidShareApi();
  bool _starting = true;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    await api.initialize();
    var valid = false;
    if (api.hasToken && api.baseUrl.isNotEmpty) {
      try {
        await api.me();
        valid = true;
      } catch (_) {
        try {
          await api.logout();
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _signedIn = valid;
      _starting = false;
    });
  }

  void _onAuthenticated() {
    setState(() => _signedIn = true);
  }

  Future<void> _onLogout() async {
    try {
      await api.logout();
    } catch (_) {}
    if (mounted) setState(() => _signedIn = false);
  }

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
        appBarTheme: const AppBarTheme(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: _starting
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _signedIn
              ? MainShell(api: api, onLogout: _onLogout)
              : AuthPage(api: api, onAuthenticated: _onAuthenticated),
    );
  }
}

class AuthPage extends StatefulWidget {
  final VidShareApi api;
  final VoidCallback onAuthenticated;

  const AuthPage({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _server.text = widget.api.baseUrl;
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.setBaseUrl(_server.text);
      if (_register) {
        await widget.api.register(_username.text.trim(), _password.text);
      } else {
        await widget.api.login(_username.text.trim(), _password.text);
      }
      widget.onAuthenticated();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '요청을 처리하지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Brand(),
                    const SizedBox(height: 14),
                    const Text(
                      'PC와 같은 VidShare 계정으로 로그인하세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      _register ? '계정 만들기' : '로그인',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'VidShare 서버 주소',
                        hintText: 'https://내-vidshare-주소.onrender.com',
                        prefixIcon: Icon(Icons.link),
                      ),
                      validator: (value) {
                        final uri = Uri.tryParse((value ?? '').trim());
                        if (uri == null ||
                            !uri.hasScheme ||
                            uri.host.isEmpty ||
                            !['https', 'http'].contains(uri.scheme)) {
                          return '배포된 VidShare 주소를 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '닉네임',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        final name = (value ?? '').trim();
                        if (name.length < 2 || name.length > 30) {
                          return '닉네임은 2~30자여야 합니다.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '비밀번호',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _hidePassword = !_hidePassword,
                          ),
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final password = value ?? '';
                        if (password.isEmpty) {
                          return '비밀번호를 입력해주세요.';
                        }
                        if (_register && password.length < 8) {
                          return '비밀번호는 8자 이상이어야 합니다.';
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? '회원가입' : '로그인'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                      child: Text(
                        _register
                            ? '이미 계정이 있나요? 로그인'
                            : '계정이 없나요? 회원가입',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '회원 정보는 PC VidShare와 같은 서버에 저장됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final VidShareApi api;
  final Future<void> Function() onLogout;

  const MainShell({
    super.key,
    required this.api,
    required this.onLogout,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      VideoFeed(api: widget.api, feed: 'home', title: '추천 영상', searchable: true),
      VideoFeed(api: widget.api, feed: 'subscriptions', title: '구독'),
      UploadPage(api: widget.api),
      LibraryPage(api: widget.api),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Brand(),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') widget.onLogout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'logout',
                child: Text('로그아웃'),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _selected, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: panel,
        indicatorColor: accent.withValues(alpha: .22),
        selectedIndex: _selected,
        onDestinationSelected: (value) => setState(() => _selected = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: '홈'),
          NavigationDestination(
            icon: Icon(Icons.subscriptions_outlined),
            label: '구독',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            label: '업로드',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            label: '보관함',
          ),
        ],
      ),
    );
  }
}

class VideoFeed extends StatefulWidget {
  final VidShareApi api;
  final String feed;
  final String title;
  final bool searchable;

  const VideoFeed({
    super.key,
    required this.api,
    required this.feed,
    required this.title,
    this.searchable = false,
  });

  @override
  State<VideoFeed> createState() => _VideoFeedState();
}

class _VideoFeedState extends State<VideoFeed> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _videos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.videos(
        feed: widget.feed,
        query: _search.text,
      );
      if (!mounted) return;
      setState(() => _videos = items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '영상을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openVideo(Map<String, dynamic> item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(
          api: widget.api,
          videoId: item['id'] as int,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: '영상 또는 채널 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
        Expanded(
          child: _loading && _videos.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _videos.isEmpty
                  ? _MessageState(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _videos.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 100),
                                Icon(
                                  Icons.ondemand_video_outlined,
                                  size: 54,
                                  color: muted.withValues(alpha: .8),
                                ),
                                const SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    widget.feed == 'subscriptions'
                                        ? '구독한 채널의 영상이 아직 없어요.'
                                        : '아직 표시할 영상이 없어요.',
                                    style: const TextStyle(color: muted),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                              itemCount: _videos.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final item = _videos[index];
                                return VideoCard(
                                  item: item,
                                  onTap: () => _openVideo(item),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }
}

class VideoCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const VideoCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnail = item['thumbnail_url']?.toString() ?? '';
    return Material(
      color: panel,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: thumbnail.isEmpty
                  ? Container(
                      color: const Color(0xFF252B3A),
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_outline,
                          size: 52,
                          color: accent,
                        ),
                      ),
                    )
                  : Image.network(
                      thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF252B3A),
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_outline,
                            size: 52,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 19,
                    backgroundColor: Color(0xFF30265F),
                    child: Icon(Icons.person, color: Colors.white70),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title']?.toString() ?? '제목 없는 영상',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          (item['creator']?.toString() ?? '알 수 없는 채널') +
                              '  ·  조회수 ' +
                              (item['views']?.toString() ?? '0'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '좋아요 ' +
                              (item['likes']?.toString() ?? '0') +
                              '  ·  댓글 ' +
                              (item['comments']?.toString() ?? '0'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_vert, color: muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoDetailPage extends StatefulWidget {
  final VidShareApi api;
  final int videoId;

  const VideoDetailPage({
    super.key,
    required this.api,
    required this.videoId,
  });

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  final _comment = TextEditingController();
  Map<String, dynamic>? _video;
  VideoPlayerController? _player;
  bool _loading = true;
  bool _commentBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final video = await widget.api.video(widget.videoId);
      final url = video['video_url']?.toString() ?? '';
      VideoPlayerController? player;
      if (url.isNotEmpty) {
        player = VideoPlayerController.networkUrl(Uri.parse(url));
        await player.initialize();
      }
      if (!mounted) {
        await player?.dispose();
        return;
      }
      await _player?.dispose();
      setState(() {
        _video = video;
        _player = player;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '영상을 재생할 수 없습니다. 파일 주소와 서버 상태를 확인해주세요.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _like() async {
    try {
      final result = await widget.api.toggleLike(widget.videoId);
      if (!mounted || _video == null) return;
      setState(() {
        _video!['is_liked'] = result['liked'];
        _video!['likes'] = result['likes'];
      });
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _subscribe() async {
    final channelId = _video?['creator_id'];
    if (channelId is! int) return;
    try {
      final result = await widget.api.toggleSubscribe(channelId);
      if (!mounted) return;
      setState(() {
        _video!['is_subscribed'] = result['subscribed'];
        _video!['subscriber_count'] = result['subscriber_count'];
      });
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _sendComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    setState(() => _commentBusy = true);
    try {
      await widget.api.addComment(widget.videoId, body);
      _comment.clear();
      await _load();
    } on ApiException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _commentBusy = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final comments = video?['comments_list'] is List
        ? (video!['comments_list'] as List)
        : const [];

    return Scaffold(
      appBar: AppBar(title: const Text('영상 보기')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _MessageState(message: _error!, onRetry: _load)
              : video == null
                  ? const Center(child: Text('영상을 찾을 수 없습니다.'))
                  : ListView(
                      children: [
                        if (_player != null && _player!.value.isInitialized)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _player!.value.isPlaying
                                    ? _player!.pause()
                                    : _player!.play();
                              });
                            },
                            child: AspectRatio(
                              aspectRatio: _player!.value.aspectRatio,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  VideoPlayer(_player!),
                                  if (!_player!.value.isPlaying)
                                    const Icon(
                                      Icons.play_circle_fill,
                                      size: 66,
                                      color: Colors.white,
                                    ),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 210,
                            color: panel,
                            child: const Center(
                              child: Icon(
                                Icons.video_library_outlined,
                                size: 54,
                                color: accent,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                          child: Text(
                            video['title']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            '조회수 ' +
                                (video['views']?.toString() ?? '0') +
                                '  ·  좋아요 ' +
                                (video['likes']?.toString() ?? '0'),
                            style: const TextStyle(color: muted),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Color(0xFF30265F),
                                child: Icon(Icons.person),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      video['creator']?.toString() ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      '구독자 ' +
                                          (video['subscriber_count']?.toString() ??
                                              '0'),
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton.tonal(
                                onPressed: _subscribe,
                                child: Text(
                                  video['is_subscribed'] == true
                                      ? '구독 중'
                                      : '구독',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Wrap(
                            spacing: 10,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _like,
                                icon: Icon(
                                  video['is_liked'] == true
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                ),
                                label: Text(
                                  '좋아요 ' + (video['likes']?.toString() ?? '0'),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () {},
                                icon: const Icon(Icons.share_outlined),
                                label: const Text('공유'),
                              ),
                            ],
                          ),
                        ),
                        if ((video['description']?.toString() ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                            child: Text(video['description'].toString()),
                          ),
                        const Divider(height: 30),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            '댓글 ' + comments.length.toString() + '개',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _comment,
                                  minLines: 1,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    hintText: '댓글 추가...',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                onPressed: _commentBusy ? null : _sendComment,
                                icon: const Icon(Icons.send),
                              ),
                            ],
                          ),
                        ),
                        for (final item in comments)
                          ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(item['username']?.toString() ?? ''),
                            subtitle: Text(item['body']?.toString() ?? ''),
                          ),
                        const SizedBox(height: 30),
                      ],
                    ),
    );
  }
}

class UploadPage extends StatefulWidget {
  final VidShareApi api;

  const UploadPage({super.key, required this.api});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  PlatformFile? _file;
  bool _uploading = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _file = result.files.single);
  }

  Future<void> _upload() async {
    final file = _file;
    if (_title.text.trim().isEmpty) {
      _message('영상 제목을 입력해주세요.');
      return;
    }
    if (file == null || file.path == null) {
      _message('업로드할 영상 파일을 선택해주세요.');
      return;
    }
    setState(() => _uploading = true);
    try {
      await widget.api.uploadVideo(
        path: file.path!,
        filename: file.name,
        title: _title.text.trim(),
        description: _description.text.trim(),
      );
      if (!mounted) return;
      _title.clear();
      _description.clear();
      setState(() => _file = null);
      _message('영상 업로드가 완료되었습니다.');
    } on ApiException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('영상 업로드에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          '영상 업로드',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'PC VidShare와 같은 계정에 영상이 등록됩니다.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: _uploading ? null : _pickVideo,
          icon: const Icon(Icons.video_file_outlined),
          label: Text(_file?.name ?? '영상 파일 선택 (MP4 / WEBM / OGG / MOV)'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          maxLength: 200,
          decoration: const InputDecoration(labelText: '영상 제목'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 5,
          maxLength: 5000,
          decoration: const InputDecoration(labelText: '영상 설명'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _uploading ? null : _upload,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _uploading
              ? const CircularProgressIndicator()
              : const Text('VidShare에 업로드'),
        ),
        const SizedBox(height: 12),
        const Text(
          '서버의 기존 업로드 용량 제한이 적용됩니다. 연결이 불안정하면 Wi-Fi에서 업로드해주세요.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}

class LibraryPage extends StatefulWidget {
  final VidShareApi api;

  const LibraryPage({super.key, required this.api});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _feed = 'mine';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('내 영상'),
                selected: _feed == 'mine',
                onSelected: (_) => setState(() => _feed = 'mine'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('좋아요 표시한 영상'),
                selected: _feed == 'liked',
                onSelected: (_) => setState(() => _feed = 'liked'),
              ),
            ],
          ),
        ),
        Expanded(
          child: VideoFeed(
            key: ValueKey(_feed),
            api: widget.api,
            feed: _feed,
            title: '보관함',
          ),
        ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _MessageState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42, color: muted),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
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
        Text(
          'vidshare',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -.8,
          ),
        ),
      ],
    );
  }
}

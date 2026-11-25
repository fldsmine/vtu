import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';
import 'money.dart';
import 'auth_api.dart';
import '../../services/media_url.dart';
import '../auth/register_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key, required this.api});

  final AuthApi api;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _scrollController = ScrollController();
  final _featuresKey = GlobalKey();
  final _appsKey = GlobalKey();
  final _adsKey = GlobalKey();
  final _storiesKey = GlobalKey();
  final _faqKey = GlobalKey();
  final _contactKey = GlobalKey();
  final _testimonialController = PageController(viewportFraction: .91);

  Map<String, dynamic> _payload = const {};
  bool _loading = true;
  String? _error;
  int _testimonialPage = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _testimonialController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.frontend();
      final data = _asMap(response['data']);
      if (!mounted) return;
      setState(() {
        _payload = data;
        _loading = false;
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'We could not load the TLStore landing page.';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _asMap(Object? value) => value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};

  List<Map<String, dynamic>> _rows(Object? value) => value is List
      ? value.whereType<Map>().map(_asMap).toList()
      : const <Map<String, dynamic>>[];

  Map<String, dynamic> get _banner => _asMap(_payload['banner']);
  Map<String, dynamic> get _contact => _asMap(_payload['contact_info']);
  Map<String, dynamic> get _footerData => _asMap(_payload['footer']);
  List<Map<String, dynamic>> get _apps => _rows(_payload['products']);
  List<Map<String, dynamic>> get _ads => _rows(_payload['ads']);
  List<Map<String, dynamic>> get _testimonies => _rows(_payload['testimonies']);
  List<Map<String, dynamic>> get _stats => _rows(_payload['platform_stats']);
  List<Map<String, dynamic>> get _leaders => _rows(_payload['leaderboard']);

  List<String> get _features {
    final value = _payload['features'];
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[,\n|]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [
      'App reviews',
      'Sponsored sharing',
      'Earn rewards',
      'Referral rewards',
    ];
  }

  List<Map<String, dynamic>> get _faqs {
    final grouped = _asMap(_payload['faqs']);
    final result = <Map<String, dynamic>>[];
    for (final entry in grouped.entries) {
      if (entry.value is List) {
        for (final row in _rows(entry.value)) {
          result.add({...row, 'category': row['category'] ?? entry.key});
        }
      }
    }
    return result;
  }

  String _text(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _image(Object? value) => MediaUrl.resolve(value?.toString()) ?? '';

  Future<void> _scrollTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: .06,
    );
  }

  Future<void> _start() async {
    final action = _text(_banner['cta_link'], '/register');
    final path = action.toLowerCase();
    if (path.startsWith('#')) {
      final key = switch (path.substring(1)) {
        'apps' || 'products' => _appsKey,
        'ads' => _adsKey,
        'faqs' || 'faq' => _faqKey,
        'contact' => _contactKey,
        _ => _featuresKey,
      };
      await _scrollTo(key);
      return;
    }
    final uri = Uri.tryParse(action);
    final routePath = uri?.path.toLowerCase() ?? path;
    if (routePath.endsWith('/register') || routePath == 'register') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const RegisterScreen()),
      );
      return;
    }
    await _openLink(action);
  }

  Future<void> _openLink(String value) async {
    final raw = value.trim();
    if (raw.isEmpty) return;
    Uri? uri = Uri.tryParse(raw);
    if (uri == null) return;
    if (!uri.hasScheme) {
      final base = Uri.parse(ApiConfig.webAppBaseUrl);
      uri = base.resolve(raw.startsWith('/') ? raw : '/$raw');
    }
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This link could not be opened.')),
      );
    }
  }

  Future<void> _showAppDetails(Map<String, dynamic> app) async {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(app['name'], _text(app['title'], 'Featured app')),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _text(app['description'], 'Discover this app on TLStore.'),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 14),
              if (app['rating'] != null)
                Row(
                  children: [
                    Icon(Icons.star_rounded, color: colors.tertiary),
                    const SizedBox(width: 5),
                    Text('${app['rating']}'),
                    const SizedBox(width: 14),
                    Text('${app['total_reviews'] ?? 0} reviews'),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAd(Map<String, dynamic> ad) async {
    final url = _text(ad['destination_url'], '');
    if (url.isNotEmpty) {
      await _openLink(url);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_text(ad['title'], 'Sponsored task')),
        content: Text(_text(ad['description'], 'Explore this sponsored task.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                'TL',
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('TLStore'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Contact support',
            onPressed: () => _scrollTo(_contactKey),
            icon: const Icon(Icons.support_agent_rounded),
          ),
          IconButton(
            tooltip: 'Refresh landing page',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: _loading && _payload.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _payload.isEmpty
              ? _loadError(theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 30),
                    children: [
                      _hero(context),
                      _leaderboardSection(context),
                      _howItWorksSection(context),
                      _featuresSection(context),
                      _appsSection(context),
                      _adsSection(context),
                      _testimonialsSection(context),
                      _statsSection(context),
                      _faqSection(context),
                      _contactSection(context),
                      _footerSection(context),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _loadError(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Landing content is unavailable.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );


  Widget _hero(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final image = _image(_banner['image']);
    final title = _text(_banner['title'], 'Review. Share. Earn.');
    final subtitle = _text(
      _banner['subtitle'],
      'A community marketplace for app feedback and sponsored sharing.',
    );
    final description = _text(
      _banner['description'],
      'Discover opportunities, complete tasks, and earn rewards after approval.',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: SizedBox(
        height: 380,
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(30),
            bottomRight: Radius.circular(30),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image.isNotEmpty)
                Image.network(
                  image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(color: colors.primary),
                )
              else
                ColoredBox(color: colors.primary),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      colors.primary.withValues(alpha: .97),
                      colors.primary.withValues(alpha: .88),
                      colors.primary.withValues(alpha: .38),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: colors.onPrimary.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: colors.onPrimary.withValues(alpha: .25),
                        ),
                      ),
                      child: Text(
                        'REVIEW  ·  SHARE  ·  EARN',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onPrimary.withValues(alpha: .92),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onPrimary.withValues(alpha: .83),
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _text(_banner['cta_text'], 'Get started'),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.onPrimary,
                            foregroundColor: colors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _scrollTo(_appsKey),
                          icon: Icon(
                            Icons.explore_outlined,
                            color: colors.onPrimary,
                          ),
                          label: Text(
                            'Explore tasks',
                            style: TextStyle(color: colors.onPrimary),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: colors.onPrimary.withValues(alpha: .7),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
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
  }

  Widget _sectionHeading(
    BuildContext context,
    String eyebrow,
    String title, {
    String? description,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _statsSection(BuildContext context) {
    if (_stats.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _stats.map((stat) {
              final icon = _statIcon(stat['icon']?.toString());
              return SizedBox(
                width: width,
                child: Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: .55),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: colors.primaryContainer,
                          foregroundColor: colors.onPrimaryContainer,
                          child: Icon(icon, size: 20),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _text(stat['value'], '—'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              Text(
                                _text(stat['label'], 'Platform activity'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  IconData _statIcon(String? key) => switch (key?.toLowerCase()) {
    'users' => Icons.groups_rounded,
    'image' => Icons.task_alt_rounded,
    'dollar' => Icons.savings_rounded,
    'globe' => Icons.public_rounded,
    _ => Icons.insights_rounded,
  };

  Widget _featuresSection(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: _featuresKey,
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            context,
            'Why TLStore',
            'A simple way to take part',
            description:
                'Choose tasks, follow clear steps, and track the outcome.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 9,
              runSpacing: 9,
              children: _features.map((feature) {
                return Chip(
                  avatar: Icon(
                    _featureIcon(feature),
                    size: 17,
                    color: colors.primary,
                  ),
                  label: Text(feature),
                  backgroundColor: colors.primaryContainer.withValues(
                    alpha: .55,
                  ),
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  IconData _featureIcon(String value) {
    final feature = value.toLowerCase();
    if (feature.contains('review')) return Icons.rate_review_rounded;
    if (feature.contains('share') || feature.contains('sponsor')) {
      return Icons.campaign_rounded;
    }
    if (feature.contains('referral')) return Icons.people_alt_rounded;
    if (feature.contains('reward') || feature.contains('earn')) {
      return Icons.account_balance_wallet_rounded;
    }
    if (feature.contains('support')) return Icons.support_agent_rounded;
    return Icons.check_circle_rounded;
  }

  Widget _howItWorksSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final steps = <({IconData icon, String title, String description, Color color})>[
      (
        icon: Icons.person_add_alt_1_rounded,
        title: 'Create your account',
        description: 'Register with your country and set up your TLStore profile.',
        color: colors.primary,
      ),
      (
        icon: Icons.workspace_premium_rounded,
        title: 'Choose a package',
        description: 'Join the package that gives you access to app reviews or sponsored sharing.',
        color: colors.secondary,
      ),
      (
        icon: Icons.task_alt_rounded,
        title: 'Complete a task',
        description: 'Review an app or share a sponsored post, then submit your proof when required.',
        color: colors.tertiary,
      ),
      (
        icon: Icons.account_balance_wallet_rounded,
        title: 'Get approved and earn',
        description: 'Approved work is credited to your wallet. Track your earnings and request a withdrawal.',
        color: colors.primary,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          context,
          'Getting started',
          'How it works',
          description: 'Four clear steps from joining to earning rewards.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
          child: Column(
            children: [
              for (var index = 0; index < steps.length; index++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: steps[index].color.withValues(alpha: .12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: steps[index].color.withValues(alpha: .3),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: steps[index].color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  steps[index].icon,
                                  size: 19,
                                  color: steps[index].color,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    steps[index].title,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              steps[index].description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (index < steps.length - 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(56, 15, 0, 15),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 1,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              steps[index].color.withValues(alpha: .6),
                              colors.outlineVariant.withValues(alpha: .45),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _appsSection(BuildContext context) {
    if (_apps.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: _appsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          context,
          'Discover',
          'Featured apps',
          description: 'Explore apps that are currently featured on TLStore.',
        ),
        SizedBox(
          height: 208,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: _apps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final app = _apps[index];
              final image = _image(app['cover_image']);
              return SizedBox(
                width: 280,
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  child: InkWell(
                    onTap: () => _showAppDetails(app),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _mediaThumb(context, image, Icons.apps_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _text(app['name'], 'Featured app'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _text(app['title'], 'App store'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Text(
                              _text(
                                app['description'],
                                'Tap to learn more about this featured app.',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(height: 1.4),
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 17,
                                color: colors.tertiary,
                              ),
                              const SizedBox(width: 3),
                              Text(_text(app['rating'], 'New')),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => _showAppDetails(app),
                                icon: const Icon(Icons.arrow_forward_rounded),
                                label: const Text('Details'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _adsSection(BuildContext context) {
    if (_ads.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: _adsKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          context,
          'Sponsored sharing',
          'Featured tasks',
          description: 'See a sample of the public sharing opportunities.',
        ),
        SizedBox(
          height: 226,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            scrollDirection: Axis.horizontal,
            itemCount: _ads.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final ad = _ads[index];
              final image = _image(ad['creative_path']);
              final currency = _text(ad['currency'], 'USD');
              final price = double.tryParse(ad['price']?.toString() ?? '') ?? 0;
              return SizedBox(
                width: 285,
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  child: InkWell(
                    onTap: () => _openAd(ad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 104,
                          width: double.infinity,
                          child: image.isEmpty
                              ? ColoredBox(
                                  color: colors.secondaryContainer,
                                  child: Icon(
                                    Icons.campaign_rounded,
                                    size: 38,
                                    color: colors.onSecondaryContainer,
                                  ),
                                )
                              : Image.network(
                                  image,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => ColoredBox(
                                    color: colors.secondaryContainer,
                                    child: Icon(
                                      Icons.campaign_rounded,
                                      color: colors.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _text(ad['title'], 'Sponsored task'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _text(
                                  ad['description'],
                                  'Share this campaign publicly.',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    formatMajorMoney(price, currency),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: colors.primary,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    size: 17,
                                    color: colors.primary,
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
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _mediaThumb(BuildContext context, String url, IconData fallback) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        width: 58,
        height: 58,
        child: url.isEmpty
            ? ColoredBox(
                color: colors.primaryContainer,
                child: Icon(fallback, color: colors.onPrimaryContainer),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: colors.primaryContainer,
                  child: Icon(fallback, color: colors.onPrimaryContainer),
                ),
              ),
      ),
    );
  }

  Widget _testimonialsSection(BuildContext context) {
    if (_testimonies.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      key: _storiesKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          context,
          'Member stories',
          'What members say',
          trailing: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Previous story',
                onPressed: _testimonialPage == 0
                    ? null
                    : () => _testimonialController.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Next story',
                onPressed: _testimonialPage >= _testimonies.length - 1
                    ? null
                    : () => _testimonialController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 230,
          child: PageView.builder(
            controller: _testimonialController,
            itemCount: _testimonies.length,
            onPageChanged: (index) => setState(() => _testimonialPage = index),
            itemBuilder: (context, index) {
              final review = _testimonies[index];
              final avatar = _image(review['avatar']);
              final rating = (review['rating'] as num?)?.toInt() ?? 5;
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 8, 8),
                child: Card(
                  elevation: 0,
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: List.generate(
                            rating.clamp(0, 5).toInt(),
                            (_) => Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: colors.tertiary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Text(
                            '“${_text(review['content'], 'A great experience with TLStore.')}”',
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: colors.primaryContainer,
                              foregroundImage: avatar.isEmpty
                                  ? null
                                  : NetworkImage(avatar),
                              child: avatar.isEmpty
                                  ? Icon(
                                      Icons.person_rounded,
                                      color: colors.onPrimaryContainer,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _text(review['name'], 'TLStore member'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _leaderboardSection(BuildContext context) {
    if (_leaders.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasPodium = _leaders.length >= 3;
    final remaining = hasPodium ? _leaders.skip(3).take(4).toList() : _leaders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          context,
          'Community',
          'Leaderboard',
          description: 'Meet the members completing the most tasks.',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.emoji_events_rounded, size: 15, color: colors.tertiary),
                const SizedBox(width: 5),
                Text(
                  'Top members',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onTertiaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                if (hasPodium) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _leaderPodiumItem(
                          context,
                          _leaders[1],
                          rank: 2,
                          medal: const Color(0xFF9DA9B4),
                          blockHeight: 48,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _leaderPodiumItem(
                          context,
                          _leaders[0],
                          rank: 1,
                          medal: const Color(0xFFE9B949),
                          blockHeight: 68,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _leaderPodiumItem(
                          context,
                          _leaders[2],
                          rank: 3,
                          medal: const Color(0xFFCD8A52),
                          blockHeight: 40,
                        ),
                      ),
                    ],
                  ),
                  if (remaining.isNotEmpty) const SizedBox(height: 12),
                ],
                for (var index = 0; index < remaining.length; index++)
                  _leaderRow(
                    context,
                    remaining[index],
                    hasPodium ? index + 3 : index,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _leaderPodiumItem(
    BuildContext context,
    Map<String, dynamic> leader,
    {required int rank,
    required Color medal,
    required double blockHeight,}
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = _asMap(leader['user']);
    final avatar = _image(user['avatar']);
    final name = _text(user['full_name'], _text(user['username'], 'Member'));
    final firstName = name.split(RegExp(r'\s+')).first;
    final score = _leaderScore(leader);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rank == 1)
          Icon(Icons.workspace_premium_rounded, color: medal, size: 20),
        CircleAvatar(
          radius: rank == 1 ? 25 : 21,
          backgroundColor: medal.withValues(alpha: .2),
          foregroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
          child: avatar.isEmpty
              ? Text(
                  firstName.isEmpty ? '?' : firstName[0].toUpperCase(),
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 5),
        Text(
          firstName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '$score tasks',
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: blockHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [medal.withValues(alpha: .35), medal.withValues(alpha: .12)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          alignment: Alignment.center,
          child: Text(
            '#$rank',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _leaderRow(
    BuildContext context,
    Map<String, dynamic> leader,
    int index,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = _asMap(leader['user']);
    final avatar = _image(user['avatar']);
    final name = _text(user['full_name'], _text(user['username'], 'Member'));
    final rank = int.tryParse(leader['rank']?.toString() ?? '') ?? index + 1;
    final reviews = int.tryParse(leader['total_review']?.toString() ?? '') ?? 0;
    final shares = int.tryParse(leader['total_share']?.toString() ?? '') ?? 0;
    final score = _leaderScore(leader);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#$rank',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          CircleAvatar(
            radius: 17,
            backgroundColor: colors.primaryContainer,
            foregroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
            child: avatar.isEmpty
                ? Icon(Icons.person_rounded, size: 18, color: colors.onPrimaryContainer)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$reviews reviews · $shares shares',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${formatGroupedNumber(score, 0)} tasks',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.secondary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  int _leaderScore(Map<String, dynamic> leader) {
    final explicit = int.tryParse(leader['total_score']?.toString() ?? '');
    if (explicit != null) return explicit;
    final reviews = int.tryParse(leader['total_review']?.toString() ?? '') ?? 0;
    final shares = int.tryParse(leader['total_share']?.toString() ?? '') ?? 0;
    return reviews + shares;
  }

  Widget _faqSection(BuildContext context) {
    final faqs = _faqs;
    if (faqs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      key: _faqKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          context,
          'Helpful answers',
          'Frequently asked questions',
          description: 'Tap a question to read the answer.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                for (var index = 0; index < faqs.length; index++)
                  ExpansionTile(
                    key: PageStorageKey(
                      'landing-faq-${faqs[index]['id'] ?? index}',
                    ),
                    title: Text(
                      _text(faqs[index]['question'], 'How does TLStore work?'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: faqs[index]['category'] == null
                        ? null
                        : Text(_label(faqs[index]['category'].toString())),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _text(faqs[index]['answer'], ''),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  String _label(String value) => value
      .split(RegExp(r'[_\-\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Widget _contactSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final social = _asMap(_contact['social_links']);
    final email = _text(_contact['email'], '');
    final phone = _text(_contact['phone'], '');
    final address = _text(_contact['address'], '');
    final supportLinks = _payload['support_link'] is List
        ? (_payload['support_link'] as List)
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList()
        : const <String>[];
    final socials = social.entries
        .where(
          (entry) =>
              entry.value != null && entry.value.toString().trim().isNotEmpty,
        )
        .toList();

    return Column(
      key: _contactKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          context,
          'We’re here for you',
          'Get in touch',
          description:
              'Reach the TLStore team or follow our community channels.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: colors.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: Column(
              children: [
                if (email.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.email_outlined, color: colors.primary),
                    title: const Text('Email'),
                    subtitle: Text(email),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => _openLink('mailto:$email'),
                  ),
                if (phone.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.phone_outlined, color: colors.primary),
                    title: const Text('Phone'),
                    subtitle: Text(phone),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => _openLink('tel:$phone'),
                  ),
                if (address.isNotEmpty)
                  ListTile(
                    leading: Icon(
                      Icons.location_on_outlined,
                      color: colors.primary,
                    ),
                    title: const Text('Address'),
                    subtitle: Text(address),
                  ),
                if (email.isEmpty && phone.isEmpty && address.isEmpty)
                  ListTile(
                    leading: Icon(
                      Icons.support_agent_rounded,
                      color: colors.primary,
                    ),
                    title: const Text('Contact TLStore support'),
                    subtitle: const Text('Open a support channel for help.'),
                    onTap: supportLinks.isEmpty
                        ? null
                        : () => _openLink(supportLinks.first),
                  ),
                if (socials.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: socials.map((entry) {
                        return OutlinedButton.icon(
                          onPressed: () => _openLink(entry.value.toString()),
                          icon: Icon(_socialIcon(entry.key)),
                          label: Text(_label(entry.key)),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (supportLinks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < supportLinks.length; index++)
                  FilledButton.tonalIcon(
                    onPressed: () => _openLink(supportLinks[index]),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(index == 0 ? 'Join community' : 'Get support'),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  IconData _socialIcon(String value) => switch (value.toLowerCase()) {
    'facebook' => Icons.facebook_rounded,
    'instagram' => Icons.camera_alt_rounded,
    'twitter' || 'x' => Icons.alternate_email_rounded,
    'telegram' => Icons.send_rounded,
    'tiktok' => Icons.music_note_rounded,
    _ => Icons.public_rounded,
  };

  Widget _footerSection(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final copyright = _text(
      _footerData['copyright'],
      '© TLStore. All rights reserved.',
    );
    final note = _text(_footerData['note'], 'Review • Share • Earn');
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            copyright,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            note,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () =>
                    _openLink('${ApiConfig.webAppBaseUrl}/privacy'),
                child: const Text('Privacy'),
              ),
              TextButton(
                onPressed: () => _openLink('${ApiConfig.webAppBaseUrl}/terms'),
                child: const Text('Terms'),
              ),
              TextButton(
                onPressed: () => _scrollTo(_contactKey),
                child: const Text('Support'),
              ),
            ],
          ),
          if (_footerData['version'] != null) ...[
            const SizedBox(height: 2),
            Text(
              'Version ${_footerData['version']}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../data/local/session_persistence.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/checkout_verification.dart';
import '../../data/models/opening_hours.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../data/repositories/opening_hours_repository.dart';
import '../admin/admin_dashboard_screen.dart';
import '../orders/order_list_screen.dart';
import '../orders/order_tracking_screen.dart';
import '../shared/opening_hours_banner.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _backgroundAsset =
      'assets/images/background_big_ingredients_darker.png';
  static const _apiBaseUrl = AppConfig.apiBaseUrl;
  static final CheckoutRepository _checkoutRepository = HttpCheckoutRepository(
    apiBaseUrl: _apiBaseUrl,
  );
  static final OpeningHoursRepository _openingHoursRepository =
      OpeningHoursRepository(
    apiBaseUrl: _apiBaseUrl,
  );

  late Future<List<Map<String, dynamic>>> _positionsFuture;
  late Future<OpeningHoursData?> _openingHoursFuture;
  AuthSession _authSession = const AuthSession();
  String? _authSessionKey;
  final List<_CartEntry> _cart = [];
  CheckoutVerificationResponse? _activeCheckout;
  bool _isLoadingActiveCheckout = false;
  int _activeFooterIndex = 1;
  int _loyaltyPoints = 0;

  @override
  void initState() {
    super.initState();
    _positionsFuture = _fetchPositions();
    _openingHoursFuture = _fetchOpeningHours();
    final storedAuthSession = SessionPersistence.loadAuthSessionSync();
    final storedCheckout = SessionPersistence.loadActiveCheckoutSync();
    final cachedCheckout = _checkoutRepository.cachedActiveCheckout;

    if (storedAuthSession?.hasIdentity == true) {
      _authSession = storedAuthSession!;
      _authSessionKey = _authSessionStorageKey(_authSession);
      _loyaltyPoints = _authSession.loyaltyPoints;
    }

    final initialCheckout = storedCheckout ?? cachedCheckout;
    if (_isCheckoutStillActive(initialCheckout)) {
      _activeCheckout = initialCheckout;
      _checkoutRepository.rememberActiveCheckout(initialCheckout);
    }

    if (_authSession.hasIdentity) {
      _loadActiveCheckout();
      _loadLoyaltyPoints();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAuthSessionFromRoute();
  }

  Future<List<Map<String, dynamic>>> _fetchPositions() async {
    final response = await http.get(Uri.parse('$_apiBaseUrl/positions'),
        headers: const {
          'Accept': 'application/json'
        }).timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /positions.');
    }

    return decoded
        .map((item) => item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map))
        .toList();
  }

  void _reload() {
    setState(() {
      _positionsFuture = _fetchPositions();
      _openingHoursFuture = _fetchOpeningHours();
    });
    _loadActiveCheckout();
    _loadLoyaltyPoints();
  }

  Future<OpeningHoursData?> _fetchOpeningHours() async {
    try {
      return await _openingHoursRepository.fetchOpeningHours();
    } catch (_) {
      return null;
    }
  }

  void _syncAuthSessionFromRoute() {
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final authSession = AuthSession.fromRouteArgs(routeArgs);
    final routedCheckout = _activeCheckoutFromRoute(routeArgs);
    final sessionKey = _authSessionStorageKey(authSession);

    if (routedCheckout != null && _isCheckoutStillActive(routedCheckout)) {
      _activeCheckout = routedCheckout;
      _checkoutRepository.rememberActiveCheckout(routedCheckout);
      SessionPersistence.saveActiveCheckout(routedCheckout);
    }

    if (!authSession.hasIdentity && _authSession.hasIdentity) {
      return;
    }

    if (_authSessionKey == sessionKey) {
      if (_loyaltyPoints != authSession.loyaltyPoints) {
        setState(() {
          _authSession = authSession;
          _loyaltyPoints = authSession.loyaltyPoints;
        });
      }
      return;
    }

    _authSession = authSession;
    _authSessionKey = sessionKey;
    _loyaltyPoints = authSession.loyaltyPoints;
    if (authSession.hasIdentity) {
      SessionPersistence.saveAuthSession(authSession);
    }
    _loadActiveCheckout();
    _loadLoyaltyPoints();
  }

  String _authSessionStorageKey(AuthSession authSession) {
    return '${authSession.email ?? ''}|${authSession.sessionToken ?? ''}|${authSession.jwt ?? ''}|${authSession.normalizedRole ?? ''}|${authSession.loyaltyPoints}';
  }

  Future<void> _loadLoyaltyPoints() async {
    final email = _authSession.email?.trim();
    if (!_authSession.hasIdentity || email == null || email.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loyaltyPoints = 0;
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/get_user/${Uri.encodeComponent(email)}'),
        headers: const {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final loyaltyPoints = _asInt(decoded['loyalty_points']) ?? 0;
      final updatedSession = _authSession.copyWith(
        role: decoded['role']?.toString(),
        loyaltyPoints: loyaltyPoints,
      );
      await SessionPersistence.saveAuthSession(updatedSession);

      if (!mounted) {
        return;
      }

      setState(() {
        _authSession = updatedSession;
        _authSessionKey = _authSessionStorageKey(updatedSession);
        _loyaltyPoints = loyaltyPoints;
      });
    } catch (_) {
      // Keep the locally cached point balance when the backend is temporarily unavailable.
    }
  }

  Future<void> _loadActiveCheckout() async {
    if (!_authSession.hasIdentity) {
      final existingCheckout =
          _activeCheckout ?? _checkoutRepository.cachedActiveCheckout;
      if (mounted) {
        setState(() {
          _activeCheckout = _isCheckoutStillActive(existingCheckout)
              ? existingCheckout
              : null;
          _isLoadingActiveCheckout = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingActiveCheckout = true;
      });
    }

    try {
      final activeCheckout = await _checkoutRepository.fetchActiveCheckout(
        sessionToken: _authSession.sessionToken,
        email: _authSession.email,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _activeCheckout = activeCheckout;
        _isLoadingActiveCheckout = false;
      });
      SessionPersistence.saveActiveCheckout(activeCheckout);
    } catch (_) {
      final existingCheckout =
          _activeCheckout ?? _checkoutRepository.cachedActiveCheckout;
      if (!mounted) {
        return;
      }

      setState(() {
        _activeCheckout =
            _isCheckoutStillActive(existingCheckout) ? existingCheckout : null;
        _isLoadingActiveCheckout = false;
      });
    }
  }

  CheckoutVerificationResponse? _activeCheckoutFromRoute(Object? args) {
    if (args is! Map) {
      return null;
    }

    final activeCheckoutJson = args['activeCheckout'];
    if (activeCheckoutJson is Map<String, dynamic>) {
      return CheckoutVerificationResponse.fromJson(activeCheckoutJson);
    }
    if (activeCheckoutJson is Map) {
      return CheckoutVerificationResponse.fromJson(
        Map<String, dynamic>.from(activeCheckoutJson),
      );
    }
    return null;
  }

  bool _isCheckoutStillActive(CheckoutVerificationResponse? checkout) {
    final activeUntil = checkout?.activeUntil;
    if (checkout == null) {
      return false;
    }
    if (activeUntil == null) {
      return true;
    }
    return activeUntil.isAfter(DateTime.now().toUtc());
  }

  Future<void> _openActiveOrder() async {
    final activeCheckout = _activeCheckout;
    if (activeCheckout == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderTrackingScreen(
          checkout: activeCheckout,
          authSession: _authSession,
          checkoutRepository: _checkoutRepository,
        ),
      ),
    );

    if (mounted) {
      _loadActiveCheckout();
    }
  }

  Future<void> _showRewardsDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF181311),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Nagrody i punkty',
          style: TextStyle(
            color: Color(0xFFF8EEE7),
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          _loyaltyPoints > 0
              ? 'Masz obecnie $_loyaltyPoints pkt. Punkty mozesz wykorzystac przy zamowieniu. 10 pkt = 1 PLN, a maksymalnie oplacisz nimi 30% wartosci koszyka.'
              : 'Punkty mozesz wykorzystac przy zamowieniu. 10 pkt = 1 PLN, a maksymalnie oplacisz nimi 30% wartosci koszyka.',
          style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFD8C7BA),
                height: 1.4,
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Zamknij',
              style: TextStyle(
                color: Color(0xFFFFA247),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfileOrders() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderListScreen(
          authSession: _authSession,
          checkoutRepository: _checkoutRepository,
          activeCheckout: _activeCheckout,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    _loadActiveCheckout();
    _loadLoyaltyPoints();
  }

  void _selectPosition(Map<String, dynamic> position) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _ProductPreviewDialog(
        position: position,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _removeFromCart(int cartEntryId) {
    setState(() {
      _cart.removeWhere((entry) => entry.id == cartEntryId);
    });
  }

  void _replaceCart(List<_CartEntry> entries) {
    setState(() {
      _cart
        ..clear()
        ..addAll(entries);
    });
  }

  void _openCartSummary() {
    if (_cart.isEmpty || _activeCheckout != null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CartSummaryScreen(
          initialEntries: _resolvedCartEntries(const <Map<String, dynamic>>[]),
          onCartChanged: _replaceCart,
          authSession: _authSession,
        ),
      ),
    );
  }

  Future<void> _openCategoryView(
    _DashboardCategory category,
    List<Map<String, dynamic>> positions,
  ) async {
    final resolvedCartEntries = _resolvedCartEntries(positions);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
      builder: (_) => _CategoryProductsScreen(
          categories: _buildDashboardCategories(positions),
          initialCategoryKey: category.key,
          initialCartEntries: resolvedCartEntries,
          authSession: _authSession,
          hasActiveCheckout: _activeCheckout != null &&
              _isCheckoutStillActive(_activeCheckout),
          onCartChanged: _replaceCart,
        ),
      ),
    );
  }

  List<_CartEntry> _resolvedCartEntries(List<Map<String, dynamic>> positions) {
    return _cart.map((entry) {
      for (final position in positions) {
        if (_samePosition(entry.position, position)) {
          return entry.copyWith(position: position);
        }
      }
      return entry;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_authSession.isStaff) {
      return AdminDashboardScreen(authSession: _authSession);
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _positionsFuture,
      builder: (context, snapshot) {
        final positions = snapshot.data ?? const <Map<String, dynamic>>[];
        final cartEntries = _resolvedCartEntries(positions);
        final dashboardCategories = _buildDashboardCategories(positions);
        final hasBottomModule = _activeCheckout != null ||
            cartEntries.isNotEmpty ||
            (_isLoadingActiveCheckout && cartEntries.isEmpty);

        Widget body;
        if (snapshot.connectionState != ConnectionState.done) {
          body = const Center(
              child: CircularProgressIndicator(color: Color(0xFFE97F2A)));
        } else if (snapshot.hasError) {
          body = _StateCard(
            icon: Icons.wifi_off_rounded,
            title: 'Nie udalo sie pobrac pozycji',
            message: snapshot.error.toString(),
            buttonLabel: 'Sprobuj ponownie',
            onPressed: _reload,
          );
        } else if (positions.isEmpty) {
          body = const _StateCard(
            icon: Icons.fastfood_outlined,
            title: 'Menu jest puste',
            message:
                'Gdy backend zwroci dane z /positions, dashboard automatycznie uzupelni kategorie i koszyk.',
          );
        } else {
          body = SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _positionsFuture;
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding =
                      constraints.maxWidth >= 720 ? 18.0 : 14.0;
                  final crossAxisCount = constraints.maxWidth >= 980 ? 3 : 2;
                  final childAspectRatio =
                      constraints.maxWidth >= 980 ? 0.92 : 0.82;

                  return ListView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      18,
                      horizontalPadding,
                      hasBottomModule ? 206 : 110,
                    ),
                    children: [
                      FutureBuilder<OpeningHoursData?>(
                        future: _openingHoursFuture,
                        builder: (context, openingHoursSnapshot) {
                          final openingHours = openingHoursSnapshot.data;
                          if (openingHours == null) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            children: [
                              OpeningHoursBanner(hours: openingHours),
                              const SizedBox(height: 12),
                            ],
                          );
                        },
                      ),
                      _CategoryBlock(
                        categories: dashboardCategories,
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: childAspectRatio,
                        onCategoryTap: (category) =>
                            _openCategoryView(category, positions),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        }

        return Scaffold(
          extendBody: true,
          body: _Background(child: body),
          bottomNavigationBar: _BottomChrome(
            cartEntries: cartEntries,
            activeCheckout: _activeCheckout,
            isLoadingActiveCheckout: _isLoadingActiveCheckout,
            activeFooterIndex: _activeFooterIndex,
            onSelect: _selectPosition,
            onRemove: _removeFromCart,
            onContinue: _openCartSummary,
            onOpenActiveOrder: _openActiveOrder,
            loyaltyPoints: _loyaltyPoints,
            onFooterTap: (index, label) {
              setState(() => _activeFooterIndex = index);
              if (label == 'Nagrody') {
                _showRewardsDialog();
                return;
              }
              if (label == 'Profil') {
                _openProfileOrders();
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label jest w przygotowaniu.')),
              );
            },
          ),
        );
      },
    );
  }
}

class _Background extends StatelessWidget {
  const _Background({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
            image: AssetImage(_DashboardScreenState._backgroundAsset),
            fit: BoxFit.cover),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xF1090808), Color(0xEC080706), Color(0xFF050505)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -10,
              child: _Glow(size: 150, color: const Color(0x28FF6A00)),
            ),
            Positioned(
              bottom: 130,
              left: -20,
              child: _Glow(size: 110, color: const Color(0x18E63946)),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.categories,
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.onCategoryTap,
  });

  final List<_DashboardCategory> categories;
  final int crossAxisCount;
  final double childAspectRatio;
  final ValueChanged<_DashboardCategory> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, index) => _CategoryTile(
        category: categories[index],
        onTap: categories[index].items.isEmpty
            ? null
            : () => onCategoryTap(categories[index]),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onTap,
  });

  final _DashboardCategory category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewItem = category.items.isEmpty ? null : category.items.first;
    final previewTitle = category.title;
    final previewPhoto = _categoryPreviewPhoto(
      category: category,
      previewItem: previewItem,
    );
    final categoryEtaLabel = _categoryEtaLabel(category);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF151210),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x20FFFFFF)),
            boxShadow: [
              BoxShadow(
                color: category.endColor.withValues(alpha: 0.26),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (previewPhoto != null)
                _PositionImage(
                  photoUrl: previewPhoto,
                  title: previewTitle,
                  fit: category.key == 'lody' ? BoxFit.contain : BoxFit.cover,
                  alignment: category.key == 'lody'
                      ? Alignment.topCenter
                      : Alignment.center,
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      category.startColor.withValues(alpha: 0.34),
                      const Color(0xA8100E0E),
                      const Color(0xF4151111),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0, 0.48, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (categoryEtaLabel != null)
                      Align(
                        alignment: Alignment.topRight,
                        child: _CategoryEtaBadge(
                          label: categoryEtaLabel,
                        ),
                      ),
                    const Spacer(),
                    Text(
                      category.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFFFF5EF),
                        fontWeight: FontWeight.w900,
                        height: 1.02,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _categorySubtitle(category.key),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFE6D7CC),
                        height: 1.28,
                      ),
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
}

String? _categoryPreviewPhoto({
  required _DashboardCategory category,
  required Map<String, dynamic>? previewItem,
}) {
  switch (category.key) {
    case 'zapiekanki':
    case 'kids':
      return 'assets/images/zapMeat.png';
    case 'udka':
      return 'assets/images/chickenLeg.png';
    default:
      return previewItem == null ? null : _photo(previewItem);
  }
}

class _CategoryProductsScreen extends StatefulWidget {
  const _CategoryProductsScreen({
    required this.categories,
    required this.initialCategoryKey,
    required this.initialCartEntries,
    required this.authSession,
    required this.hasActiveCheckout,
    required this.onCartChanged,
  });

  final List<_DashboardCategory> categories;
  final String initialCategoryKey;
  final List<_CartEntry> initialCartEntries;
  final AuthSession authSession;
  final bool hasActiveCheckout;
  final ValueChanged<List<_CartEntry>> onCartChanged;

  @override
  State<_CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<_CategoryProductsScreen> {
  late String _selectedCategoryKey;
  late List<_CartEntry> _entries;
  _UdkaPickupEstimate? _udkaPickupEstimate;
  int _nextCartEntryId = 1;
  int _activeFooterIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedCategoryKey = widget.initialCategoryKey;
    _entries = List<_CartEntry>.from(widget.initialCartEntries);
    _nextCartEntryId = _entries.fold<int>(
          0,
          (maxId, entry) => entry.id > maxId ? entry.id : maxId,
        ) +
        1;
    _refreshUdkaPickupEstimate();
  }

  _DashboardCategory get _selectedCategory {
    for (final category in widget.categories) {
      if (category.key == _selectedCategoryKey) {
        return category;
      }
    }
    return widget.categories.first;
  }

  int _quantityFor(Map<String, dynamic> position) {
    var count = 0;
    for (final entry in _entries) {
      if (_samePosition(entry.position, position)) {
        count++;
      }
    }
    return count;
  }

  void _syncCart() {
    widget.onCartChanged(List<_CartEntry>.from(_entries));
  }

  Future<void> _refreshUdkaPickupEstimate() async {
    if (!_containsUdkaCartEntries(_entries)) {
      if (mounted && _udkaPickupEstimate != null) {
        setState(() => _udkaPickupEstimate = null);
      }
      return;
    }

    try {
      final estimate = await _fetchUdkaPickupEstimateForEntries(_entries);
      if (!mounted) {
        return;
      }
      setState(() => _udkaPickupEstimate = estimate);
    } catch (_) {
      if (mounted) {
        setState(() => _udkaPickupEstimate = null);
      }
    }
  }

  void _addToCart(Map<String, dynamic> position) {
    if (!_isPositionAvailable(position)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ta pozycja jest chwilowo niedostepna. Wroc do niej pozniej.',
          ),
        ),
      );
      return;
    }

    if (widget.hasActiveCheckout) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Masz aktywne zamowienie. Poczekaj na jego zakonczenie, zanim dodasz kolejne pozycje.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _entries.add(
        _CartEntry(
          id: _nextCartEntryId++,
          position: position,
          customization: _initialCustomizationFor(position),
        ),
      );
    });
    _syncCart();
    _refreshUdkaPickupEstimate();
  }

  void _removeFromCart(Map<String, dynamic> position) {
    final index =
        _entries.indexWhere((entry) => _samePosition(entry.position, position));
    if (index < 0) {
      return;
    }

    setState(() {
      _entries.removeAt(index);
    });
    _syncCart();
    _refreshUdkaPickupEstimate();
  }

  void _removeEntryById(int id) {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index < 0) {
      return;
    }

    setState(() {
      _entries.removeAt(index);
    });
    _syncCart();
    _refreshUdkaPickupEstimate();
  }

  void _openProductPreview(Map<String, dynamic> position) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _ProductPreviewDialog(
        position: position,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  int _estimatedPrepMinutesForEntries() {
    final prepMinutes = _entries
        .map((entry) => _prepMinutes(entry.position))
        .whereType<int>()
        .where((minutes) => minutes > 0)
        .toList(growable: false);

    if (prepMinutes.isEmpty) {
      return 15;
    }

    return prepMinutes.reduce(math.max);
  }

  String _liveCartEtaLabelForEntries() {
    if (_containsUdkaCartEntries(_entries)) {
      final estimate = _udkaPickupEstimate;
      if (estimate != null) {
        return _formatScheduledPickupCompact(estimate.scheduledPickupAt);
      }
      return _udkaPickupCompactLabel();
    }
    return '${_estimatedPrepMinutesForEntries()} min';
  }

  Future<void> _openCartSummary() async {
    if (_entries.isEmpty || widget.hasActiveCheckout) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CartSummaryScreen(
          initialEntries: List<_CartEntry>.from(_entries),
          onCartChanged: (entries) {
            if (!mounted) {
              return;
            }
            setState(() {
              _entries = List<_CartEntry>.from(entries);
              _nextCartEntryId = _entries.fold<int>(
                    0,
                    (maxId, entry) => entry.id > maxId ? entry.id : maxId,
                  ) +
                  1;
            });
            _syncCart();
            _refreshUdkaPickupEstimate();
          },
          authSession: widget.authSession,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    _refreshUdkaPickupEstimate();
  }

  @override
  Widget build(BuildContext context) {
    final category = _selectedCategory;
    final items = category.items;
    final itemCountLabel =
        items.length == 1 ? '1 produkt' : '${items.length} produktow';
    final hasLiveCart = _entries.isNotEmpty;

    return Scaffold(
      extendBody: true,
      body: _Background(
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(14, 14, 14, hasLiveCart ? 186 : 110),
            children: [
              Row(
                children: [
                  _IconCircle(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Menu',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFFF8EEE7),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _DashboardHomeTab(
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    for (var index = 0;
                        index < widget.categories.length;
                        index++) ...[
                      _CategoryViewTab(
                        category: widget.categories[index],
                        selected: widget.categories[index].key ==
                            _selectedCategoryKey,
                        onTap: widget.categories[index].items.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _selectedCategoryKey =
                                      widget.categories[index].key;
                                });
                              },
                      ),
                      if (index < widget.categories.length - 1)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: const Color(0xD82B2827),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x1EFFFFFF)),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: Column(
                    key: ValueKey<String>(_selectedCategoryKey),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  category.startColor,
                                  category.endColor
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              category.icon,
                              color: const Color(0xFFFFF0E6),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: const Color(0xFFF8EEE7),
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$itemCountLabel • ${_categorySubtitle(category.key)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xCCCFBBAE),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (items.isEmpty)
                        const _StateCard(
                          icon: Icons.inventory_2_outlined,
                          title: 'Brak produktow w tej kategorii',
                          message:
                              'Gdy backend zwroci pozycje dla tej kategorii, lista pojawi sie tutaj.',
                        )
                      else
                        for (var index = 0; index < items.length; index++) ...[
                          _CategoryProductRow(
                            position: items[index],
                            quantity: _quantityFor(items[index]),
                            onTap: () => _openProductPreview(items[index]),
                            onIncrement: () => _addToCart(items[index]),
                            onDecrement: () => _removeFromCart(items[index]),
                            locked: widget.hasActiveCheckout ||
                                !_isPositionAvailable(items[index]),
                          ),
                          if (index < items.length - 1)
                            const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasLiveCart) ...[
                _CartOverviewBar(
                  entries: _entries,
                  etaLabel: _liveCartEtaLabelForEntries(),
                  onSelect: _openProductPreview,
                  onRemove: _removeEntryById,
                  onContinue: _openCartSummary,
                ),
                const SizedBox(height: 8),
              ],
              _DashboardFooterBar(
                activeIndex: _activeFooterIndex,
                onTap: (index, label) {
                  if (index == 0) {
                    Navigator.of(context).pop();
                    return;
                  }
                  setState(() => _activeFooterIndex = index);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label jest w przygotowaniu.')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryViewTab extends StatelessWidget {
  const _CategoryViewTab({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _DashboardCategory category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? category.startColor : const Color(0xFF2A2522),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? const Color(0x66FFF1E7) : const Color(0x20FFFFFF),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: category.endColor.withValues(alpha: 0.26),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Text(
            category.title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFFFF4ED),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

class _DashboardHomeTab extends StatelessWidget {
  const _DashboardHomeTab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1816),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x20FFFFFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.grid_view_rounded,
                size: 16,
                color: Color(0xFFF6E7D9),
              ),
              const SizedBox(width: 8),
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFFFFF4ED),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryProductRow extends StatelessWidget {
  const _CategoryProductRow({
    required this.position,
    required this.quantity,
    required this.onTap,
    required this.onIncrement,
    required this.onDecrement,
    required this.locked,
  });

  final Map<String, dynamic> position;
  final int quantity;
  final VoidCallback onTap;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final isAvailable = _isPositionAvailable(position);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1716),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x16FFFFFF)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 82,
                  height: 82,
                  child: _PositionImage(
                    photoUrl: _photo(position),
                    title: _title(position, 0),
                    fit: _positionImageFit(position),
                    alignment: _positionImageAlignment(position),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(position, 0),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFFF7EEE7),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (_isFrozenPosition(position)) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: const [
                          _ProductStateBadge(label: 'MROZONE'),
                          _ProductStateBadge(label: 'DO ODGRZANIA'),
                        ],
                      ),
                    ],
                    if (!isAvailable) ...[
                      const SizedBox(height: 6),
                      const _ProductStateBadge(
                        label: 'CHWILOWO NIEDOSTEPNE',
                        tone: _ProductStateBadgeTone.warning,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _description(position),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFD1C0B5),
                            height: 1.3,
                          ),
                    ),
                    const SizedBox(height: 8),
                    _PrepTimeBadge(
                      minutes: _prepMinutesOrFallback(position),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _kcal(position),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFFB59E90),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _priceLabel(position),
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: const Color(0xFFF4DDCE),
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _CategoryRowStepper(
                quantity: quantity,
                locked: locked,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRowStepper extends StatelessWidget {
  const _CategoryRowStepper({
    required this.quantity,
    required this.locked,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final bool locked;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF282220),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CategoryStepperButton(
            icon: Icons.remove_rounded,
            onTap: quantity <= 0 || locked ? null : onDecrement,
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFF8EEE7),
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          _CategoryStepperButton(
            icon: Icons.add_rounded,
            onTap: locked ? null : onIncrement,
          ),
        ],
      ),
    );
  }
}

class _CategoryStepperButton extends StatelessWidget {
  const _CategoryStepperButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color:
              onTap == null ? const Color(0xFF221D1B) : const Color(0xFF38302C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 18,
          color:
              onTap == null ? const Color(0xFF7B6F68) : const Color(0xFFF7EEE7),
        ),
      ),
    );
  }
}

class _DashboardFooterBar extends StatelessWidget {
  const _DashboardFooterBar({
    required this.activeIndex,
    required this.onTap,
  });

  final int activeIndex;
  final void Function(int index, String label) onTap;

  @override
  Widget build(BuildContext context) {
    const footer = [
      (Icons.receipt_long_outlined, 'Menu'),
      (Icons.emoji_events_outlined, 'Nagrody'),
      (Icons.person_rounded, 'Profil')
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xEE3B3837),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < footer.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onTap(i, footer[i].$2),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        footer[i].$1,
                        color: activeIndex == i
                            ? const Color(0xFFFFF0E7)
                            : const Color(0xFFCEC3BC),
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        footer[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: activeIndex == i
                                  ? const Color(0xFFFFF0E7)
                                  : const Color(0xFFCEC3BC),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomChrome extends StatelessWidget {
  const _BottomChrome({
    required this.cartEntries,
    required this.activeCheckout,
    required this.isLoadingActiveCheckout,
    required this.activeFooterIndex,
    required this.onSelect,
    required this.onRemove,
    required this.onContinue,
    required this.onOpenActiveOrder,
    required this.loyaltyPoints,
    required this.onFooterTap,
  });

  final List<_CartEntry> cartEntries;
  final CheckoutVerificationResponse? activeCheckout;
  final bool isLoadingActiveCheckout;
  final int activeFooterIndex;
  final int loyaltyPoints;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<int> onRemove;
  final VoidCallback onContinue;
  final VoidCallback onOpenActiveOrder;
  final void Function(int index, String label) onFooterTap;

  @override
  Widget build(BuildContext context) {
    final footer = [
      (Icons.receipt_long_outlined, 'Menu'),
      (Icons.emoji_events_outlined, 'Nagrody'),
      (Icons.person_rounded, 'Profil')
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (activeCheckout != null)
              _ActiveOrderBar(
                checkout: activeCheckout!,
                onTap: onOpenActiveOrder,
              )
            else if (isLoadingActiveCheckout && cartEntries.isEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                  color: const Color(0xE2272220),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x2BFFFFFF)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF48D77C),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sprawdzamy, czy masz aktywne zamowienie...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFFF2E6DD),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
              )
            else if (cartEntries.isNotEmpty)
              _CartOverviewBar(
                entries: cartEntries,
                etaLabel: '${_cartEstimatedPrepMinutes(cartEntries)} min',
                onSelect: onSelect,
                onRemove: onRemove,
                onContinue: onContinue,
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xEE3B3837),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  for (var i = 0; i < footer.length; i++)
                    Expanded(
                      child: InkWell(
                        onTap: () => onFooterTap(i, footer[i].$2),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    footer[i].$1,
                                    color: activeFooterIndex == i
                                        ? const Color(0xFFFFF0E7)
                                        : const Color(0xFFCEC3BC),
                                    size: 22,
                                  ),
                                  if (i == 1)
                                    Positioned(
                                      top: -8,
                                      right: -18,
                                      child:
                                          _PointsBadge(points: loyaltyPoints),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(footer[i].$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: activeFooterIndex == i
                                              ? const Color(0xFFFFF0E7)
                                              : const Color(0xFFCEC3BC),
                                          fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointsBadge extends StatelessWidget {
  const _PointsBadge({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    final label = points > 999 ? '999+' : '$points';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF08B2D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xCC5A2302)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x451D0C02),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF2E1304),
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _ActiveOrderBar extends StatelessWidget {
  const _ActiveOrderBar({
    required this.checkout,
    required this.onTap,
  });

  final CheckoutVerificationResponse checkout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final totalEta = checkout.receivedOrder.etaMinutes <= 0
        ? 1
        : checkout.receivedOrder.etaMinutes;
    final remainingEta = checkout.remainingEtaMinutes ?? totalEta;
    final progress = (1 - (remainingEta / totalEta)).clamp(0.0, 1.0).toDouble();
    final itemCount = checkout.receivedOrder.items.length;
    final leadItem = itemCount == 0
        ? 'Aktywne zamowienie'
        : checkout.receivedOrder.items.first.name;
    final etaDisplay = _activeCheckoutEtaDisplay(checkout);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xED2A231E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x2BFFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x341D0E07),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF37B766), Color(0xFF27894D)],
                      ),
                    ),
                    child: const Icon(
                      Icons.delivery_dining_rounded,
                      color: Color(0xFFF7FFF9),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trwa realizacja zamowienia #${checkout.savedOrderId}',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: const Color(0xFFF8EEE6),
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          leadItem,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFFDCC9BD),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        etaDisplay,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: const Color(0xFFF8F3EE),
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Dotknij, aby otworzyc',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFF8FE0AE),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: progress,
                  backgroundColor: const Color(0xFF473C35),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF3BC977)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Etap 1/2 aktywny',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFEEDDD0),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '$itemCount ${itemCount == 1 ? 'pozycja' : 'pozycje'}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFEEDDD0),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartSummaryScreen extends StatefulWidget {
  const _CartSummaryScreen({
    required this.initialEntries,
    required this.onCartChanged,
    required this.authSession,
  });

  final List<_CartEntry> initialEntries;
  final ValueChanged<List<_CartEntry>> onCartChanged;
  final AuthSession authSession;

  @override
  State<_CartSummaryScreen> createState() => _CartSummaryScreenState();
}

class _CartSummaryScreenState extends State<_CartSummaryScreen> {
  late List<_CartEntry> _entries;
  late final List<({String title, String subtitle})> _addresses;
  final TextEditingController _noteController = TextEditingController();
  _UdkaPickupEstimate? _udkaPickupEstimate;
  String _pickupLocationAddress = '';
  int _fulfillmentIndex = 0;
  int _addressIndex = 0;
  String? _selectedPaymentMethod;
  int _redeemedPoints = 0;
  int _deliveryEtaMinutes = 30;

  static const _fulfillmentOptions = <({String label, IconData icon})>[
    (label: 'Dostawa', icon: Icons.delivery_dining_rounded),
    (label: 'Odbior na miejscu', icon: Icons.storefront_rounded),
    (label: 'Zaplanuj odbior', icon: Icons.schedule_rounded),
  ];

  static const _defaultAddresses = <({String title, String subtitle})>[
    (title: 'Sklotowa 6/9', subtitle: '02-220, Warszawa'),
    (title: 'Mefedronowa 20', subtitle: '02-225, Warszawa'),
  ];

  @override
  void initState() {
    super.initState();
    _entries = List<_CartEntry>.from(widget.initialEntries);
    _addresses =
        List<({String title, String subtitle})>.from(_defaultAddresses);
    _enforceFulfillmentConstraints();
    _loadDeliveryEstimate();
    _refreshUdkaPickupEstimate();
    _loadPickupLocationAddress();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _syncEntries() {
    widget.onCartChanged(List<_CartEntry>.from(_entries));
  }

  Future<void> _refreshUdkaPickupEstimate() async {
    if (!_cartContainsUdka()) {
      if (mounted && _udkaPickupEstimate != null) {
        setState(() => _udkaPickupEstimate = null);
      }
      return;
    }

    try {
      final estimate = await _fetchUdkaPickupEstimateForEntries(_entries);
      if (!mounted) {
        return;
      }
      setState(() => _udkaPickupEstimate = estimate);
    } catch (_) {
      if (mounted) {
        setState(() => _udkaPickupEstimate = null);
      }
    }
  }

  bool _cartContainsUdka() => _containsUdkaCartEntries(_entries);

  bool _cartContainsIceCream() => _containsIceCreamCartEntries(_entries);

  int _defaultFulfillmentIndexForCurrentCart() {
    if (_cartContainsUdka()) {
      return 2;
    }
    if (_cartContainsIceCream()) {
      return 1;
    }
    return 0;
  }

  void _enforceFulfillmentConstraints() {
    final preferredIndex = _defaultFulfillmentIndexForCurrentCart();
    if (_cartContainsUdka()) {
      _fulfillmentIndex = preferredIndex;
      return;
    }
    if (_cartContainsIceCream() && _fulfillmentIndex == 0) {
      _fulfillmentIndex = preferredIndex;
    }
  }

  void _setFulfillmentIndex(int index) {
    if (_cartContainsUdka() && index != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Udka z kurczaka sa dostepne tylko w opcji Zaplanuj odbior o 12:00, 15:00 albo 18:00.',
          ),
        ),
      );
      return;
    }
    if (_cartContainsIceCream() && index == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lody sa dostepne tylko na miejscu albo w opcji Zaplanuj odbior.',
          ),
        ),
      );
      return;
    }

    setState(() => _fulfillmentIndex = index);
  }

  Future<void> _loadDeliveryEstimate() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/checkout/delivery-estimate'),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final etaMinutes = _asInt(decoded['eta_minutes']);
      if (etaMinutes == null || etaMinutes <= 0 || !mounted) {
        return;
      }

      setState(() => _deliveryEtaMinutes = etaMinutes);
    } catch (_) {
      // The backend recalculates ETA on checkout, so the UI can keep its fallback.
    }
  }

  Future<void> _loadPickupLocationAddress() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/checkout/pickup-location'),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final address = decoded['address']?.toString().trim() ?? '';
      if (!mounted) {
        return;
      }

      setState(() => _pickupLocationAddress = address);
    } catch (_) {
      // The backend still writes pickup address to the order on submit.
    }
  }

  void _removeEntry(int id) {
    setState(() {
      _entries.removeWhere((entry) => entry.id == id);
      _enforceFulfillmentConstraints();
      _redeemedPoints = _effectiveRedeemedPoints();
    });
    _syncEntries();
    _refreshUdkaPickupEstimate();
  }

  Future<void> _openPersonalization(_CartEntry entry) async {
    final updatedEntry = await Navigator.of(context).push<_CartEntry>(
      MaterialPageRoute<_CartEntry>(
        builder: (_) => _CartPersonalizationScreen(entry: entry),
      ),
    );

    if (updatedEntry == null || !mounted) {
      return;
    }

    setState(() {
      final index = _entries.indexWhere((item) => item.id == updatedEntry.id);
      if (index >= 0) {
        _entries[index] = updatedEntry;
      }
      _redeemedPoints = _effectiveRedeemedPoints();
    });
    _syncEntries();
    _refreshUdkaPickupEstimate();
  }

  Future<void> _showAddAddressDialog() async {
    final newAddress = await showDialog<({String title, String subtitle})>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (_) => const _AddAddressDialog(),
    );

    if (newAddress == null || !mounted) {
      return;
    }

    setState(() {
      _addresses.add(newAddress);
      _addressIndex = _addresses.length - 1;
      _fulfillmentIndex = _defaultFulfillmentIndexForCurrentCart();
    });
  }

  Future<void> _showPaymentMethodsDialog() async {
    final method = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _PaymentMethodsDialog(
        selectedMethod: _selectedPaymentMethod,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );

    if (method != null) {
      setState(() {
        _selectedPaymentMethod = method;
      });

      final payload = _buildOrderPayload(method);
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PaymentVerificationScreen(
            paymentMethod: method,
            checkoutRepository: _DashboardScreenState._checkoutRepository,
            requestPayload: payload,
            authSession: widget.authSession,
            onCheckoutConfirmed: () {
              setState(() {
                _entries.clear();
              });
              widget.onCartChanged(const <_CartEntry>[]);
            },
          ),
        ),
      );
    }
  }

  int _estimatedPrepMinutes() {
    final prepMinutes = _entries
        .map((entry) => _prepMinutes(entry.position))
        .whereType<int>()
        .where((minutes) => minutes > 0)
        .toList(growable: false);

    if (prepMinutes.isEmpty) {
      return 15;
    }

    return prepMinutes.reduce(math.max);
  }

  bool _usesDeliveryBuffer() => _fulfillmentIndex == 0;

  int _summaryEtaMinutes(int prepMinutes) {
    if (_cartContainsUdka()) {
      return _udkaPickupEstimate?.etaMinutes ?? _udkaPickupEtaMinutes();
    }
    if (!_usesDeliveryBuffer()) {
      return prepMinutes;
    }
    return _deliveryEtaMinutes;
  }

  String _summaryEtaLabel(int prepMinutes) {
    if (_cartContainsUdka()) {
      final estimate = _udkaPickupEstimate;
      if (estimate != null) {
        return _formatScheduledPickupCompact(estimate.scheduledPickupAt);
      }
      return _udkaPickupCompactLabel();
    }
    return '${_summaryEtaMinutes(prepMinutes)} min.';
  }

  String _addressEtaLabel(int prepMinutes) {
    return _addressEtaLabelForIndex(prepMinutes, _addressIndex);
  }

  String _addressEtaLabelForIndex(int prepMinutes, int _) {
    if (_cartContainsUdka()) {
      final estimate = _udkaPickupEstimate;
      if (estimate != null) {
        return _formatScheduledPickupDetailed(estimate.scheduledPickupAt);
      }
      return _udkaPickupEtaLabel();
    }
    final totalMinutes =
        _usesDeliveryBuffer() ? _deliveryEtaMinutes : prepMinutes;
    return '~$totalMinutes min.';
  }

  int _availableLoyaltyPoints() => widget.authSession.loyaltyPoints;

  int _maxRedeemablePoints(double subtotal) {
    final maxRedeemablePln = subtotal <= 0 ? 0 : (subtotal * 0.3).floor();
    final normalizedMaxPointsByOrder = maxRedeemablePln * 10;
    final availablePoints = _availableLoyaltyPoints();
    final clampedPoints = math.min(availablePoints, normalizedMaxPointsByOrder);
    return clampedPoints - (clampedPoints % 10);
  }

  int _effectiveRedeemedPoints() {
    final subtotal = _entries.fold<double>(
      0,
      (sum, entry) => sum + _entryPrice(entry),
    );
    final maxRedeemablePoints = _maxRedeemablePoints(subtotal);
    if (maxRedeemablePoints <= 0) {
      return 0;
    }

    final normalizedPoints = _redeemedPoints.clamp(0, maxRedeemablePoints);
    return normalizedPoints - (normalizedPoints % 10);
  }

  double _redeemedAmountForPoints(int points) {
    return points / 10;
  }

  CheckoutVerificationRequest _buildOrderPayload(String paymentMethod) {
    final selectedAddress = _usesDeliveryBuffer()
        ? _addresses[_addressIndex]
        : (
            title: _pickupLocationAddress.isNotEmpty
                ? _pickupLocationAddress
                : 'Adres odbioru zostanie potwierdzony przy zamowieniu',
            subtitle: _fulfillmentOptions[_fulfillmentIndex].label,
          );
    final subtotal = _entries.fold<double>(
      0,
      (sum, entry) => sum + _entryPrice(entry),
    );
    final redeemedPoints = _effectiveRedeemedPoints();
    final redeemedAmount = _redeemedAmountForPoints(redeemedPoints);
    final double total = math.max(0.0, subtotal - redeemedAmount);
    final quickNote = _noteController.text.trim();
    final estimatedPrepMinutes = _estimatedPrepMinutes();
    final etaMinutes = _summaryEtaMinutes(estimatedPrepMinutes);

    return CheckoutVerificationRequest(
      createdAt: DateTime.now().toUtc(),
      currency: 'PLN',
      subtotalAmount: subtotal,
      totalAmount: total,
      redeemedPoints: redeemedPoints,
      redeemedAmount: redeemedAmount,
      etaMinutes: etaMinutes,
      paymentMethod: paymentMethod,
      fulfillmentMethod: _fulfillmentOptions[_fulfillmentIndex].label,
      fulfillmentOptionIndex: _fulfillmentIndex,
      addressOptionIndex: _addressIndex,
      address: CheckoutVerificationAddress(
        title: selectedAddress.title,
        subtitle: selectedAddress.subtitle,
        etaLabel: _addressEtaLabel(estimatedPrepMinutes),
      ),
      items: _entries
          .map(
            (entry) => CheckoutVerificationItem(
              cartEntryId: entry.id,
              positionId: _positionId(entry.position),
              name: _title(entry.position, 0),
              description: _checkoutItemDescription(entry),
              photoUrl: _photo(entry.position),
              calories: _positionCalories(entry.position),
              price: _entryPrice(entry),
            ),
          )
          .toList(growable: false),
      sessionToken: widget.authSession.sessionToken,
      userEmail: widget.authSession.email,
      notes: quickNote.isEmpty ? null : quickNote,
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = _entries.fold<double>(
      0,
      (sum, entry) => sum + _entryPrice(entry),
    );
    final redeemedPoints = _effectiveRedeemedPoints();
    final redeemedAmount = _redeemedAmountForPoints(redeemedPoints);
    final double total = math.max(0.0, subtotal - redeemedAmount);
    final maxRedeemablePoints = _maxRedeemablePoints(subtotal);
    final estimatedPrepMinutes = _estimatedPrepMinutes();
    final udkaOnlyScheduledPickup = _cartContainsUdka();
    final iceCreamPickupOnly =
        !udkaOnlyScheduledPickup && _cartContainsIceCream();
    final visibleFulfillmentIndexes = udkaOnlyScheduledPickup
        ? const <int>[2]
        : iceCreamPickupOnly
            ? const <int>[1, 2]
            : const <int>[0, 1, 2];

    return Scaffold(
      extendBody: true,
      body: _Background(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 120),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xEE090909),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x33FFF2E8)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Koszyk',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: const Color(0xFFF9EEDF),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const Spacer(),
                        _IconCircle(
                          icon: Icons.undo_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SummarySection(
                      title: 'Wybrane produkty',
                      child: SizedBox(
                        height: 252,
                        child: _entries.isEmpty
                            ? Center(
                                child: Text(
                                  'Koszyk jest pusty.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFFD5C7BA),
                                      ),
                                ),
                              )
                            : ScrollConfiguration(
                                behavior: const MaterialScrollBehavior()
                                    .copyWith(scrollbars: false),
                                child: ListView.separated(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: _entries.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) =>
                                      _SummaryProductTile(
                                    entry: _entries[index],
                                    onCustomize: () =>
                                        _openPersonalization(_entries[index]),
                                    onRemove: () =>
                                        _removeEntry(_entries[index].id),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SummarySection(
                      title: 'Rodzaj realizacji',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (udkaOnlyScheduledPickup)
                            _FulfillmentTile(
                              label: _fulfillmentOptions[2].label,
                              icon: _fulfillmentOptions[2].icon,
                              isSelected: true,
                              onTap: () {},
                            )
                          else
                            Row(
                              children: [
                                for (var index = 0;
                                    index < visibleFulfillmentIndexes.length;
                                    index++) ...[
                                  if (index > 0) const SizedBox(width: 8),
                                  Expanded(
                                    child: _FulfillmentTile(
                                      label: _fulfillmentOptions[
                                              visibleFulfillmentIndexes[index]]
                                          .label,
                                      icon: _fulfillmentOptions[
                                              visibleFulfillmentIndexes[index]]
                                          .icon,
                                      isSelected: _fulfillmentIndex ==
                                          visibleFulfillmentIndexes[index],
                                      onTap: () => _setFulfillmentIndex(
                                        visibleFulfillmentIndexes[index],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          if (udkaOnlyScheduledPickup) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Udka wydajemy tylko w zaplanowanym odbiorze. Najblizszy termin: ${_summaryEtaLabel(estimatedPrepMinutes)}.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFFD5C7BA),
                                    height: 1.35,
                                  ),
                            ),
                          ] else if (iceCreamPickupOnly) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Lody sa dostepne tylko na miejscu albo w opcji Zaplanuj odbior.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFFD5C7BA),
                                    height: 1.35,
                                  ),
                            ),
                          ],
                          if (!_usesDeliveryBuffer()) ...[
                            const SizedBox(height: 16),
                            _PickupLocationCard(
                              address: _pickupLocationAddress,
                              etaLabel: _addressEtaLabel(estimatedPrepMinutes),
                              fulfillmentLabel:
                                  _fulfillmentOptions[_fulfillmentIndex].label,
                            ),
                          ],
                          if (_usesDeliveryBuffer()) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Adres dostawy',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFFF8EEDF),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 108,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: _addresses.length + 1,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  if (index == _addresses.length) {
                                    return Center(
                                      child: _AddAddressTile(
                                        onTap: _showAddAddressDialog,
                                      ),
                                    );
                                  }

                                  return SizedBox(
                                    width: 204,
                                    child: _AddressTile(
                                      title: _addresses[index].title,
                                      subtitle: _addresses[index].subtitle,
                                      eta: _addressEtaLabelForIndex(
                                        estimatedPrepMinutes,
                                        index,
                                      ),
                                      isSelected: _addressIndex == index,
                                      onTap: () =>
                                          setState(() => _addressIndex = index),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SummarySection(
                      title: 'Szybka uwaga do zamowienia',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Np. bez cebuli, dodatkowy sos albo prosba o telefon przy odbiorze.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFFD5C7BA),
                                      height: 1.35,
                                    ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _noteController,
                            minLines: 2,
                            maxLines: 3,
                            maxLength: 140,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFFF8EEE0),
                                ),
                            decoration: InputDecoration(
                              hintText: 'Dodaj krotka uwage dla restauracji...',
                              hintStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFF9E9085),
                                  ),
                              filled: true,
                              fillColor: const Color(0xFF171412),
                              counterStyle: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF8E8178),
                                  ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide:
                                    const BorderSide(color: Color(0x1FFFFFFF)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide:
                                    const BorderSide(color: Color(0x66FFB061)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SummarySection(
                      title: 'Nagrody i punkty',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Masz ${_availableLoyaltyPoints()} pkt. Przy tym zamowieniu mozesz wykorzystac maksymalnie $maxRedeemablePoints pkt, czyli PLN ${_fmt(_redeemedAmountForPoints(maxRedeemablePoints))}.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFFD5C7BA),
                                      height: 1.35,
                                    ),
                          ),
                          const SizedBox(height: 12),
                          if (maxRedeemablePoints > 0) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: const Color(0xFFFFA247),
                                      inactiveTrackColor:
                                          const Color(0x33FFFFFF),
                                      thumbColor: const Color(0xFFFFA247),
                                      overlayColor: const Color(0x33FFA247),
                                    ),
                                    child: Slider(
                                      value: redeemedPoints.toDouble(),
                                      min: 0,
                                      max: maxRedeemablePoints.toDouble(),
                                      divisions: maxRedeemablePoints ~/ 10,
                                      onChanged: (value) {
                                        setState(() {
                                          _redeemedPoints =
                                              ((value / 10).round() * 10).clamp(
                                                  0, maxRedeemablePoints);
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _redeemedPoints = redeemedPoints > 0
                                          ? 0
                                          : maxRedeemablePoints;
                                    });
                                  },
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(72, 44),
                                    foregroundColor: const Color(0xFFF7EEE6),
                                    side: const BorderSide(
                                      color: Color(0x30FFFFFF),
                                    ),
                                  ),
                                  child: Text(
                                    redeemedPoints > 0 ? 'Wyczysc' : 'Max',
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Wykorzystasz: $redeemedPoints pkt',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: const Color(0xFFF8EEE0),
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                Text(
                                  '- PLN ${_fmt(redeemedAmount)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: const Color(0xFFFFB66A),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                          ] else
                            Text(
                              'Zbieraj dalej punkty. Przy tym koszyku limit wykorzystania wynosi 30% wartosci zamowienia.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFFD5C7BA),
                                    height: 1.35,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'TOTAL',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: const Color(0xFFF8F0E8),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _SummaryMetricPill(
                            child: Text(
                              redeemedAmount > 0
                                  ? 'PLN ${_fmt(total)}'
                                  : 'PLN ${_fmt(subtotal)}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: const Color(0xFFF9EEDF),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SummaryMetricPill(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.access_time_rounded,
                                    color: Color(0xFFF0DDD0)),
                                const SizedBox(width: 8),
                                Text(
                                  _summaryEtaLabel(estimatedPrepMinutes),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: const Color(0xFFF0DDD0),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (redeemedAmount > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Suma przed punktami: PLN ${_fmt(subtotal)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFFD5C7BA),
                                  ),
                            ),
                          ),
                          Text(
                            'Punkty: - PLN ${_fmt(redeemedAmount)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFFFFB66A),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed:
                          _entries.isEmpty ? null : _showPaymentMethodsDialog,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: const Color(0xFFFF8B00),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _selectedPaymentMethod == null
                            ? 'Wybierz metode platnosci'
                            : 'Metoda platnosci: $_selectedPaymentMethod',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: _StaticFooterBar(),
        ),
      ),
    );
  }
}

class _PaymentVerificationScreen extends StatefulWidget {
  const _PaymentVerificationScreen({
    required this.paymentMethod,
    required this.checkoutRepository,
    required this.requestPayload,
    required this.authSession,
    required this.onCheckoutConfirmed,
  });

  final String paymentMethod;
  final CheckoutRepository checkoutRepository;
  final CheckoutVerificationRequest requestPayload;
  final AuthSession authSession;
  final VoidCallback onCheckoutConfirmed;

  @override
  State<_PaymentVerificationScreen> createState() =>
      _PaymentVerificationScreenState();
}

class _PaymentVerificationScreenState
    extends State<_PaymentVerificationScreen> {
  CheckoutVerificationResponse? _verificationResponse;
  Object? _verificationError;
  bool _isSubmitting = true;
  bool _didNavigateToTracking = false;

  @override
  void initState() {
    super.initState();
    _runVerificationFlow();
  }

  Future<void> _runVerificationFlow() async {
    try {
      final response =
          await widget.checkoutRepository.submitCheckoutVerification(
        widget.requestPayload,
      );
      final updatedAuthSession = widget.authSession.copyWith(
        loyaltyPoints: response.userPointsBalance,
      );
      await SessionPersistence.saveAuthSession(updatedAuthSession);

      if (!mounted) {
        return;
      }

      widget.onCheckoutConfirmed();
      setState(() {
        _verificationResponse = response;
        _verificationError = null;
        _isSubmitting = false;
      });

      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) {
        return;
      }

      _openTrackingScreen(response, updatedAuthSession);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _verificationError = error;
        _isSubmitting = false;
      });
    }
  }

  void _openTrackingScreen(
    CheckoutVerificationResponse checkout,
    AuthSession authSession,
  ) {
    if (_didNavigateToTracking || !mounted) {
      return;
    }

    _didNavigateToTracking = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OrderTrackingScreen(
          checkout: checkout,
          authSession: authSession,
          checkoutRepository: widget.checkoutRepository,
        ),
      ),
    );
  }

  String _verificationErrorMessage() {
    final raw = _verificationError?.toString() ?? 'Nieznany blad.';
    final detailMatch = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(raw);
    if (detailMatch != null) {
      return detailMatch.group(1) ?? raw;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _Background(
        child: SafeArea(
          bottom: false,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final isLoading = _isSubmitting;
              final hasError = _verificationError != null;
              final successfulCheckout = _verificationResponse;

              final jsonToShow = hasError
                  ? <String, dynamic>{
                      'request_payload': widget.requestPayload.toJson(),
                      'error': _verificationError.toString(),
                    }
                  : successfulCheckout == null
                      ? <String, dynamic>{
                          'request_payload': widget.requestPayload.toJson(),
                          'status': 'sending',
                        }
                      : <String, dynamic>{
                          'request_payload': widget.requestPayload.toJson(),
                          'backend_response': successfulCheckout.toJson(),
                        };

              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 120),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xEE090909),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x33FFF2E8)),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Weryfikacja platnosci',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: const Color(0xFFF9EEDF),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            _IconCircle(
                              icon: Icons.undo_rounded,
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2B2826),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                height: 48,
                                width: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1C1816),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: isLoading
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.6,
                                          color: Color(0xFFFF9A32),
                                        ),
                                      )
                                    : Icon(
                                        hasError
                                            ? Icons.error_outline_rounded
                                            : Icons.check_circle_rounded,
                                        color: hasError
                                            ? const Color(0xFFFF8975)
                                            : const Color(0xFF3BC977),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.paymentMethod,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        color: const Color(0xFFF8EEE7),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isLoading
                                          ? 'Wysylamy szczegoly zamowienia do backendu i przygotowujemy etap wstepnej weryfikacji.'
                                          : hasError
                                              ? _verificationErrorMessage()
                                              : (successfulCheckout?.message ??
                                                  'Backend przyjal dane do wstepnej weryfikacji.'),
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: const Color(0xFFD9C6B9),
                                        height: 1.35,
                                      ),
                                    ),
                                    if (successfulCheckout != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Symulacja platnosci zakonczyla sie sukcesem. Otwieramy widok trwajacego zamowienia.',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: const Color(0xFF73DCA2),
                                          fontWeight: FontWeight.w700,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (successfulCheckout != null) ...[
                          FilledButton(
                            onPressed: () => _openTrackingScreen(
                              successfulCheckout,
                              widget.authSession,
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              backgroundColor: const Color(0xFF2E8F57),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Przejdz do trwajacego zamowienia',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _SummarySection(
                          title: 'Payload i odpowiedz',
                          child: SizedBox(
                            height: 320,
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: SelectableText(
                                const JsonEncoder.withIndent('  ')
                                    .convert(jsonToShow),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFFF0DED2),
                                  height: 1.45,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: _StaticFooterBar(),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard(
      {required this.icon,
      required this.title,
      required this.message,
      this.buttonLabel,
      this.onPressed});

  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: const Color(0xE3191412),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 54, color: const Color(0xFFE98736)),
                  const SizedBox(height: 16),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFF8EEE7),
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFD8C5B8), height: 1.4)),
                  if (buttonLabel != null && onPressed != null) ...[
                    const SizedBox(height: 18),
                    FilledButton(
                        onPressed: onPressed, child: Text(buttonLabel!)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductPreviewDialog extends StatelessWidget {
  const _ProductPreviewDialog({
    required this.position,
    required this.onClose,
  });

  final Map<String, dynamic> position;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title(position, 0);
    final description = _description(position);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: const Color(0xF0191513),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x24FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x70000000),
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  child: SizedBox(
                    height: 250,
                    width: double.infinity,
                    child: _PositionImage(
                      photoUrl: _photo(position),
                      title: title,
                      fit: _positionImageFit(position),
                      alignment: _positionImageAlignment(position),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _RemoveThumbButton(onTap: onClose),
                ),
                Positioned(
                  left: 14,
                  bottom: 14,
                  child: _PricePill(label: _priceLabel(position)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFFDF3EC),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_isFrozenPosition(position)) ...[
                    const SizedBox(height: 10),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ProductStateBadge(label: 'MROZONE'),
                        _ProductStateBadge(label: 'DO ODGRZANIA'),
                      ],
                    ),
                  ],
                  if (!_isPositionAvailable(position)) ...[
                    const SizedBox(height: 10),
                    const _ProductStateBadge(
                      label: 'CHWILOWO NIEDOSTEPNE',
                      tone: _ProductStateBadgeTone.warning,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFDCCABE),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _DetailChip(
                        icon: Icons.access_time_rounded,
                        label: '${_prepMinutesOrFallback(position)} min',
                      ),
                      _DetailChip(
                        icon: Icons.local_fire_department_outlined,
                        label: _kcal(position),
                      ),
                      _DetailChip(
                        icon: Icons.receipt_long_outlined,
                        label: 'Pozycja z dashboardu',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2826),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFF5E7D5),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SummaryProductTile extends StatelessWidget {
  const _SummaryProductTile({
    required this.entry,
    required this.onCustomize,
    required this.onRemove,
  });

  final _CartEntry entry;
  final VoidCallback onCustomize;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _PositionImage(
                      photoUrl: _photo(entry.position),
                      title: _title(entry.position, 0),
                      fit: _positionImageFit(entry.position),
                      alignment: _positionImageAlignment(entry.position),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _PersonalizeThumbButton(
                    onTap: onCustomize,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _title(entry.position, 0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFF7EEE8),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (_isFrozenPosition(entry.position)) ...[
                  const SizedBox(height: 6),
                  const Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ProductStateBadge(label: 'MROZONE'),
                      _ProductStateBadge(label: 'DO ODGRZANIA'),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _description(entry.position),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD4C1B5),
                        height: 1.2,
                      ),
                ),
                if (entry.customization.hasSelections) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _personalizationEmojiBadges(entry.customization)
                        .map(
                          (label) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E2824),
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: const Color(0x22FFFFFF)),
                            ),
                            child: Text(
                              label,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFFFFD8B3),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 34,
                  width: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF34302D),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: _SummaryActionIcon(
                      icon: Icons.delete_outline_rounded, onTap: onRemove),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _entryPriceLabel(entry),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFFF5E6D7),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartPersonalizationScreen extends StatefulWidget {
  const _CartPersonalizationScreen({
    required this.entry,
  });

  final _CartEntry entry;

  @override
  State<_CartPersonalizationScreen> createState() =>
      _CartPersonalizationScreenState();
}

class _CartPersonalizationScreenState
    extends State<_CartPersonalizationScreen> {
  late _CartCustomization _customization;
  List<_PersonalizationOption> _options = const <_PersonalizationOption>[];
  bool _isLoadingOptions = true;
  Object? _optionsError;

  @override
  void initState() {
    super.initState();
    _customization = widget.entry.customization;
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    if (mounted) {
      setState(() {
        _isLoadingOptions = true;
        _optionsError = null;
      });
    }

    try {
      final options = await _fetchPersonalizationOptions(widget.entry.position);
      if (!mounted) {
        return;
      }

      setState(() {
        _options = options;
        _customization = _customization.normalizedForOptions(options);
        _isLoadingOptions = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _optionsError = error;
        _isLoadingOptions = false;
      });
    }
  }

  void _changeExtra(String label, int delta) {
    final current = _customization.extras[label] ?? 0;
    final next = current + delta;
    setState(() {
      _customization = _customization.copyWithExtra(
        label,
        next < 0 ? 0 : next,
      );
    });
  }

  void _setCutOption(_CutOption option) {
    setState(() {
      _customization = _customization.copyWith(cutOption: option);
    });
  }

  void _setPackagingOption(_PackagingOption option) {
    setState(() {
      _customization = _customization.copyWith(packagingOption: option);
    });
  }

  void _close() {
    Navigator.of(context).pop(
      widget.entry.copyWith(customization: _customization),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title(widget.entry.position, 0);
    final description = _description(widget.entry.position);
    final isZapiekanka =
        _supportsZapiekankaServingOptions(widget.entry.position);
    final selectedExtras = _personalizationChips(_customization);
    final extrasPriceTotal = _extrasPriceTotal(_customization);
    final hasAddonOptions = _options.isNotEmpty;

    Widget addonsContent;
    if (_isLoadingOptions) {
      addonsContent = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: Color(0xFFE98B38)),
        ),
      );
    } else if (_optionsError != null) {
      addonsContent = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nie udalo sie pobrac dodatkow dla tej pozycji.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFF8EEE7),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _optionsError.toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFD4C1B5),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadOptions,
                child: const Text('Sprobuj ponownie'),
              ),
            ],
          ),
        ),
      );
    } else if (!hasAddonOptions) {
      addonsContent = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Dla tej pozycji nie ma aktywnych dodatkow do personalizacji.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFD6C4B7),
              height: 1.35,
            ),
          ),
        ),
      );
    } else {
      addonsContent = SizedBox(
        height: 220,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final option = _options[index];
            return _CustomizationOptionTile(
              label: option.label,
              subtitle: option.subtitle,
              assetPath: option.assetPath,
              emoji: option.emoji,
              count: _customization.extras[option.label] ?? 0,
              onDecrement: () => _changeExtra(option.label, -1),
              onIncrement: () => _changeExtra(option.label, 1),
            );
          },
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      body: _Background(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 120),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xEE090909),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x33FFF2E8)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Personalizacja',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFFF9EEDF),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _IconCircle(
                          icon: Icons.close_rounded,
                          onTap: _close,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SummarySection(
                      title: 'Wybrana pozycja',
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 164,
                              height: 96,
                              child: _PositionImage(
                                photoUrl: _photo(widget.entry.position),
                                title: title,
                                fit: _positionImageFit(widget.entry.position),
                                alignment:
                                    _positionImageAlignment(widget.entry.position),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: const Color(0xFFF8EEE7),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFFD6C4B7),
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _PricePill(
                                    label: _priceLabel(widget.entry.position)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SummarySection(
                      title: 'Dodatki',
                      child: addonsContent,
                    ),
                    if (isZapiekanka) ...[
                      const SizedBox(height: 14),
                      _SummarySection(
                        title: 'Sposob podania',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wybierz, czy zapiekanka ma byc cieta na pol oraz w jakim opakowaniu ma trafic do wydania.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFFD7C5B8),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _ChoiceGroup(
                              title: 'Krojenie',
                              options: [
                                _ChoiceItem(
                                  title: 'Calosc',
                                  subtitle: 'Bez krojenia, pelna zapiekanka.',
                                  selected: _customization.cutOption ==
                                      _CutOption.whole,
                                  onTap: () => _setCutOption(_CutOption.whole),
                                  assetPath: 'assets/images/productWhole.png',
                                  assetScale: 1.64,
                                ),
                                _ChoiceItem(
                                  title: 'Na pol',
                                  subtitle: 'Przekrojona na dwie czesci.',
                                  selected: _customization.cutOption ==
                                      _CutOption.cutInHalf,
                                  onTap: () =>
                                      _setCutOption(_CutOption.cutInHalf),
                                  assetPath: 'assets/images/productHalfed.png',
                                  assetScale: 1.64,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _ChoiceGroup(
                              title: 'Opakowanie',
                              options: [
                                _ChoiceItem(
                                  title: 'Tacka papierowa',
                                  subtitle:
                                      'Standardowe podanie na papierowej tacce.',
                                  selected: _customization.packagingOption ==
                                      _PackagingOption.paperTray,
                                  onTap: () => _setPackagingOption(
                                    _PackagingOption.paperTray,
                                  ),
                                  assetPath: 'assets/images/paperLongPlate.png',
                                  assetScale: 0.91,
                                ),
                                _ChoiceItem(
                                  title: 'Pudelko',
                                  subtitle:
                                      'Wygodniejsze opakowanie do transportu.',
                                  selected: _customization.packagingOption ==
                                      _PackagingOption.box,
                                  onTap: () => _setPackagingOption(
                                    _PackagingOption.box,
                                  ),
                                  assetPath: 'assets/images/paperBox.png',
                                  assetScale: 0.91,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _SummarySection(
                      title: 'Podglad',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedExtras.isEmpty
                                ? hasAddonOptions
                                    ? 'Brak dodatkow. Mozesz zostawic pozycje w wersji podstawowej albo dodac aktywne opcje.'
                                    : 'Ta pozycja nie ma teraz aktywnych dodatkow.'
                                : 'Wybrane dodatki zostana przypiete do tej pozycji w koszyku.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFFD7C5B8),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1A18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (selectedExtras.isEmpty)
                                  Text(
                                    isZapiekanka
                                        ? 'Wybrane zostana ustawienia krojenia i opakowania.'
                                        : 'Pozycja bez personalizacji',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: const Color(0xFFF4E4D7),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: selectedExtras
                                        .map(
                                          (label) => Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF201A16),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                  color:
                                                      const Color(0x2AFFFFFF)),
                                            ),
                                            child: Text(
                                              label,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                color: const Color(0xFFFFD8B5),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(growable: false),
                                  ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: Text(
                                    'PLN ${_fmt(extrasPriceTotal)}',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: const Color(0xFFFFFFFF),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryMetricPill(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${isZapiekanka ? _customization.totalSelections : _customization.totalExtras}',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: const Color(0xFFF8EEE0),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  isZapiekanka ? 'wyborow' : 'dodatkow',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: const Color(0xFFDCCABE),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _close,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor: const Color(0xFFFF8B00),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Gotowe',
                              style: TextStyle(fontWeight: FontWeight.w800),
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
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: _StaticFooterBar(),
        ),
      ),
    );
  }
}

class _CustomizationOptionTile extends StatelessWidget {
  const _CustomizationOptionTile({
    required this.label,
    required this.subtitle,
    required this.assetPath,
    required this.emoji,
    required this.count,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final String subtitle;
  final String? assetPath;
  final String emoji;
  final int count;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 176,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1816),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: count > 0 ? const Color(0x33FFB15D) : const Color(0x14FFFFFF),
        ),
        boxShadow: count > 0
            ? const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0xFF261F1B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x22FFFFFF)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ImageSideStepper(
                  icon: Icons.remove_rounded,
                  tooltip: 'Zmniejsz liczbe dodatkow',
                  onTap: onDecrement,
                  side: _StepperSide.left,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x26FFFFFF)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _AddonImageFrame(
                        assetPath: assetPath,
                        emoji: emoji,
                        title: label,
                      ),
                    ),
                  ),
                ),
                _ImageSideStepper(
                  icon: Icons.add_rounded,
                  tooltip: 'Zwieksz liczbe dodatkow',
                  onTap: onIncrement,
                  side: _StepperSide.right,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF8ECE0),
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFD1BDB1),
                  height: 1.2,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF29221D),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x18FFFFFF)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$count',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF7EADB),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceItem {
  const _ChoiceItem({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.assetPath,
    this.assetScale = 1,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? assetPath;
  final double assetScale;
}

class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.title,
    required this.options,
  });

  final String title;
  final List<_ChoiceItem> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFFF7EEE7),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: options
              .map(
                (option) => Padding(
                  padding: EdgeInsets.only(
                    bottom: option == options.last ? 0 : 8,
                  ),
                  child: _ChoiceTile(option: option),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.option,
  });

  final _ChoiceItem option;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAsset = option.assetPath != null && option.assetPath!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: option.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: option.selected
                ? const Color(0xFF2A241F)
                : const Color(0xFF191614),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: option.selected
                  ? const Color(0x55FFB15D)
                  : const Color(0x1FFFFFFF),
            ),
          ),
          child: Row(
            children: [
              if (hasAsset) ...[
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x18FFFFFF)),
                  ),
                  child: Center(
                    child: OverflowBox(
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: 220,
                      maxHeight: 220,
                      child: Transform.scale(
                        scale: option.assetScale,
                        child: Image.asset(
                          option.assetPath!,
                          width: 86,
                          height: 86,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFF8EEE7),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD3C2B6),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 24,
                width: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: option.selected
                      ? const Color(0xFFFF9D3C)
                      : Colors.transparent,
                  border: Border.all(
                    color: option.selected
                        ? const Color(0xFFFFC78D)
                        : const Color(0x55FFFFFF),
                  ),
                ),
                child: option.selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageSideStepper extends StatelessWidget {
  const _ImageSideStepper({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.side,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final _StepperSide side;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.only(
            topLeft: side == _StepperSide.left
                ? const Radius.circular(14)
                : const Radius.circular(0),
            bottomLeft: side == _StepperSide.left
                ? const Radius.circular(14)
                : const Radius.circular(0),
            topRight: side == _StepperSide.right
                ? const Radius.circular(14)
                : const Radius.circular(0),
            bottomRight: side == _StepperSide.right
                ? const Radius.circular(14)
                : const Radius.circular(0),
          ),
          child: Container(
            width: 38,
            height: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2A221D),
              borderRadius: BorderRadius.only(
                topLeft: side == _StepperSide.left
                    ? const Radius.circular(14)
                    : const Radius.circular(0),
                bottomLeft: side == _StepperSide.left
                    ? const Radius.circular(14)
                    : const Radius.circular(0),
                topRight: side == _StepperSide.right
                    ? const Radius.circular(14)
                    : const Radius.circular(0),
                bottomRight: side == _StepperSide.right
                    ? const Radius.circular(14)
                    : const Radius.circular(0),
              ),
              border: Border(
                top: const BorderSide(color: Color(0x18FFFFFF)),
                bottom: const BorderSide(color: Color(0x18FFFFFF)),
                left: side == _StepperSide.left
                    ? const BorderSide(color: Color(0x18FFFFFF))
                    : BorderSide.none,
                right: side == _StepperSide.right
                    ? const BorderSide(color: Color(0x18FFFFFF))
                    : BorderSide.none,
              ),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFFEAD9),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _AddonImageFrame extends StatelessWidget {
  const _AddonImageFrame({
    required this.assetPath,
    required this.emoji,
    required this.title,
  });

  final String? assetPath;
  final String emoji;
  final String title;

  @override
  Widget build(BuildContext context) {
    final resolvedAssetPath = assetPath?.trim();
    if (resolvedAssetPath != null && resolvedAssetPath.isNotEmpty) {
      if (_isBundledAssetPhoto(resolvedAssetPath)) {
        return Image.asset(
          _normalizeBundledAssetPhoto(resolvedAssetPath),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(context),
        );
      }
      return Image.network(
        resolvedAssetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF31251E), Color(0xFF5B4137)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 26),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFFFF0E6),
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StepperSide { left, right }

class _SummaryActionIcon extends StatelessWidget {
  const _SummaryActionIcon({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 22,
        width: 22,
        decoration: BoxDecoration(
          color: const Color(0xFF433E3A),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Icon(icon, size: 14, color: const Color(0xFFF5E7D7)),
      ),
    );
  }
}

class _FulfillmentTile extends StatelessWidget {
  const _FulfillmentTile({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF38332E) : const Color(0xFF24211F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                isSelected ? const Color(0x40FFB061) : const Color(0x10FFFFFF),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: const Color(0xFFF5E6D7)),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFFF4E6D9),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.title,
    required this.subtitle,
    required this.eta,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String eta;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 108,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF141313) : const Color(0xFF1E1A18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                isSelected ? const Color(0x33FFD199) : const Color(0x12FFFFFF),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFF6E8D9),
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFD6C5B9),
                  ),
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.access_time_rounded,
                    size: 14, color: Color(0xFFF0DDD0)),
                const SizedBox(width: 4),
                Text(
                  eta,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: const Color(0xFFF0DDD0),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddAddressTile extends StatelessWidget {
  const _AddAddressTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 72,
        width: 72,
        decoration: const BoxDecoration(
          color: Color(0xFF1D1B19),
          shape: BoxShape.circle,
        ),
        child:
            const Icon(Icons.add_rounded, color: Color(0xFFF6E8D9), size: 34),
      ),
    );
  }
}

class _AddAddressDialog extends StatefulWidget {
  const _AddAddressDialog();

  @override
  State<_AddAddressDialog> createState() => _AddAddressDialogState();
}

class _AddAddressDialogState extends State<_AddAddressDialog> {
  final _formKey = GlobalKey<FormState>();
  final _streetController = TextEditingController();
  final _postalController = TextEditingController();
  final _cityController = TextEditingController(text: 'Warszawa');
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _streetController.dispose();
    _postalController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final street = _streetController.text.trim();
    final postal = _postalController.text.trim();
    final city = _cityController.text.trim();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse(
              '${AppConfig.apiBaseUrl}/checkout/validate-delivery-address',
            ),
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'street': street,
              'postal': postal,
              'city': city,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) {
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() {
          _errorMessage = _extractBackendDetail(response.body) ??
              'Nie udalo sie potwierdzic adresu dostawy.';
          _isSubmitting = false;
        });
        return;
      }

      Navigator.of(context).pop((
        title: street,
        subtitle: '$postal, $city',
      ));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Nie udalo sie sprawdzic adresu. Sprobuj ponownie za chwile.';
        _isSubmitting = false;
      });
    }
  }

  String? _extractBackendDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail']?.toString().trim();
        if (detail != null && detail.isNotEmpty) {
          return detail;
        }
      }
    } catch (_) {
      // Ignore malformed error payloads and fall back to a generic message.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      backgroundColor: const Color(0xFF211917),
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Nowy adres dostawy',
        style: theme.textTheme.titleLarge?.copyWith(
          color: const Color(0xFFF8EEE0),
          fontWeight: FontWeight.w900,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _streetController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Ulica i numer',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Podaj ulice i numer.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _postalController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Kod pocztowy',
                    prefixIcon: Icon(Icons.local_post_office_outlined),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Podaj kod pocztowy.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityController,
                  textInputAction: TextInputAction.done,
                  enabled: !_isSubmitting,
                  decoration: const InputDecoration(
                    labelText: 'Miasto',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Podaj miasto.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFF9F9F),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Dodaj adres'),
        ),
      ],
    );
  }
}

class _CartOverviewBar extends StatelessWidget {
  const _CartOverviewBar({
    required this.entries,
    required this.etaLabel,
    required this.onSelect,
    required this.onRemove,
    required this.onContinue,
  });

  final List<_CartEntry> entries;
  final String etaLabel;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<int> onRemove;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(
      0,
      (sum, entry) => sum + _entryPrice(entry),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xED2A231E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x2BFFFFFF)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.shopping_cart_outlined,
                          size: 16,
                          color: Color(0xFFF0D7C7),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Koszyk',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: const Color(0xFFF7E7DD),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 104,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => _CartThumb(
                          entry: entries[index],
                          onTap: () => onSelect(entries[index].position),
                          onRemove: () => onRemove(entries[index].id),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 92,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: const Color(0x33FFF3EA),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PLN ${_fmt(total)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFFFF3EA),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${entries.length} szt.',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFF0DDCF),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 15,
                        color: Color(0xFFEBD7C8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        etaLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFEBD7C8),
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: onContinue,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(96, 42),
                      backgroundColor: const Color(0xFFDD6B1F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'DALEJ',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryMetricPill extends StatelessWidget {
  const _SummaryMetricPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2724),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _StaticFooterBar extends StatelessWidget {
  const _StaticFooterBar();

  @override
  Widget build(BuildContext context) {
    const footer = [
      (Icons.receipt_long_outlined, 'Menu'),
      (Icons.emoji_events_outlined, 'Nagrody'),
      (Icons.person_rounded, 'Profil')
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xEE3B3837),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < footer.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(footer[i].$1,
                        color: const Color(0xFFCEC3BC), size: 22),
                    const SizedBox(height: 4),
                    Text(
                      footer[i].$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFFCEC3BC),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CartThumb extends StatelessWidget {
  const _CartThumb({
    required this.entry,
    required this.onTap,
    required this.onRemove,
  });

  final _CartEntry entry;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 156,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0x33181514),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: _positionImagePadding(entry.position, compact: true),
                child: _PositionImage(
                  photoUrl: _photo(entry.position),
                  title: _title(entry.position, 0),
                  fit: _positionImageFit(entry.position, compact: true),
                  alignment: _positionImageAlignment(
                    entry.position,
                    compact: true,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: _PricePill(label: _priceLabel(entry.position)),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: _RemoveThumbButton(onTap: onRemove),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 42,
        width: 42,
        decoration: BoxDecoration(
            color: const Color(0x1CFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x2CFFFFFF))),
        child: Icon(icon, color: const Color(0xFFF4E5DB), size: 20),
      ),
    );
  }
}

class _ProductStateBadge extends StatelessWidget {
  const _ProductStateBadge({
    required this.label,
    this.tone = _ProductStateBadgeTone.info,
  });

  final String label;
  final _ProductStateBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = tone == _ProductStateBadgeTone.warning
        ? const Color(0xFF312319)
        : const Color(0xFF2A231D);
    final borderColor = tone == _ProductStateBadgeTone.warning
        ? const Color(0x44FFB36A)
        : const Color(0x33AEE6FF);
    final textColor = tone == _ProductStateBadgeTone.warning
        ? const Color(0xFFFFD4AA)
        : const Color(0xFFBEEAFF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

enum _ProductStateBadgeTone { info, warning }

class _PrepTimeBadge extends StatelessWidget {
  const _PrepTimeBadge({
    required this.minutes,
  });

  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF251E19),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33FFD6AB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.access_time_rounded,
            size: 13,
            color: Color(0xFFFFCB93),
          ),
          const SizedBox(width: 5),
          Text(
            '$minutes min',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFFFD8B2),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _CategoryEtaBadge extends StatelessWidget {
  const _CategoryEtaBadge({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF251E19),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33FFD6AB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.access_time_rounded,
            size: 13,
            color: Color(0xFFFFCB93),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFFFD8B2),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xD9FFF4E8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF45200F),
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF261F1A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x2AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFF19A49)),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFF8E9DD),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodsDialog extends StatelessWidget {
  const _PaymentMethodsDialog({
    required this.selectedMethod,
    required this.onClose,
  });

  final String? selectedMethod;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const methods = <String>['BLIK', 'Apple Pay', 'Google Pay'];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        decoration: BoxDecoration(
          color: const Color(0xF0191513),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Metoda platnosci',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFF8EEE7),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const Spacer(),
                _RemoveThumbButton(onTap: onClose),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var index = 0; index < methods.length; index++) ...[
                  if (index > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _PaymentMethodTile(
                      label: methods[index],
                      isSelected: selectedMethod == methods[index],
                      onTap: () => Navigator.of(context).pop(methods[index]),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent =
        isSelected ? const Color(0xFFFFA247) : const Color(0xFF615852);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3A332E) : const Color(0xFF2A2623),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _paymentBrand(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF9EEE6),
                    fontWeight: FontWeight.w900,
                    letterSpacing: label == 'BLIK' ? 0.5 : 0,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFFDCC9BC),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbActionButton extends StatelessWidget {
  const _ThumbActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: const Color(0xE81B1512),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Icon(
              icon,
              size: 18,
              color: const Color(0xFFFFE9DA),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickupLocationCard extends StatelessWidget {
  const _PickupLocationCard({
    required this.address,
    required this.etaLabel,
    required this.fulfillmentLabel,
  });

  final String address;
  final String etaLabel;
  final String fulfillmentLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedAddress = address.trim().isEmpty
        ? 'Adres lokalu zostanie pokazany po zatwierdzeniu ustawienia w panelu administratora.'
        : address.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161311),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 18,
                color: Color(0xFFFFC38D),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Miejsce odbioru',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFFF8EEDF),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                etaLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFF0DDD0),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            resolvedAddress,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFF6E8D9),
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            fulfillmentLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFD6C5B9),
                  height: 1.3,
                ),
          ),
        ],
      ),
    );
  }
}

class _RemoveThumbButton extends StatelessWidget {
  const _RemoveThumbButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ThumbActionButton(
      icon: Icons.close_rounded,
      tooltip: 'Zamknij',
      onTap: onTap,
    );
  }
}

class _PersonalizeThumbButton extends StatelessWidget {
  const _PersonalizeThumbButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ThumbActionButton(
      icon: Icons.brush_rounded,
      tooltip: 'Personalizuj pozycje',
      onTap: onTap,
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent])),
      ),
    );
  }
}

class _PositionImage extends StatelessWidget {
  const _PositionImage({
    required this.photoUrl,
    required this.title,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String? photoUrl;
  final String title;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.trim().isNotEmpty) {
      final resolvedPhotoUrl = photoUrl!.trim();
      if (_isBundledAssetPhoto(resolvedPhotoUrl)) {
        return _FadedPositionImage(
          child: Image.asset(
            _normalizeBundledAssetPhoto(resolvedPhotoUrl),
            fit: fit,
            alignment: alignment,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => _fallback(context),
          ),
        );
      }
      return _FadedPositionImage(
        child: Image.network(
          resolvedPhotoUrl,
          fit: fit,
          alignment: alignment,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _fallback(context),
        ),
      );
    }
    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF2D1C16), Color(0xFF594036)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxHeight <= 64 || constraints.maxWidth <= 64;
        final iconSize = isCompact
            ? math.max(
                14.0,
                math.min(constraints.maxWidth, constraints.maxHeight) * 0.42,
              )
            : 26.0;
        final showTitle =
            !isCompact && constraints.maxHeight >= 96 && constraints.maxWidth >= 88;

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fastfood_rounded,
                  size: iconSize,
                  color: const Color(0xFFFFE9D9),
                ),
                if (showTitle) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 18,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: const Color(0xFFFFF0E6),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FadedPositionImage extends StatelessWidget {
  const _FadedPositionImage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0x78080706),
                Color(0x00080706),
                Color(0xD8080706),
              ],
              stops: [0, 0.5, 1],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0x9A080706),
                Color(0x00080706),
                Color(0x00080706),
                Color(0x9A080706),
              ],
              stops: [0, 0.16, 0.84, 1],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardCategory {
  const _DashboardCategory({
    required this.key,
    required this.title,
    required this.icon,
    required this.startColor,
    required this.endColor,
    required this.items,
  });

  final String key;
  final String title;
  final IconData icon;
  final Color startColor;
  final Color endColor;
  final List<Map<String, dynamic>> items;
}

class _CartEntry {
  const _CartEntry({
    required this.id,
    required this.position,
    this.customization = const _CartCustomization(),
  });

  final int id;
  final Map<String, dynamic> position;
  final _CartCustomization customization;

  _CartEntry copyWith({
    int? id,
    Map<String, dynamic>? position,
    _CartCustomization? customization,
  }) {
    return _CartEntry(
      id: id ?? this.id,
      position: position ?? this.position,
      customization: customization ?? this.customization,
    );
  }
}

class _CartCustomization {
  const _CartCustomization({
    this.extras = const <String, int>{},
    this.extraUnitPrices = const <String, double>{},
    this.defaultExtras = const <String, int>{},
    this.extraEmojis = const <String, String>{},
    this.servingOptionsEnabled = false,
    this.cutOption = _CutOption.whole,
    this.packagingOption = _PackagingOption.paperTray,
  });

  final Map<String, int> extras;
  final Map<String, double> extraUnitPrices;
  final Map<String, int> defaultExtras;
  final Map<String, String> extraEmojis;
  final bool servingOptionsEnabled;
  final _CutOption cutOption;
  final _PackagingOption packagingOption;

  bool get hasSelections =>
      extras.values.any((count) => count > 0) ||
      (servingOptionsEnabled && cutOption != _CutOption.whole) ||
      (servingOptionsEnabled && packagingOption != _PackagingOption.paperTray);

  int get totalExtras => extras.values.fold(0, (sum, count) => sum + count);
  int get totalSelections => totalExtras + (servingOptionsEnabled ? 2 : 0);

  _CartCustomization copyWith({
    Map<String, int>? extras,
    Map<String, double>? extraUnitPrices,
    Map<String, int>? defaultExtras,
    Map<String, String>? extraEmojis,
    bool? servingOptionsEnabled,
    _CutOption? cutOption,
    _PackagingOption? packagingOption,
  }) {
    return _CartCustomization(
      extras: extras ?? this.extras,
      extraUnitPrices: extraUnitPrices ?? this.extraUnitPrices,
      defaultExtras: defaultExtras ?? this.defaultExtras,
      extraEmojis: extraEmojis ?? this.extraEmojis,
      servingOptionsEnabled:
          servingOptionsEnabled ?? this.servingOptionsEnabled,
      cutOption: cutOption ?? this.cutOption,
      packagingOption: packagingOption ?? this.packagingOption,
    );
  }

  _CartCustomization copyWithExtra(String label, int count) {
    final nextExtras = Map<String, int>.from(extras);
    if (count <= 0) {
      nextExtras.remove(label);
    } else {
      nextExtras[label] = count;
    }
    return copyWith(extras: nextExtras);
  }

  _CartCustomization normalizedForOptions(
    List<_PersonalizationOption> options,
  ) {
    final hasResolvedMetadata = defaultExtras.isNotEmpty ||
        extraUnitPrices.isNotEmpty ||
        extraEmojis.isNotEmpty;
    final nextExtras = <String, int>{};
    final nextPrices = <String, double>{};
    final nextDefaults = <String, int>{};
    final nextEmojis = <String, String>{};

    for (final option in options) {
      nextPrices[option.label] = option.price;
      nextDefaults[option.label] = option.defaultQuantity;
      nextEmojis[option.label] = option.emoji;

      final currentCount = extras.containsKey(option.label)
          ? extras[option.label] ?? 0
          : (hasResolvedMetadata ? 0 : option.defaultQuantity);
      if (currentCount > 0) {
        nextExtras[option.label] = currentCount;
      }
    }

    return copyWith(
      extras: nextExtras,
      extraUnitPrices: nextPrices,
      defaultExtras: nextDefaults,
      extraEmojis: nextEmojis,
    );
  }
}

enum _CutOption {
  whole,
  cutInHalf,
}

enum _PackagingOption {
  paperTray,
  box,
}

class _PersonalizationOption {
  const _PersonalizationOption({
    required this.label,
    required this.subtitle,
    required this.emoji,
    required this.price,
    this.defaultQuantity = 0,
    this.assetPath,
  });

  final String label;
  final String subtitle;
  final String emoji;
  final double price;
  final int defaultQuantity;
  final String? assetPath;
}

const _knownPersonalizationOptions = <_PersonalizationOption>[
  _PersonalizationOption(
    label: 'Pomidory',
    subtitle: 'Swieze plasterki pomidora do klasycznej zapiekanki.',
    emoji: '🍅',
    price: 3,
    assetPath: 'assets/images/tomatos.png',
  ),
  _PersonalizationOption(
    label: 'Oliwki',
    subtitle: 'Lekko slone oliwki, ktore podbijaja smak sera i pieczywa.',
    emoji: '🫒',
    price: 3,
  ),
  _PersonalizationOption(
    label: 'Prazona cebulka',
    subtitle: 'Chrupiaca cebulka dla dodatkowej tekstury i aromatu.',
    emoji: '🧅',
    price: 2.5,
    assetPath: 'assets/images/crispyOnions.png',
  ),
  _PersonalizationOption(
    label: 'Sos BBQ',
    subtitle: 'Dymny sos do mocniejszego, bardziej grillowego profilu.',
    emoji: '🍖',
    price: 2,
    assetPath: 'assets/images/bbqSauce.png',
  ),
  _PersonalizationOption(
    label: 'Surowka kolorowa',
    subtitle: 'Swieza salatka jako lekki, chrupiacy kontrast.',
    emoji: '🥗',
    price: 4,
    assetPath: 'assets/images/colorSalad.png',
  ),
  _PersonalizationOption(
    label: 'Ketchup',
    subtitle: 'Klasyczny dodatek dla bardziej znanego, pomidorowego smaku.',
    emoji: '🍅',
    price: 1.5,
    assetPath: 'assets/images/ketchup.png',
  ),
  _PersonalizationOption(
    label: 'Sos tysiaca wysp',
    subtitle: 'Lagodniejszy, kremowy sos do bogatszej kompozycji.',
    emoji: '🥫',
    price: 2.5,
    assetPath: 'assets/images/thousandIslandsSauce.png',
  ),
];

final Map<String, _PersonalizationOption> _knownPersonalizationOptionsByLabel =
    {
  for (final option in _knownPersonalizationOptions)
    option.label.trim().toLowerCase(): option,
};

Future<List<_PersonalizationOption>> _fetchPersonalizationOptions(
  Map<String, dynamic> position,
) async {
  if (_isFrozenPosition(position)) {
    return const <_PersonalizationOption>[];
  }
  final positionId = _positionId(position);
  if (positionId == null) {
    return const <_PersonalizationOption>[];
  }

  final response = await http.get(
    Uri.parse('${AppConfig.apiBaseUrl}/position/$positionId/addons'),
    headers: const {
      'Accept': 'application/json',
    },
  ).timeout(const Duration(seconds: 10));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'Backend zwrocil ${response.statusCode}: ${response.body}',
    );
  }

  final decoded = jsonDecode(response.body);
  if (decoded is! List<dynamic>) {
    throw Exception(
      'Nieoczekiwany format odpowiedzi z /position/{position_id}/addons.',
    );
  }

  return decoded
      .map(
        (item) => item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map),
      )
      .map(_personalizationOptionFromJson)
      .toList(growable: false);
}

_PersonalizationOption _personalizationOptionFromJson(
  Map<String, dynamic> json,
) {
  final label = json['name']?.toString().trim() ?? 'Dodatek';
  final normalizedLabel = label.toLowerCase();
  final knownOption = _knownPersonalizationOptionsByLabel[normalizedLabel];
  final description = json['description']?.toString().trim();
  final defaultQuantity = _asInt(json['default_quantity']) ?? 0;

  return _PersonalizationOption(
    label: label,
    subtitle: description == null || description.isEmpty
        ? knownOption?.subtitle ?? 'Dodatek do personalizacji pozycji.'
        : description,
    emoji: knownOption?.emoji ?? _fallbackExtraEmoji(label),
    price: _price(json) ?? knownOption?.price ?? 0,
    defaultQuantity: defaultQuantity > 0 ? defaultQuantity : 0,
    assetPath:
        _resolvePersonalizationAssetPath(json['photo_url']?.toString()) ??
            knownOption?.assetPath,
  );
}

String? _resolvePersonalizationAssetPath(String? rawValue) {
  final value = rawValue?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return _isBundledAssetPhoto(value)
      ? _normalizeBundledAssetPhoto(value)
      : value;
}

List<_DashboardCategory> _buildDashboardCategories(
  List<Map<String, dynamic>> positions,
) {
  const definitions = [
    (
      'zapiekanki',
      'Zapiekanki',
      Icons.view_agenda_rounded,
      Color(0xFFF28A2A),
      Color(0xFFCC5C1F),
    ),
    (
      'kids',
      'Kids',
      Icons.child_care_rounded,
      Color(0xFF9D7CFF),
      Color(0xFF6A48D7),
    ),
    (
      'udka',
      'Udka',
      Icons.set_meal_rounded,
      Color(0xFFFF9B5C),
      Color(0xFFD05E2A),
    ),
    (
      'lody',
      'Lody',
      Icons.icecream_rounded,
      Color(0xFF3AB6BF),
      Color(0xFF207E90),
    ),
    (
      'napoje',
      'Napoje',
      Icons.local_drink_rounded,
      Color(0xFFD5442F),
      Color(0xFFA61F1B),
    ),
    (
      'dodatki',
      'Frytki',
      Icons.lunch_dining_rounded,
      Color(0xFFE1662A),
      Color(0xFFB83B18),
    ),
  ];

  return definitions
      .map(
        (definition) => _DashboardCategory(
          key: definition.$1,
          title: definition.$2,
          icon: definition.$3,
          startColor: definition.$4,
          endColor: definition.$5,
          items: positions
              .where((position) =>
                  _categoryKeyForPosition(position) == definition.$1)
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
}

String _categoryKeyForPosition(Map<String, dynamic> position) {
  final positionType =
      position['position_type']?.toString().trim().toLowerCase() ?? '';
  final prepGroup =
      position['prep_group_key']?.toString().trim().toLowerCase() ?? '';
  final title = _title(position, 0).trim().toLowerCase();
  final description = _description(position).trim().toLowerCase();
  final haystack = '$positionType $prepGroup $title $description';

  if (positionType.contains('kids') ||
      prepGroup.contains('kids') ||
      haystack.contains('dziec') ||
      haystack.contains('kids')) {
    return 'kids';
  }

  if (prepGroup.contains('zapiek') ||
      positionType.contains('zapiek') ||
      positionType.contains('zapkiek') ||
      (positionType.contains('zap') && positionType.contains('iek')) ||
      haystack.contains('zapiek')) {
    return 'zapiekanki';
  }

  if (prepGroup.contains('udka') ||
      positionType.contains('udk') ||
      haystack.contains('udk') ||
      haystack.contains('kurczak') ||
      haystack.contains('chicken')) {
    return 'udka';
  }

  if (positionType.contains('lod') ||
      haystack.contains('lody') ||
      haystack.contains('lod ') ||
      haystack.contains('ice cream') ||
      haystack.contains('gelato')) {
    return 'lody';
  }

  if (positionType.contains('napoj') ||
      positionType.contains('drink') ||
      haystack.contains('napoj') ||
      haystack.contains('cola') ||
      haystack.contains('pepsi') ||
      haystack.contains('sprite') ||
      haystack.contains('fanta') ||
      haystack.contains('woda') ||
      haystack.contains('sok') ||
      haystack.contains('kawa') ||
      haystack.contains('herbata')) {
    return 'napoje';
  }

  return 'dodatki';
}

String _categorySubtitle(String categoryKey) {
  switch (categoryKey) {
    case 'zapiekanki':
      return 'Klasyczne oraz hermetycznie pakowane warianty do odgrzania.';
    case 'kids':
      return 'Mniejsze zapiekanki 25 cm dla dzieci.';
    case 'udka':
      return 'Pakiety udek z kurczaka przygotowywane w transzach.';
    case 'lody':
      return 'Chlodne pozycje na deser i szybka przerwe.';
    case 'napoje':
      return 'Puszki i napoje do kompletu zamowienia.';
    default:
      return 'Chrupiace frytki do domkniecia zestawu.';
  }
}

String? _categoryEtaLabel(_DashboardCategory category) {
  if (category.key == 'udka') {
    return _udkaPickupCompactLabel();
  }

  if (category.items.isEmpty) {
    return null;
  }

  final minutes = category.items
      .map(_prepMinutes)
      .whereType<int>()
      .where((value) => value > 0)
      .toList(growable: false);
  if (minutes.isEmpty) {
    return null;
  }
  return 'do ${minutes.reduce(math.max)} min';
}

String _title(Map<String, dynamic> item, int fallbackIndex) =>
    item['name']?.toString() ??
    item['title']?.toString() ??
    item['position_name']?.toString() ??
    'Pozycja ${fallbackIndex + 1}';
String _description(Map<String, dynamic> item) {
  final value = item['description']?.toString().trim();
  return value == null || value.isEmpty
      ? 'Wyrozniona pozycja z dzisiejszego menu.'
      : value;
}

String? _photo(Map<String, dynamic> item) {
  final categoryKey = _categoryKeyForPosition(item);
  final value = item['photo_url']?.toString().trim();

  if (categoryKey == 'zapiekanki' || categoryKey == 'kids') {
    if (value != null && value.isNotEmpty && _isBundledAssetPhoto(value)) {
      return _normalizeBundledAssetPhoto(value);
    }
    return _deriveZapiekankaAssetPath(item) ?? 'assets/images/zapMeat.png';
  }

  if (categoryKey == 'udka') {
    if (value != null && value.isNotEmpty) {
      return _normalizePhotoValue(value);
    }
    return 'assets/images/chickenLeg.png';
  }

  if (value != null && value.isNotEmpty) {
    return _normalizePhotoValue(value);
  }

  return _deriveDrinkAssetPath(item);
}

String _normalizePhotoValue(String value) {
  return _isBundledAssetPhoto(value)
      ? _normalizeBundledAssetPhoto(value)
      : value;
}

class _UdkaPickupEstimate {
  const _UdkaPickupEstimate({
    required this.etaMinutes,
    required this.etaLabel,
    required this.scheduledPickupAt,
  });

  final int etaMinutes;
  final String etaLabel;
  final DateTime scheduledPickupAt;
}

String _udkaPickupEtaLabel({DateTime? now}) =>
    _formatScheduledPickupDetailed(_nextUdkaPickupSlot(now: now), now: now);

String _udkaPickupCompactLabel({DateTime? now}) =>
    _formatScheduledPickupCompact(_nextUdkaPickupSlot(now: now), now: now);

int _udkaPickupEtaMinutes({DateTime? now}) {
  final localNow = now ?? DateTime.now();
  final nextSlot = _nextUdkaPickupSlot(now: localNow);
  final deltaSeconds = nextSlot.difference(localNow).inSeconds;
  return ((math.max(0, deltaSeconds) + 59) / 60).floor();
}

String _formatScheduledPickupDetailed(
  DateTime scheduledPickupAt, {
  DateTime? now,
}) {
  final localSlot = scheduledPickupAt.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final hour = localSlot.hour.toString().padLeft(2, '0');
  final minute = localSlot.minute.toString().padLeft(2, '0');
  if (_isSameCalendarDay(localSlot, localNow)) {
    return 'Odbior o $hour:$minute';
  }
  return 'Odbior ${_pickupDateLabel(localSlot)} $hour:$minute';
}

String _formatScheduledPickupCompact(
  DateTime scheduledPickupAt, {
  DateTime? now,
}) {
  final localSlot = scheduledPickupAt.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final hour = localSlot.hour.toString().padLeft(2, '0');
  final minute = localSlot.minute.toString().padLeft(2, '0');
  if (_isSameCalendarDay(localSlot, localNow)) {
    return '$hour:$minute';
  }
  return '${_pickupDateLabel(localSlot)} $hour:$minute';
}

String _pickupDateLabel(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month';
}

bool _isSameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

DateTime _nextUdkaPickupSlot({DateTime? now}) {
  final localNow = now ?? DateTime.now();
  const slotHours = <int>[12, 15, 18];
  for (final slotHour in slotHours) {
    final candidate = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      slotHour,
    );
    if (!candidate.isBefore(localNow)) {
      return candidate;
    }
  }

  final nextDay = localNow.add(const Duration(days: 1));
  return DateTime(nextDay.year, nextDay.month, nextDay.day, slotHours.first);
}

bool _containsUdkaCartEntries(Iterable<_CartEntry> entries) =>
    entries.any((entry) => _categoryKeyForPosition(entry.position) == 'udka');

bool _containsIceCreamCartEntries(Iterable<_CartEntry> entries) =>
    entries.any((entry) => _categoryKeyForPosition(entry.position) == 'lody');

int _cartEstimatedPrepMinutes(List<_CartEntry> entries) {
  return entries
      .map((entry) => _prepMinutes(entry.position))
      .whereType<int>()
      .where((minutes) => minutes > 0)
      .fold<int>(15, math.max);
}

Future<_UdkaPickupEstimate?> _fetchUdkaPickupEstimateForEntries(
  Iterable<_CartEntry> entries,
) async {
  final normalizedEntries = entries.toList(growable: false);
  if (!_containsUdkaCartEntries(normalizedEntries)) {
    return null;
  }

  final response = await http
      .post(
        Uri.parse('${AppConfig.apiBaseUrl}/checkout/pickup-slot-estimate'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'items': normalizedEntries
              .map(
                (entry) => {
                  'cart_entry_id': entry.id,
                  'position_id': _positionId(entry.position),
                  'name': _title(entry.position, 0),
                  'description': _description(entry.position),
                },
              )
              .toList(growable: false),
        }),
      )
      .timeout(const Duration(seconds: 6));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'Backend zwrocil ${response.statusCode}: ${response.body}',
    );
  }

  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw Exception(
      'Nieoczekiwany format odpowiedzi z /checkout/pickup-slot-estimate.',
    );
  }

  final scheduledPickupAt = DateTime.tryParse(
    decoded['scheduled_pickup_at']?.toString() ?? '',
  );
  if (scheduledPickupAt == null) {
    throw Exception(
      'Brak scheduled_pickup_at w odpowiedzi z /checkout/pickup-slot-estimate.',
    );
  }

  return _UdkaPickupEstimate(
    etaMinutes: _asInt(decoded['eta_minutes']) ?? 0,
    etaLabel: decoded['eta_label']?.toString() ?? '',
    scheduledPickupAt: scheduledPickupAt,
  );
}

DateTime? _scheduledPickupDateTimeForCheckout(
  CheckoutVerificationResponse checkout,
) {
  return checkout.scheduledPickupAt ?? checkout.activeUntil;
}

String _activeCheckoutEtaDisplay(CheckoutVerificationResponse checkout) {
  if (_checkoutContainsUdka(checkout)) {
    final scheduledPickupAt = _scheduledPickupDateTimeForCheckout(checkout);
    if (scheduledPickupAt != null) {
      return _formatScheduledPickupCompact(scheduledPickupAt);
    }
  }

  final totalEta =
      checkout.receivedOrder.etaMinutes <= 0 ? 1 : checkout.receivedOrder.etaMinutes;
  final remainingEta = checkout.remainingEtaMinutes ?? totalEta;
  return '${remainingEta.clamp(0, 999)} min';
}

bool _checkoutContainsUdka(CheckoutVerificationResponse checkout) {
  return checkout.receivedOrder.items.any((item) {
    final signature =
        '${item.name} ${item.description ?? ''}'.trim().toLowerCase();
    return signature.contains('udk') || signature.contains('chicken leg');
  });
}

String? _deriveZapiekankaAssetPath(Map<String, dynamic> item) {
  final categoryKey = _categoryKeyForPosition(item);
  if (categoryKey != 'zapiekanki' && categoryKey != 'kids') {
    return null;
  }

  final title = _title(item, 0).trim().toLowerCase();
  if (title.isEmpty) {
    return null;
  }

  final isFrozen = _isFrozenPosition(item);
  if (title.contains('jalape') && title.contains('salame')) {
    return 'assets/images/zapJalapengoSalame.png';
  }
  if (title.contains('szynk') || title.contains('meat')) {
    return isFrozen
        ? 'assets/images/zapMeatFrozen.png'
        : 'assets/images/zapMeat.png';
  }
  if (title.contains('pieczark') || title.contains('mushroom')) {
    return isFrozen
        ? 'assets/images/zapMushroomFrozen.png'
        : 'assets/images/zapMushroom.png';
  }
  if (title.contains('serow') || title.contains('cheese')) {
    return isFrozen
        ? 'assets/images/zapCheeseFrozen.png'
        : 'assets/images/zapCheese.png';
  }
  if (title.contains('salame')) {
    return isFrozen
        ? 'assets/images/zapSalameFrozen.png'
        : 'assets/images/zapSalame.png';
  }

  return null;
}

String? _deriveDrinkAssetPath(Map<String, dynamic> item) {
  if (_categoryKeyForPosition(item) != 'napoje') {
    return null;
  }

  final rawTitle = _title(item, 0).trim().toLowerCase();
  if (rawTitle.isEmpty) {
    return null;
  }

  final volumeMatches =
      RegExp(r'(\d+(?:[.,]\d+)?)\s*(ml|l)?').allMatches(rawTitle).toList();
  if (volumeMatches.isEmpty) {
    return null;
  }
  final volumeMatch = volumeMatches.last;

  final volumeValue = volumeMatch.group(1)?.trim() ?? '';
  final volumeUnit = (volumeMatch.group(2) ?? '').trim().toLowerCase();
  if (volumeValue.isEmpty) {
    return null;
  }

  final brandPart = rawTitle.substring(0, volumeMatch.start);
  final brandSlug = _slugifyDrinkName(
    brandPart
        .replaceAll(RegExp(r'\b(puszka|butelka|but|pet|can)\b'), ' ')
        .trim(),
  );
  if (brandSlug.isEmpty) {
    return null;
  }

  final volumeSlug = _drinkVolumeSlug(
    value: volumeValue,
    unit: volumeUnit,
  );
  if (volumeSlug == null || volumeSlug.isEmpty) {
    return null;
  }

  return 'assets/images/$brandSlug$volumeSlug.png';
}

String _slugifyDrinkName(String value) {
  final normalized = value
      .replaceAll('ą', 'a')
      .replaceAll('ć', 'c')
      .replaceAll('ę', 'e')
      .replaceAll('ł', 'l')
      .replaceAll('ń', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ś', 's')
      .replaceAll('ż', 'z')
      .replaceAll('ź', 'z');

  return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String? _drinkVolumeSlug({
  required String value,
  required String unit,
}) {
  final normalizedValue = value.replaceAll(',', '.');

  if (unit == 'ml') {
    return normalizedValue.replaceAll(RegExp(r'[^0-9]'), '');
  }

  if (normalizedValue.contains('.')) {
    return normalizedValue.replaceAll('.', '');
  }

  final parsedInt = int.tryParse(normalizedValue);
  if (parsedInt == null) {
    return null;
  }

  if (parsedInt >= 100) {
    return parsedInt.toString();
  }

  return normalizedValue;
}

bool _isBundledAssetPhoto(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('assets/') || normalized.startsWith('/assets/');
}

String _normalizeBundledAssetPhoto(String value) {
  final trimmed = value.trim();
  return trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
}

int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

double? _price(Map<String, dynamic> item) {
  final raw = item['price'];
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.replaceAll(',', '.'));
  return null;
}

int? _prepMinutes(Map<String, dynamic> item) {
  final raw = item['prep_minutes'];
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw);
  }
  return null;
}

int _prepMinutesOrFallback(Map<String, dynamic> item, {int fallback = 15}) {
  final minutes = _prepMinutes(item);
  if (minutes == null || minutes <= 0) {
    return fallback;
  }
  return minutes;
}

int? _positionId(Map<String, dynamic> item) {
  final raw = item['position_id'] ?? item['id'];
  if (raw is int) return raw;
  if (raw is String) return int.tryParse(raw);
  return null;
}

int? _positionCalories(Map<String, dynamic> item) {
  final raw = item['calories'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

String _checkoutItemDescription(_CartEntry entry) {
  final base = _description(entry.position);
  final serving = _servingSummary(entry.customization);
  final extrasChanges = _extrasChangesSummary(entry.customization);
  final parts = <String>[base];
  if (serving != null) {
    parts.add('Ustawienia: $serving');
  }
  if (extrasChanges != null) {
    parts.add('Dodatki: $extrasChanges');
  }
  return parts.join(' | ');
}

double _entryPrice(_CartEntry entry) {
  return (_price(entry.position) ?? 0) + _extrasPriceTotal(entry.customization);
}

String _entryPriceLabel(_CartEntry entry) => 'PLN ${_fmt(_entryPrice(entry))}';

String _priceLabel(Map<String, dynamic> item) =>
    _price(item) == null ? 'PLN --' : 'PLN ${_fmt(_price(item)!)}';
String _fmt(double value) => value.toStringAsFixed(2);
String _kcal(Map<String, dynamic> item) =>
    item['calories'] == null ? '-- kcal' : '${item['calories']} kcal';
String? _servingSummary(_CartCustomization customization) {
  if (!customization.servingOptionsEnabled) {
    return null;
  }
  return [
    _cutOptionLabel(customization.cutOption),
    _packagingOptionLabel(customization.packagingOption),
  ].join(', ');
}

String? _extrasChangesSummary(_CartCustomization customization) {
  final changes = _extrasChanges(customization);
  if (changes.isEmpty) {
    return null;
  }
  return changes.join(', ');
}

List<String> _personalizationChips(_CartCustomization customization) {
  final chips = <String>[
    if (customization.servingOptionsEnabled) ...[
      _cutOptionLabel(customization.cutOption),
      _packagingOptionLabel(customization.packagingOption),
    ],
  ];
  final entries = customization.extras.entries
      .where((entry) => entry.value > 0)
      .toList()
    ..sort((first, second) => first.key.compareTo(second.key));
  chips.addAll(
    entries.map(
      (entry) => entry.value == 1 ? entry.key : '${entry.key} x${entry.value}',
    ),
  );
  return chips;
}

List<String> _personalizationEmojiBadges(_CartCustomization customization) {
  final chips = <String>[
    if (customization.servingOptionsEnabled) ...[
      _cutOptionBadge(customization.cutOption),
      _packagingOptionBadge(customization.packagingOption),
    ],
  ];
  final entries = customization.extras.entries
      .where((entry) => entry.value > 0)
      .toList()
    ..sort((first, second) => first.key.compareTo(second.key));
  chips.addAll(
    entries.map((entry) {
      final emoji = customization.extraEmojis[entry.key] ??
          _fallbackExtraEmoji(entry.key);
      return entry.value == 1 ? emoji : '$emoji x${entry.value}';
    }),
  );
  return chips;
}

double _extrasPriceTotal(_CartCustomization customization) {
  var total = 0.0;
  for (final entry in customization.extras.entries) {
    final selectedCount = entry.value;
    final includedCount = customization.defaultExtras[entry.key] ?? 0;
    final paidCount = selectedCount - includedCount;
    if (paidCount > 0) {
      total += paidCount * (customization.extraUnitPrices[entry.key] ?? 0);
    }
  }
  return total;
}

List<String> _extrasChanges(_CartCustomization customization) {
  final changes = <String>[];
  final labels = customization.extras.keys.toList(growable: false)..sort();
  for (final label in labels) {
    final selectedCount = customization.extras[label] ?? 0;
    final includedCount = customization.defaultExtras[label] ?? 0;
    final delta = selectedCount - includedCount;
    if (delta == 0) {
      continue;
    }
    final sign = delta > 0 ? '+' : '-';
    final absoluteDelta = delta.abs();
    changes.add(
      absoluteDelta == 1 ? '$sign$label' : '$sign$label x$absoluteDelta',
    );
  }
  return changes;
}

String _fallbackExtraEmoji(String label) {
  switch (label.toLowerCase()) {
    case 'pomidory':
      return '🍅';
    case 'oliwki':
      return '🫒';
    case 'prazona cebulka':
      return '🧅';
    case 'sos bbq':
      return '🍖';
    case 'surowka kolorowa':
      return '🥗';
    case 'ketchup':
      return '🍅';
    case 'sos tysiaca wysp':
      return '🥫';
  }
  return '✨';
}

String _cutOptionLabel(_CutOption option) {
  switch (option) {
    case _CutOption.whole:
      return 'Calosc';
    case _CutOption.cutInHalf:
      return 'Cieta na pol';
  }
}

String _packagingOptionLabel(_PackagingOption option) {
  switch (option) {
    case _PackagingOption.paperTray:
      return 'Tacka papierowa';
    case _PackagingOption.box:
      return 'Pudelko';
  }
}

String _cutOptionBadge(_CutOption option) {
  switch (option) {
    case _CutOption.whole:
      return 'CALA';
    case _CutOption.cutInHalf:
      return '1/2';
  }
}

String _packagingOptionBadge(_PackagingOption option) {
  switch (option) {
    case _PackagingOption.paperTray:
      return 'TACKA';
    case _PackagingOption.box:
      return 'BOX';
  }
}

bool _supportsZapiekankaServingOptions(Map<String, dynamic> position) {
  if (_isFrozenPosition(position)) {
    return false;
  }
  final positionType =
      position['position_type']?.toString().toLowerCase() ?? '';
  final name = _title(position, 0).toLowerCase();
  return positionType.contains('zapiek') || name.contains('zapiek');
}

bool _isFrozenPosition(Map<String, dynamic> position) {
  final positionType =
      position['position_type']?.toString().trim().toLowerCase() ?? '';
  final title = _title(position, 0).trim().toLowerCase();
  final description = _description(position).trim().toLowerCase();
  final haystack = '$positionType $title $description';
  return haystack.contains('frozen') ||
      haystack.contains('mroz') ||
      haystack.contains('zamroz') ||
      haystack.contains('odgrzan');
}

BoxFit _positionImageFit(
  Map<String, dynamic> item, {
  bool compact = false,
}) {
  if (compact && _categoryKeyForPosition(item) == 'lody') {
    return BoxFit.contain;
  }
  if (_categoryKeyForPosition(item) == 'lody') {
    return BoxFit.contain;
  }
  return BoxFit.cover;
}

Alignment _positionImageAlignment(
  Map<String, dynamic> item, {
  bool compact = false,
}) {
  if (_categoryKeyForPosition(item) == 'lody') {
    if (compact) {
      return const Alignment(0, -0.92);
    }
    return Alignment.topCenter;
  }
  return Alignment.center;
}

EdgeInsets _positionImagePadding(
  Map<String, dynamic> item, {
  bool compact = false,
}) {
  if (_categoryKeyForPosition(item) == 'lody' && compact) {
    return const EdgeInsets.fromLTRB(10, 2, 10, 12);
  }
  return EdgeInsets.zero;
}

bool _isPositionAvailable(Map<String, dynamic> position) {
  final raw = position['is_active'];
  if (raw is bool) {
    return raw;
  }
  if (raw is num) {
    return raw != 0;
  }
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    return normalized != 'false' && normalized != '0';
  }
  return true;
}

_CartCustomization _initialCustomizationFor(Map<String, dynamic> position) {
  return _CartCustomization(
    servingOptionsEnabled: _supportsZapiekankaServingOptions(position),
  );
}

String _paymentBrand(String label) {
  switch (label) {
    case 'BLIK':
      return 'blik';
    case 'Apple Pay':
      return 'Pay';
    case 'Google Pay':
      return 'G Pay';
  }
  return label;
}

Object _positionKey(Map<String, dynamic> item) =>
    item['position_id'] ?? item['id'] ?? item['name'] ?? item.hashCode;
bool _samePosition(Map<String, dynamic>? first, Map<String, dynamic>? second) =>
    first != null &&
    second != null &&
    _positionKey(first) == _positionKey(second);

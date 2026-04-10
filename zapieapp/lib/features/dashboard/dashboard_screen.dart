import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../router/app_router.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _backgroundAsset = 'assets/images/background_big_ingredients_darker.png';
  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  late Future<List<Map<String, dynamic>>> _positionsFuture;
  Map<String, dynamic>? _selectedPosition;
  final List<_CartEntry> _cart = [];
  int _nextCartEntryId = 1;
  int _activeFooterIndex = 1;

  @override
  void initState() {
    super.initState();
    _positionsFuture = _fetchPositions();
  }

  Future<List<Map<String, dynamic>>> _fetchPositions() async {
    final response = await http
        .get(Uri.parse('$_apiBaseUrl/positions'), headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw Exception('Nieoczekiwany format odpowiedzi z /positions.');
    }

    return decoded
        .map((item) => item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map))
        .toList();
  }

  void _reload() {
    setState(() {
      _positionsFuture = _fetchPositions();
    });
  }

  void _selectPosition(Map<String, dynamic> position) {
    setState(() {
      _selectedPosition = position;
    });

    showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _ProductPreviewDialog(
        position: position,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  void _addToCart(Map<String, dynamic> position) {
    setState(() {
      _selectedPosition = position;
      _cart.add(
        _CartEntry(
          id: _nextCartEntryId++,
          position: position,
        ),
      );
    });
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
      _nextCartEntryId = _cart.fold<int>(0, (maxId, entry) => entry.id > maxId ? entry.id : maxId) + 1;
    });
  }

  void _openCartSummary() {
    if (_cart.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CartSummaryScreen(
          initialEntries: _resolvedCartEntries(const <Map<String, dynamic>>[]),
          onCartChanged: _replaceCart,
        ),
      ),
    );
  }

  Map<String, dynamic>? _resolveSelected(List<Map<String, dynamic>> positions) {
    if (positions.isEmpty) return null;
    if (_selectedPosition == null) return positions.first;
    for (final item in positions) {
      if (_samePosition(item, _selectedPosition)) return item;
    }
    return positions.first;
  }

  List<({String title, List<Map<String, dynamic>> items})> _sections(List<Map<String, dynamic>> positions) {
    if (positions.isEmpty) return const [];
    return [
      (title: 'Popularne', items: _rotatedTake(positions, 0)),
      (title: 'Ostatnio zamawiane', items: _rotatedTake(positions.reversed.toList(), 0)),
      (title: 'Ulubione pozycje', items: _rotatedTake(positions, positions.length > 2 ? 1 : 0)),
    ];
  }

  List<_CartEntry> _resolvedCartEntries(List<Map<String, dynamic>> positions) {
    return _cart
        .map((entry) {
          for (final position in positions) {
            if (_samePosition(entry.position, position)) {
              return entry.copyWith(position: position);
            }
          }
          return entry;
        })
        .toList(growable: false);
  }

  int _cartQuantityFor(
    Map<String, dynamic> position,
    List<_CartEntry> cartEntries,
  ) {
    var count = 0;
    for (final entry in cartEntries) {
      if (_samePosition(entry.position, position)) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _positionsFuture,
      builder: (context, snapshot) {
        final positions = snapshot.data ?? const <Map<String, dynamic>>[];
        final selected = _resolveSelected(positions);
        final cartEntries = _resolvedCartEntries(positions);

        Widget body;
        if (snapshot.connectionState != ConnectionState.done) {
          body = const Center(child: CircularProgressIndicator(color: Color(0xFFE97F2A)));
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
            message: 'Gdy backend zwroci dane z /positions, dashboard automatycznie uzupelni sekcje i koszyk.',
          );
        } else {
          final sections = _sections(positions);
          body = SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _positionsFuture;
              },
              child: ListView(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: EdgeInsets.fromLTRB(14, 12, 14, cartEntries.isEmpty ? 110 : 206),
                children: [
                  _TopBar(
                    onReload: _reload,
                    onLogout: () => Navigator.pushReplacementNamed(context, AppRoutes.login),
                  ),
                  const SizedBox(height: 14),
                  for (final section in sections) ...[
                    _SectionBlock(
                      title: section.title,
                      items: section.items,
                      selected: selected,
                      cartQuantityFor: (item) => _cartQuantityFor(item, cartEntries),
                      onSelect: _selectPosition,
                      onAddToCart: _addToCart,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _CategoryBlock(
                    positions: positions,
                    selected: selected,
                    onSelect: _selectPosition,
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          extendBody: true,
          body: _Background(child: body),
          bottomNavigationBar: _BottomChrome(
            cartEntries: cartEntries,
            activeFooterIndex: _activeFooterIndex,
            onSelect: _selectPosition,
            onRemove: _removeFromCart,
            onContinue: _openCartSummary,
            onFooterTap: (index, label) {
              setState(() => _activeFooterIndex = index);
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
        image: DecorationImage(image: AssetImage(_DashboardScreenState._backgroundAsset), fit: BoxFit.cover),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onReload, required this.onLogout});

  final VoidCallback onReload;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        _IconCircle(icon: Icons.refresh_rounded, onTap: onReload),
        const SizedBox(width: 8),
        _IconCircle(icon: Icons.logout_rounded, onTap: onLogout),
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.items,
    required this.selected,
    required this.cartQuantityFor,
    required this.onSelect,
    required this.onAddToCart,
  });

  final String title;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic>? selected;
  final int Function(Map<String, dynamic>) cartQuantityFor;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<Map<String, dynamic>> onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardWidth = MediaQuery.of(context).size.width < 460 ? 182.0 : 206.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge?.copyWith(color: const Color(0xFFF8EEE7), fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        SizedBox(
          height: 252,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => SizedBox(
              width: cardWidth,
              child: _MenuCard(
                position: items[i],
                index: i,
                selected: _samePosition(items[i], selected),
                cartQuantity: cartQuantityFor(items[i]),
                onTap: () => onSelect(items[i]),
                onAddToCart: () => onAddToCart(items[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.position,
    required this.index,
    required this.selected,
    required this.cartQuantity,
    required this.onTap,
    required this.onAddToCart,
  });

  final Map<String, dynamic> position;
  final int index;
  final bool selected;
  final int cartQuantity;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title(position, index);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xE6121111),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? const Color(0xFFF08B2D) : const Color(0x26FFFFFF), width: selected ? 1.4 : 1),
            boxShadow: selected ? const [BoxShadow(color: Color(0x40190B03), blurRadius: 18, offset: Offset(0, 10))] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 148,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: _PositionImage(photoUrl: _photo(position), title: title)),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _TinyBadge(
                        icon: Icons.shopping_bag_outlined,
                        active: cartQuantity > 0,
                        label: cartQuantity > 0 ? '$cartQuantity' : null,
                        onTap: onAddToCart,
                      ),
                    ),
                    const Positioned(top: 6, right: 6, child: _TinyBadge(icon: Icons.favorite_border_rounded, active: false)),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _PricePill(label: _priceLabel(position)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFFF7EEE8), fontWeight: FontWeight.w700, height: 1.15)),
              const SizedBox(height: 4),
              Text(_description(position), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xCCCFBBAE), height: 1.2)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(_priceLabel(position), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: const Color(0xFFF4D8C6), fontWeight: FontWeight.w700))),
                  Text(_kcal(position), style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF918076))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({required this.positions, required this.selected, required this.onSelect});

  final List<Map<String, dynamic>> positions;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = [
      ('Zapiekanki', Icons.view_agenda_rounded, const Color(0xFFF28A2A), const Color(0xFFCC5C1F), _pick(positions, 0)),
      ('Lody', Icons.icecream_rounded, const Color(0xFF3AB6BF), const Color(0xFF207E90), _pick(positions, 1)),
      ('Napoje', Icons.local_drink_rounded, const Color(0xFFD5442F), const Color(0xFFA61F1B), _pick(positions, 2)),
      ('Dodatki', Icons.lunch_dining_rounded, const Color(0xFFE1662A), const Color(0xFFB83B18), _pick(positions, 3)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kategorie', style: theme.textTheme.titleLarge?.copyWith(color: const Color(0xFFF8EEE7), fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var index = 0; index < categories.length; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              Expanded(
                child: _CategoryTile(
                  title: categories[index].$1,
                  icon: categories[index].$2,
                  startColor: categories[index].$3,
                  endColor: categories[index].$4,
                  selected: _samePosition(categories[index].$5, selected),
                  onTap: categories[index].$5 == null ? null : () => onSelect(categories[index].$5!),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.title, required this.icon, required this.startColor, required this.endColor, required this.selected, required this.onTap});

  final String title;
  final IconData icon;
  final Color startColor;
  final Color endColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [startColor, endColor], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? const Color(0xFFFBE6D8) : const Color(0x14FFFFFF)),
            boxShadow: [BoxShadow(color: endColor.withOpacity(0.35), blurRadius: selected ? 18 : 12, offset: const Offset(0, 10))],
          ),
          child: AspectRatio(
            aspectRatio: 0.86,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: const Color(0xFFFFECDD), size: 34),
                const Spacer(),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(color: const Color(0xFFFFF5EF), fontWeight: FontWeight.w800, height: 1.05)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomChrome extends StatelessWidget {
  const _BottomChrome({
    required this.cartEntries,
    required this.activeFooterIndex,
    required this.onSelect,
    required this.onRemove,
    required this.onContinue,
    required this.onFooterTap,
  });

  final List<_CartEntry> cartEntries;
  final int activeFooterIndex;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<int> onRemove;
  final VoidCallback onContinue;
  final void Function(int index, String label) onFooterTap;

  @override
  Widget build(BuildContext context) {
    final total = cartEntries.fold<double>(
      0,
      (sum, entry) => sum + (_price(entry.position) ?? 0),
    );
    final footer = [(Icons.receipt_long_outlined, 'Menu'), (Icons.emoji_events_outlined, 'Nagrody'), (Icons.person_rounded, 'Profil')];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cartEntries.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(color: const Color(0xED2A231E), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x2BFFFFFF))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [const Icon(Icons.shopping_cart_outlined, size: 16, color: Color(0xFFF0D7C7)), const SizedBox(width: 6), Text('Koszyk', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: const Color(0xFFF7E7DD), fontWeight: FontWeight.w700))]),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 104,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: cartEntries.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (context, index) => _CartThumb(
                                    entry: cartEntries[index],
                                    onTap: () => onSelect(cartEntries[index].position),
                                    onRemove: () => onRemove(cartEntries[index].id),
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
                            Text('PLN ${_fmt(total)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFFFFF3EA), fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text('${cartEntries.length} szt.', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFFF0DDCF), fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFFEBD7C8)), const SizedBox(width: 4), Text('15 min', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFEBD7C8)))]),
                            const SizedBox(height: 10),
                            FilledButton(
                              onPressed: onContinue,
                              style: FilledButton.styleFrom(minimumSize: const Size(96, 42), backgroundColor: const Color(0xFFDD6B1F), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              child: const Text('DALEJ', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xEE3B3837), borderRadius: BorderRadius.circular(12)),
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
                              Icon(footer[i].$1, color: activeFooterIndex == i ? const Color(0xFFFFF0E7) : const Color(0xFFCEC3BC), size: 22),
                              const SizedBox(height: 4),
                              Text(footer[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: activeFooterIndex == i ? const Color(0xFFFFF0E7) : const Color(0xFFCEC3BC), fontWeight: FontWeight.w700)),
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

class _CartSummaryScreen extends StatefulWidget {
  const _CartSummaryScreen({
    required this.initialEntries,
    required this.onCartChanged,
  });

  final List<_CartEntry> initialEntries;
  final ValueChanged<List<_CartEntry>> onCartChanged;

  @override
  State<_CartSummaryScreen> createState() => _CartSummaryScreenState();
}

class _CartSummaryScreenState extends State<_CartSummaryScreen> {
  late List<_CartEntry> _entries;
  int _fulfillmentIndex = 0;
  int _addressIndex = 0;
  String? _selectedPaymentMethod;

  static const _fulfillmentOptions = <({String label, IconData icon})>[
    (label: 'Dostawa', icon: Icons.delivery_dining_rounded),
    (label: 'Odbior na miejscu', icon: Icons.storefront_rounded),
    (label: 'Zaplanuj odbior', icon: Icons.schedule_rounded),
  ];

  static const _addresses = <({String title, String subtitle})>[
    (title: 'Sklotowa 6/9', subtitle: '02-220, Warszawa'),
    (title: 'Mefedronowa 20', subtitle: '02-225, Warszawa'),
  ];

  @override
  void initState() {
    super.initState();
    _entries = List<_CartEntry>.from(widget.initialEntries);
  }

  void _syncEntries() {
    widget.onCartChanged(List<_CartEntry>.from(_entries));
  }

  void _removeEntry(int id) {
    setState(() {
      _entries.removeWhere((entry) => entry.id == id);
    });
    _syncEntries();
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
            requestPayload: payload,
          ),
        ),
      );
    }
  }

  Map<String, dynamic> _buildOrderPayload(String paymentMethod) {
    final selectedAddress = _addresses[_addressIndex];
    final total = _entries.fold<double>(0, (sum, entry) => sum + (_price(entry.position) ?? 0));

    return {
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'currency': 'PLN',
      'total_amount': total,
      'eta_minutes': 15,
      'payment_method': paymentMethod,
      'fulfillment_method': _fulfillmentOptions[_fulfillmentIndex].label,
      'fulfillment_option_index': _fulfillmentIndex,
      'address_option_index': _addressIndex,
      'address': {
        'title': selectedAddress.title,
        'subtitle': selectedAddress.subtitle,
        'eta_label': _addressIndex == 0 ? '~25 min.' : '~40 min.',
      },
      'items': _entries
          .map(
            (entry) => {
              'cart_entry_id': entry.id,
              'position_id': _positionId(entry.position),
              'name': _title(entry.position, 0),
              'description': _description(entry.position),
              'photo_url': _photo(entry.position),
              'calories': _positionCalories(entry.position),
              'price': _price(entry.position),
            },
          )
          .toList(growable: false),
      'notes': 'Wstepna weryfikacja checkout z aplikacji mobilnej',
    };
  }

  @override
  Widget build(BuildContext context) {
    final total = _entries.fold<double>(0, (sum, entry) => sum + (_price(entry.position) ?? 0));

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
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: const Color(0xFFD5C7BA),
                                      ),
                                ),
                              )
                            : ScrollConfiguration(
                                behavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
                                child: ListView.separated(
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: _entries.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) => _SummaryProductTile(
                                    entry: _entries[index],
                                    onRemove: () => _removeEntry(_entries[index].id),
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
                          Row(
                            children: [
                              for (var index = 0; index < _fulfillmentOptions.length; index++) ...[
                                if (index > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: _FulfillmentTile(
                                    label: _fulfillmentOptions[index].label,
                                    icon: _fulfillmentOptions[index].icon,
                                    isSelected: _fulfillmentIndex == index,
                                    onTap: () => setState(() => _fulfillmentIndex = index),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Adres dostawy',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: const Color(0xFFF8EEDF),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (var index = 0; index < _addresses.length; index++) ...[
                                if (index > 0) const SizedBox(width: 10),
                                Expanded(
                                  child: _AddressTile(
                                    title: _addresses[index].title,
                                    subtitle: _addresses[index].subtitle,
                                    eta: index == 0 ? '~25 min.' : '~40 min.',
                                    isSelected: _addressIndex == index,
                                    onTap: () => setState(() => _addressIndex = index),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 10),
                              _AddAddressTile(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Dodawanie nowego adresu dodamy dalej.')),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          'TOTAL',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: const Color(0xFFF8F0E8),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _SummaryMetricPill(
                            child: Text(
                              'PLN ${_fmt(total)}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                                const Icon(Icons.access_time_rounded, color: Color(0xFFF0DDD0)),
                                const SizedBox(width: 8),
                                Text(
                                  '15 min.',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _entries.isEmpty
                          ? null
                          : _showPaymentMethodsDialog,
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
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
    required this.requestPayload,
  });

  final String paymentMethod;
  final Map<String, dynamic> requestPayload;

  @override
  State<_PaymentVerificationScreen> createState() => _PaymentVerificationScreenState();
}

class _PaymentVerificationScreenState extends State<_PaymentVerificationScreen> {
  late Future<Map<String, dynamic>> _verificationFuture;

  @override
  void initState() {
    super.initState();
    _verificationFuture = _sendVerificationRequest();
  }

  Future<Map<String, dynamic>> _sendVerificationRequest() async {
    final response = await http
        .post(
          Uri.parse('${_DashboardScreenState._apiBaseUrl}/checkout/verification'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(widget.requestPayload),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Backend zwrocil ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw Exception('Nieoczekiwany format odpowiedzi z /checkout/verification.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _Background(
        child: SafeArea(
          bottom: false,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _verificationFuture,
            builder: (context, snapshot) {
              final theme = Theme.of(context);
              final isLoading = snapshot.connectionState != ConnectionState.done;
              final hasError = snapshot.hasError;
              final responseData = snapshot.data;
              final jsonToShow = hasError
                  ? <String, dynamic>{
                      'request_payload': widget.requestPayload,
                      'error': snapshot.error.toString(),
                    }
                  : responseData == null
                      ? <String, dynamic>{
                          'request_payload': widget.requestPayload,
                          'status': 'sending',
                        }
                      : <String, dynamic>{
                          'request_payload': widget.requestPayload,
                          'backend_response': responseData,
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
                                        hasError ? Icons.error_outline_rounded : Icons.verified_outlined,
                                        color: hasError ? const Color(0xFFFF8975) : const Color(0xFFFFB15B),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.paymentMethod,
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        color: const Color(0xFFF8EEE7),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isLoading
                                          ? 'Wysylamy szczegoly zamowienia do backendu i przygotowujemy etap wstepnej weryfikacji.'
                                          : hasError
                                              ? 'Nie udalo sie wyslac zamowienia do backendu.'
                                              : (responseData?['message']?.toString() ?? 'Backend przyjal dane do wstepnej weryfikacji.'),
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: const Color(0xFFD9C6B9),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _SummarySection(
                          title: 'JSON zamowienia',
                          child: SizedBox(
                            height: 320,
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: SelectableText(
                                const JsonEncoder.withIndent('  ').convert(jsonToShow),
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
  const _StateCard({required this.icon, required this.title, required this.message, this.buttonLabel, this.onPressed});

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
                  Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: const Color(0xFFF8EEE7), fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFFD8C5B8), height: 1.4)),
                  if (buttonLabel != null && onPressed != null) ...[
                    const SizedBox(height: 18),
                    FilledButton(onPressed: onPressed, child: Text(buttonLabel!)),
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: SizedBox(
                    height: 250,
                    width: double.infinity,
                    child: _PositionImage(
                      photoUrl: _photo(position),
                      title: title,
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
    required this.onRemove,
  });

  final _CartEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 82,
              height: double.infinity,
              child: _PositionImage(
                photoUrl: _photo(entry.position),
                title: _title(entry.position, 0),
              ),
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
                  child: _SummaryActionIcon(icon: Icons.delete_outline_rounded, onTap: onRemove),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _priceLabel(entry.position),
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
            color: isSelected ? const Color(0x40FFB061) : const Color(0x10FFFFFF),
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
            color: isSelected ? const Color(0x33FFD199) : const Color(0x12FFFFFF),
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
                const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFFF0DDD0)),
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
        child: const Icon(Icons.add_rounded, color: Color(0xFFF6E8D9), size: 34),
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
    const footer = [(Icons.receipt_long_outlined, 'Menu'), (Icons.emoji_events_outlined, 'Nagrody'), (Icons.person_rounded, 'Profil')];

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
                    Icon(footer[i].$1, color: const Color(0xFFCEC3BC), size: 22),
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
              child: _PositionImage(
                photoUrl: _photo(entry.position),
                title: _title(entry.position, 0),
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
        decoration: BoxDecoration(color: const Color(0x1CFFFFFF), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0x2CFFFFFF))),
        child: Icon(icon, color: const Color(0xFFF4E5DB), size: 20),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({
    required this.icon,
    required this.active,
    this.label,
    this.onTap,
  });

  final IconData icon;
  final bool active;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE77A27) : const Color(0x7A0E0D0C),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: active ? Colors.white : const Color(0xFFF5E6D9)),
              if (label != null) ...[
                const SizedBox(width: 3),
                Text(
                  label!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
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
    final accent = isSelected ? const Color(0xFFFFA247) : const Color(0xFF615852);

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
          border: Border.all(color: accent.withOpacity(0.55)),
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

class _RemoveThumbButton extends StatelessWidget {
  const _RemoveThumbButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 22,
          width: 22,
          decoration: BoxDecoration(
            color: const Color(0xE81B1512),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 13,
            color: Color(0xFFFFE9DA),
          ),
        ),
      ),
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
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, Colors.transparent])),
      ),
    );
  }
}

class _PositionImage extends StatelessWidget {
  const _PositionImage({required this.photoUrl, required this.title});

  final String? photoUrl;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.trim().isNotEmpty) {
      return Image.network(photoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(context));
    }
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2D1C16), Color(0xFF594036)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fastfood_rounded, size: 26, color: Color(0xFFFFE9D9)),
            const SizedBox(height: 6),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFFFFF0E6), fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _CartEntry {
  const _CartEntry({
    required this.id,
    required this.position,
  });

  final int id;
  final Map<String, dynamic> position;

  _CartEntry copyWith({
    int? id,
    Map<String, dynamic>? position,
  }) {
    return _CartEntry(
      id: id ?? this.id,
      position: position ?? this.position,
    );
  }
}

List<Map<String, dynamic>> _rotatedTake(List<Map<String, dynamic>> positions, int offset) {
  if (positions.isEmpty) return const [];
  final start = offset % positions.length;
  return [...positions.skip(start), ...positions.take(start)].take(3).toList();
}

Map<String, dynamic>? _pick(List<Map<String, dynamic>> positions, int index) {
  if (positions.isEmpty) return null;
  return positions[index < positions.length ? index : 0];
}

String _title(Map<String, dynamic> item, int fallbackIndex) => item['name']?.toString() ?? item['title']?.toString() ?? item['position_name']?.toString() ?? 'Pozycja ${fallbackIndex + 1}';
String _description(Map<String, dynamic> item) {
  final value = item['description']?.toString().trim();
  return value == null || value.isEmpty ? 'Wyrozniona pozycja z dzisiejszego menu.' : value;
}
String? _photo(Map<String, dynamic> item) {
  final value = item['photo_url']?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}
double? _price(Map<String, dynamic> item) {
  final raw = item['price'];
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.replaceAll(',', '.'));
  return null;
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
String _priceLabel(Map<String, dynamic> item) => _price(item) == null ? 'PLN --' : 'PLN ${_fmt(_price(item)!)}';
String _fmt(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
String _kcal(Map<String, dynamic> item) => item['calories'] == null ? '-- kcal' : '${item['calories']} kcal';
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
Object _positionKey(Map<String, dynamic> item) => item['position_id'] ?? item['id'] ?? item['name'] ?? item.hashCode;
bool _samePosition(Map<String, dynamic>? first, Map<String, dynamic>? second) => first != null && second != null && _positionKey(first) == _positionKey(second);

import 'package:flutter/material.dart';

import '../../data/local/session_persistence.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/checkout_verification.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../router/app_router.dart';
import 'order_tracking_screen.dart';

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({
    super.key,
    required this.authSession,
    required this.checkoutRepository,
    this.activeCheckout,
  });

  final AuthSession authSession;
  final CheckoutRepository checkoutRepository;
  final CheckoutVerificationResponse? activeCheckout;

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  static const _backgroundAsset =
      'assets/images/background_big_ingredients_darker.png';
  static const _pageSize = 10;
  static const _loadMoreTriggerOffset = 220.0;

  final List<CheckoutVerificationResponse> _orders =
      <CheckoutVerificationResponse>[];
  late final ScrollController _scrollController = ScrollController()
    ..addListener(_handleScroll);
  Object? _error;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _nextPage = 1;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoading || _isLoadingMore || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    final remainingScroll = position.maxScrollExtent - position.pixels;
    if (remainingScroll <= _loadMoreTriggerOffset) {
      _loadMore();
    }
  }

  void _scheduleAutoLoadMoreCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _handleScroll();
    });
  }

  Future<void> _loadHistory({bool reset = true}) async {
    if (reset) {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _error = null;
          _nextPage = 1;
          _totalCount = 0;
          _hasMore = false;
        });
      }
    } else if (mounted) {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final page = await widget.checkoutRepository.fetchCheckoutHistory(
        sessionToken: widget.authSession.sessionToken,
        email: widget.authSession.email,
        page: reset ? 1 : _nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _orders
            ..clear()
            ..addAll(page.orders);
        } else {
          _orders.addAll(page.orders);
        }
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
        _nextPage = page.page + 1;
        _error = null;
        _isLoading = false;
        _isLoadingMore = false;
      });
      _scheduleAutoLoadMoreCheck();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadHistory();
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) {
      return;
    }
    await _loadHistory(reset: false);
  }

  Future<void> _openOrder(CheckoutVerificationResponse checkout) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderTrackingScreen(
          checkout: checkout,
          authSession: widget.authSession,
          checkoutRepository: widget.checkoutRepository,
          isHistoryView: true,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    await _refresh();
  }

  Future<void> _logout() async {
    widget.checkoutRepository.rememberActiveCheckout(null);
    await SessionPersistence.clearAll();
    if (!mounted) {
      return;
    }
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCheckout = widget.activeCheckout;

    return Scaffold(
      extendBody: true,
      body: _OrdersBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 110),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profil',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: const Color(0xFFF9EEE2),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ostatnie zamowienia i szybki podglad szczegolow.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFFD4C3B8),
                                  height: 1.35,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TopActionButton(
                      icon: Icons.logout_rounded,
                      onTap: _logout,
                    ),
                    const SizedBox(width: 8),
                    _TopActionButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ProfileHeroCard(
                  authSession: widget.authSession,
                  activeCheckout: activeCheckout,
                  onOpenActiveOrder: activeCheckout == null
                      ? null
                      : () => _openOrder(activeCheckout),
                ),
                const SizedBox(height: 18),
                _SectionTitle(
                  title: 'Ostatnie zamowienia',
                  subtitle:
                      'Pokazujemy zamkniete zamowienia z checkoutu. Zaladowano ${_orders.length} z $_totalCount.',
                ),
                const SizedBox(height: 12),
                if (_isLoading && _orders.isEmpty)
                  const _LoadingCard()
                else if (_error != null && _orders.isEmpty)
                  _MessageCard(
                    icon: Icons.wifi_off_rounded,
                    title: 'Nie udalo sie pobrac historii',
                    message: _error.toString(),
                    actionLabel: 'Sprobuj ponownie',
                    onAction: _refresh,
                  )
                else if (_orders.isEmpty)
                  const _MessageCard(
                    icon: Icons.history_toggle_off_rounded,
                    title: 'Brak ostatnich zamowien',
                    message:
                        'Gdy zakonczysz pierwsze zamowienie, pojawi sie tutaj jego podglad.',
                  )
                else ...[
                  ..._orders.map(
                    (order) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _OrderHistoryCard(
                        checkout: order,
                        onTap: () => _openOrder(order),
                      ),
                    ),
                  ),
                  if (_hasMore || _isLoadingMore || _error != null)
                    _LoadMoreCard(
                      isLoading: _isLoadingMore,
                      loadedCount: _orders.length,
                      totalCount: _totalCount,
                      error: _error,
                      onPressed: _loadMore,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrdersBackground extends StatelessWidget {
  const _OrdersBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(_OrderListScreenState._backgroundAsset),
          fit: BoxFit.cover,
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xF60A0908), Color(0xF1090808), Color(0xFF050505)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        height: 46,
        width: 46,
        decoration: BoxDecoration(
          color: const Color(0xF0131010),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Icon(icon, color: const Color(0xFFF8EEE7)),
      ),
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.authSession,
    required this.activeCheckout,
    this.onOpenActiveOrder,
  });

  final AuthSession authSession;
  final CheckoutVerificationResponse? activeCheckout;
  final VoidCallback? onOpenActiveOrder;

  @override
  Widget build(BuildContext context) {
    final email = authSession.email?.trim();
    final activeCheckout = this.activeCheckout;
    final displayLabel = email != null && email.isNotEmpty ? email : 'Twoje konto';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xD9161312),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x1BFFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2A000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayLabel,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFFF8EEE7),
                  fontWeight: FontWeight.w900,
                ),
          ),
          if (email != null && email.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              email,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFD8C7BA),
                  ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.emoji_events_outlined,
                label: '${authSession.loyaltyPoints} pkt',
              ),
              _MetricChip(
                icon: Icons.receipt_long_outlined,
                label: activeCheckout == null
                    ? 'Brak aktywnego'
                    : 'Aktywne #${activeCheckout.savedOrderId}',
              ),
            ],
          ),
          if (activeCheckout != null && onOpenActiveOrder != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onOpenActiveOrder,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E8F57),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.delivery_dining_rounded),
              label: const Text(
                'Przejdz do trwajacego zamowienia',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
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
        color: const Color(0x14131110),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFFFD7B7)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFF7E7DC),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFFF8EEE7),
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFD3C3B7),
              ),
        ),
      ],
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  const _OrderHistoryCard({
    required this.checkout,
    required this.onTap,
  });

  final CheckoutVerificationResponse checkout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final request = checkout.receivedOrder;
    final items = request.items;
    final leadItem = items.isEmpty ? 'Brak pozycji' : items.first.name;
    final itemCount = items.length;
    final itemSummary = itemCount <= 1 ? leadItem : '$leadItem +${itemCount - 1}';
    final totalAmount = request.totalAmount;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xEE141210),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x22FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Zamowienie #${checkout.savedOrderId}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFFF8EEE7),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                _StatusPill(label: _historyStatusLabel(checkout)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              itemSummary,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFF0DDD2),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '${request.address.title}\n${request.address.subtitle}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFD0C1B6),
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatHistoryDate(checkout.createdAt),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFFFFC993),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text(
                  'PLN ${_fmt(totalAmount)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFF9F1EA),
                        fontWeight: FontWeight.w900,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x1AFFB061),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x2EFFB061)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFFFFD8B8),
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const _MessageCard(
      icon: Icons.hourglass_bottom_rounded,
      title: 'Pobieramy historie',
      message: 'Ladujemy ostatnie zamowienia z backendu.',
      loading: true,
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xEE141210),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Color(0xFFE97F2A),
              ),
            )
          else
            Icon(icon, color: const Color(0xFFFFB25F), size: 28),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFF8EEE7),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD0C1B6),
                  height: 1.35,
                ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => onAction!.call(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE07A28),
                foregroundColor: Colors.white,
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadMoreCard extends StatelessWidget {
  const _LoadMoreCard({
    required this.isLoading,
    required this.loadedCount,
    required this.totalCount,
    required this.error,
    required this.onPressed,
  });

  final bool isLoading;
  final int loadedCount;
  final int totalCount;
  final Object? error;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xEE141210),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zaladowano $loadedCount z $totalCount zamowien',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFF8EEE7),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            error == null
                ? 'Kolejne strony dociagamy na zadanie, zeby nie ladowac calej historii naraz.'
                : error.toString(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD0C1B6),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: isLoading ? null : () => onPressed(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE07A28),
              foregroundColor: Colors.white,
            ),
            child: isLoading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    error == null ? 'Wczytaj kolejne' : 'Sprobuj ponownie',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }
}

String _historyStatusLabel(CheckoutVerificationResponse checkout) {
  final stage = checkout.verificationStage.trim().toLowerCase();
  if (stage == 'delivered_confirmed') {
    return 'Dostarczone';
  }
  if (stage == 'completed_by_admin') {
    return 'Zakonczone';
  }
  return 'Archiwum';
}

String _formatHistoryDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final year = local.year.toString();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day.$month.$year, $hour:$minute';
}

String _fmt(num value) => value.toStringAsFixed(2);

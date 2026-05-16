import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../data/local/session_persistence.dart';
import '../../data/models/admin_dashboard.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/checkout_verification.dart';
import '../../data/repositories/admin_dashboard_repository.dart';
import '../../data/repositories/checkout_repository.dart';
import '../shared/opening_hours_banner.dart';
import '../../router/app_router.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.authSession,
  });

  final AuthSession authSession;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const _backgroundAsset =
      'assets/images/background_big_ingredients_darker.png';
  static const _apiBaseUrl = AppConfig.apiBaseUrl;
  static final AdminDashboardRepository _repository =
      HttpAdminDashboardRepository(
    apiBaseUrl: _apiBaseUrl,
  );
  static final CheckoutRepository _checkoutRepository = HttpCheckoutRepository(
    apiBaseUrl: _apiBaseUrl,
  );

  AdminDashboardData? _dashboard;
  Object? _error;
  bool _isLoading = true;
  final Set<int> _busyOrderIds = <int>{};
  final Set<String> _busyPrepTimeGroups = <String>{};
  final GlobalKey _pendingOrdersSectionKey = GlobalKey();
  final GlobalKey _inProgressOrdersSectionKey = GlobalKey();
  final GlobalKey _closedOrdersSectionKey = GlobalKey();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadDashboard(showLoading: false),
    );
  }

  @override
  void didUpdateWidget(covariant AdminDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authSession.sessionToken != widget.authSession.sessionToken ||
        oldWidget.authSession.email != widget.authSession.email) {
      _loadDashboard();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboard({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final dashboard = await _repository.fetchDashboard(
        authSession: widget.authSession,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _dashboard = dashboard;
        _error = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateOrderStatus(
      AdminDashboardOrder order, String processingStatus, String successMessage,
      {String? verificationStage}) async {
    setState(() {
      _busyOrderIds.add(order.checkoutOrderId);
    });

    try {
      await _repository.updateOrderProcessingStatus(
        authSession: widget.authSession,
        checkoutOrderId: order.checkoutOrderId,
        processingStatus: processingStatus,
        verificationStage: verificationStage,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      await _loadDashboard(showLoading: false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nie udalo sie zaktualizowac zamowienia #${order.checkoutOrderId}.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyOrderIds.remove(order.checkoutOrderId);
        });
      }
    }
  }

  Future<void> _logout() async {
    await SessionPersistence.clearAll();
    if (!mounted) {
      return;
    }
    Navigator.pushReplacementNamed(context, AppRoutes.login);
  }

  Future<void> _openTakenOrderDetails(AdminDashboardOrder order) async {
    final isDriver = widget.authSession.isDriver;
    List<CheckoutChatMessage> orderMessages = const [];

    try {
      orderMessages = await _checkoutRepository.fetchOrderMessages(
        checkoutOrderId: order.checkoutOrderId,
        sessionToken: widget.authSession.sessionToken,
        email: widget.authSession.email,
      );

      if (order.unreadCustomerMessageCount > 0) {
        await _checkoutRepository.markOrderMessagesRead(
          checkoutOrderId: order.checkoutOrderId,
          request: CheckoutChatMessagesReadRequest(
            sessionToken: widget.authSession.sessionToken,
            userEmail: widget.authSession.email,
          ),
        );
        await _loadDashboard(showLoading: false);
      }
    } catch (_) {
      orderMessages = const [];
    }

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _TakenOrderDetailsDialog(
        order: order,
        isDriverView: isDriver,
        messages: orderMessages,
        onClose: () => Navigator.of(dialogContext).pop(),
        onMarkInOven: isDriver ||
                !order.supportsProgressUpdates ||
                !order.canMarkInOven ||
                !order.assignedToMe ||
                !order.isInProgress ||
                _busyOrderIds.contains(order.checkoutOrderId) ||
                _operatorStageIndex(order) >= 2
            ? null
            : () async {
                Navigator.of(dialogContext).pop();
                await _updateOrderStatus(
                  order,
                  'assigned',
                  'Zamowienie #${order.checkoutOrderId} zostalo oznaczone jako w piecu.',
                  verificationStage: 'in_oven',
                );
              },
        onMarkReadyForDispatch: isDriver ||
                !_isDeliveryOrder(order) ||
                !order.assignedToMe ||
                !order.isInProgress ||
                _busyOrderIds.contains(order.checkoutOrderId) ||
                _operatorStageIndex(order) >= 3
            ? null
            : () async {
                Navigator.of(dialogContext).pop();
                await _updateOrderStatus(
                  order,
                  'assigned',
                  'Zamowienie #${order.checkoutOrderId} jest gotowe do wysylki i czeka na kierowce.',
                  verificationStage: 'ready_for_delivery',
                );
              },
        onMarkOnTheWay: isDriver ||
                _isDeliveryOrder(order) ||
                !order.supportsProgressUpdates ||
                !order.assignedToMe ||
                !order.isInProgress ||
                _busyOrderIds.contains(order.checkoutOrderId) ||
                _operatorStageIndex(order) >= 3
            ? null
            : () async {
                Navigator.of(dialogContext).pop();
                await _updateOrderStatus(
                  order,
                  'assigned',
                  isDriver
                      ? 'Dostawa #${order.checkoutOrderId} zostala oznaczona jako w drodze.'
                      : 'Zamowienie #${order.checkoutOrderId} zostalo oznaczone jako w drodze.',
                  verificationStage: 'on_the_way',
                );
              },
        onComplete: !order.assignedToMe ||
                !order.isInProgress ||
                _busyOrderIds.contains(order.checkoutOrderId)
            ? null
            : () async {
                Navigator.of(dialogContext).pop();
                await _updateOrderStatus(
                  order,
                  'completed',
                  isDriver
                      ? 'Dostawa #${order.checkoutOrderId} zostala zakonczona.'
                      : 'Zamowienie #${order.checkoutOrderId} zostalo zakonczone.',
                );
              },
      ),
    );
  }

  Future<void> _openClosedOrdersHistory(AdminDashboardData dashboard) async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _ClosedOrdersHistoryDialog(
        title: widget.authSession.isDriver
            ? 'Zrealizowane dostawy'
            : widget.authSession.isEmployee
                ? 'Moja historia zamowien'
                : 'Historia zamknietych zamowien',
        subtitle: widget.authSession.isDriver
            ? 'Dostawy zakonczone przez zalogowanego kierowce.'
            : widget.authSession.isEmployee
                ? 'Zamowienia zakonczone przez zalogowanego pracownika.'
                : 'Wszystkie zamkniete zamowienia z panelu administratora.',
        authSession: widget.authSession,
        repository: _repository,
        initialOrders: const [],
        totalCount: dashboard.orderHistoryCount,
        hasMore: dashboard.orderHistoryCount > 0,
        todayOnly: false,
        onClose: () => Navigator.of(dialogContext).pop(),
        onOrderTap: (order) async {
          Navigator.of(dialogContext).pop();
          await _openTakenOrderDetails(order);
        },
      ),
    );
  }

  Future<void> _openTodayCompletedOrders(AdminDashboardData dashboard) async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _ClosedOrdersHistoryDialog(
        title: 'Zamowienia zrealizowane dzis',
        subtitle: 'Lista zamknietych zamowien dla biezacego dnia.',
        authSession: widget.authSession,
        repository: _repository,
        initialOrders: const [],
        totalCount: dashboard.completedOrdersToday,
        hasMore: dashboard.completedOrdersToday > 0,
        todayOnly: true,
        onClose: () => Navigator.of(dialogContext).pop(),
        onOrderTap: (order) async {
          Navigator.of(dialogContext).pop();
          await _openTakenOrderDetails(order);
        },
      ),
    );
  }

  Future<void> _openStaffPresenceDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _StaffPresenceDialog(
        authSession: widget.authSession,
        repository: _repository,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  Future<void> _scrollToSection(GlobalKey sectionKey) async {
    final context = sectionKey.currentContext;
    if (context == null) {
      return;
    }

    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _openPrepTimeDialog(AdminPrepTimeSetting setting) async {
    final selectedMinutes = await showDialog<int>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _PrepTimePickerDialog(
        setting: setting,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );

    if (selectedMinutes == null || selectedMinutes == setting.minutes) {
      return;
    }

    await _updatePrepTimeSetting(setting, selectedMinutes);
  }

  Future<void> _openCatalogRepository() async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _CatalogRepositoryDialog(
        authSession: widget.authSession,
        repository: _repository,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadDashboard(showLoading: false);
  }

  Future<void> _updatePrepTimeSetting(
    AdminPrepTimeSetting setting,
    int minutes,
  ) async {
    setState(() {
      _busyPrepTimeGroups.add(setting.groupKey);
    });

    try {
      await _repository.updatePrepTimeSetting(
        authSession: widget.authSession,
        groupKey: setting.groupKey,
        minutes: minutes,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${setting.label}: ustawiono $minutes min.',
          ),
        ),
      );
      await _loadDashboard(showLoading: false);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nie udalo sie zaktualizowac czasu dla ${setting.label.toLowerCase()}.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyPrepTimeGroups.remove(setting.groupKey);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;

    Widget body;
    if (_isLoading && dashboard == null) {
      body = const Center(
        child: CircularProgressIndicator(color: Color(0xFFE98B38)),
      );
    } else if (_error != null && dashboard == null) {
      body = _AdminStateCard(
        icon: Icons.shield_outlined,
        title: 'Nie udalo sie pobrac panelu administratora',
        message: _error.toString(),
        buttonLabel: 'Sprobuj ponownie',
        onPressed: _loadDashboard,
      );
    } else if (dashboard == null) {
      body = const _AdminStateCard(
        icon: Icons.dashboard_customize_outlined,
        title: 'Brak danych dashboardu',
        message:
            'Backend nie zwrocil jeszcze danych dla panelu administratora.',
      );
    } else {
      final isEmployee = widget.authSession.isEmployee;
      final isDriver = widget.authSession.isDriver;
      final statCards = [
        _StatCardData(
          icon: isDriver
              ? Icons.delivery_dining_outlined
              : Icons.support_agent_outlined,
          value: dashboard.pendingOrderCount.toString(),
          label: isDriver ? 'Oczekujace\ndostawy' : 'Oczekujace\nzamowienia',
          onTap: () => _scrollToSection(_pendingOrdersSectionKey),
        ),
        _StatCardData(
          icon: isDriver ? Icons.route_outlined : Icons.room_service_outlined,
          value: isDriver
              ? dashboard.myTakenOrders.length.toString()
              : dashboard.inProgressOrderCount.toString(),
          label:
              isDriver ? 'Przypisane\nDo Ciebie' : 'Zamowienia w\nrealizacji',
          onTap: () => _scrollToSection(_inProgressOrdersSectionKey),
        ),
        if (!isDriver)
          _StatCardData(
            icon: Icons.local_fire_department_outlined,
            value: '${dashboard.ovenLoad}/${dashboard.ovenCapacity}',
            label: 'Piec\nzapiekanek',
          ),
        if (!isDriver)
          _StatCardData(
            icon: Icons.set_meal_outlined,
            value: '${dashboard.udkaOvenLoad}/${dashboard.udkaOvenCapacity}',
            label: dashboard.udkaSlotLabel.isEmpty
                ? 'Piec udek'
                : 'Piec udek\n${dashboard.udkaSlotLabel}',
          ),
        _StatCardData(
          icon: Icons.history_outlined,
          value: dashboard.orderHistoryCount.toString(),
          label: isDriver
              ? 'Zrealizowane\ndostawy'
              : isEmployee
                  ? 'Moja historia\nzamowien'
                  : 'Historia\nzamowien',
          onTap: isDriver
              ? () => _scrollToSection(_closedOrdersSectionKey)
              : () => _openClosedOrdersHistory(dashboard),
        ),
      ];
      if (!isEmployee && !isDriver) {
        statCards.insert(
          0,
          _StatCardData(
            icon: Icons.badge_outlined,
            value: dashboard.loggedInEmployeeCount.toString(),
            label: 'Zalogowani\npracownicy',
            activeEmployees: dashboard.activeEmployees,
            onTap: _openStaffPresenceDialog,
          ),
        );
        statCards.addAll([
          _StatCardData(
            icon: Icons.inventory_2_outlined,
            value: '',
            label: 'Repozytorium\nproduktow',
            onTap: _openCatalogRepository,
          ),
          _StatCardData(
            icon: Icons.group_outlined,
            value: dashboard.newUsersThisMonth.toString(),
            label: 'Nowych\nuzytkownikow /mc',
          ),
          _StatCardData(
            icon: Icons.assignment_turned_in_outlined,
            value: dashboard.completedOrdersToday.toString(),
            label: 'Zamowienia\nzrealizowane dzis',
            onTap: () => _openTodayCompletedOrders(dashboard),
          ),
        ]);
      }

      final inProgressOrders =
          isDriver ? dashboard.myTakenOrders : dashboard.inProgressOrders;

      body = SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadDashboard,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              _AdminTopBar(
                adminEmail: widget.authSession.email,
                isEmployee: widget.authSession.isEmployee,
                isDriver: widget.authSession.isDriver,
                onRefresh: _loadDashboard,
                onLogout: _logout,
              ),
              const SizedBox(height: 14),
              OpeningHoursBanner(hours: dashboard.openingHours),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final spacing = 14.0;
                  final itemWidth = width < 720
                      ? (width - spacing) / 2
                      : (width - (spacing * 2)) / 3;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final card in statCards)
                        SizedBox(
                          width: itemWidth,
                          child: _AdminStatCard(data: card),
                        ),
                    ],
                  );
                },
              ),
              if (dashboard.prepTimeSettings.isNotEmpty) ...[
                const SizedBox(height: 22),
                _SectionHeader(
                  title: 'Czas produktow',
                  subtitle:
                      'Robocza zmiana minut przygotowania dla grup produktow i dodatkow.',
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final spacing = 14.0;
                    final itemWidth = width < 720
                        ? (width - spacing) / 2
                        : (width - (spacing * 2)) / 3;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final setting in dashboard.prepTimeSettings)
                          SizedBox(
                            width: itemWidth,
                            child: _PrepTimeCard(
                              setting: setting,
                              busy: _busyPrepTimeGroups.contains(
                                setting.groupKey,
                              ),
                              onTap: () => _openPrepTimeDialog(setting),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              if (!isEmployee && !isDriver) ...[
                const SizedBox(height: 22),
                _TurnoverCard(points: dashboard.turnoverLastDays),
                const SizedBox(height: 22),
              ] else
                const SizedBox(height: 22),
              KeyedSubtree(
                key: _pendingOrdersSectionKey,
                child: _SectionHeader(
                  title:
                      isDriver ? 'Oczekujace dostawy' : 'Oczekujace zamowienia',
                  subtitle: isDriver
                      ? 'Dostawy gotowe do przejecia przez kierowce.'
                      : 'Nowe zamowienia z checkoutu, ktore nie zostaly jeszcze podjete.',
                ),
              ),
              const SizedBox(height: 12),
              if (dashboard.pendingOrders.isEmpty)
                _EmptyOrdersCard(
                  icon: isDriver
                      ? Icons.local_shipping_outlined
                      : Icons.mark_chat_unread_outlined,
                  title: isDriver
                      ? 'Brak dostaw oczekujacych'
                      : 'Brak zamowien niepodjetych',
                  message: isDriver
                      ? 'Gdy pojawia sie nowa dostawa, zobaczysz ja w tej sekcji.'
                      : 'Nowe zamowienia pojawia sie tutaj automatycznie po zapisie checkoutu.',
                )
              else
                for (final order in dashboard.pendingOrders) ...[
                  _AdminOrderCard(
                    order: order,
                    busy: _busyOrderIds.contains(order.checkoutOrderId),
                    accentColor: const Color(0xFFE48A32),
                    statusLabel: isDriver ? 'Do odbioru' : 'Niepodjete',
                    primaryActionLabel:
                        isDriver ? 'Podejmij dostawe' : 'Podejmij',
                    onPrimaryAction: () => _updateOrderStatus(
                      order,
                      'assigned',
                      isDriver
                          ? 'Dostawa #${order.checkoutOrderId} zostala przypisana do Ciebie.'
                          : 'Zamowienie #${order.checkoutOrderId} zostalo podjete.',
                    ),
                    onTap:
                        isDriver ? () => _openTakenOrderDetails(order) : null,
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 10),
              KeyedSubtree(
                key: _inProgressOrdersSectionKey,
                child: _SectionHeader(
                  title: isDriver
                      ? 'Przypisane do Ciebie'
                      : 'Zamowienia w realizacji',
                  subtitle: isDriver
                      ? 'Aktywne dostawy obslugiwane przez zalogowanego kierowce.'
                      : 'Pozycje juz podjete przez zespol i gotowe do dalszej obslugi.',
                ),
              ),
              const SizedBox(height: 12),
              if (inProgressOrders.isEmpty)
                _EmptyOrdersCard(
                  icon: isDriver
                      ? Icons.route_outlined
                      : Icons.room_service_outlined,
                  title: isDriver
                      ? 'Brak przypisanych dostaw'
                      : 'Brak zamowien podjetych',
                  message: isDriver
                      ? 'Po przejeciu dostawy zobaczysz ja tutaj.'
                      : 'Po podjeciu zlecenia pojawi sie ono w tej sekcji.',
                )
              else
                for (final order in inProgressOrders) ...[
                  _AdminOrderCard(
                    order: order,
                    busy: _busyOrderIds.contains(order.checkoutOrderId),
                    accentColor: const Color(0xFF63D7D2),
                    statusLabel: _boardStatusLabelForOrder(
                      order,
                      isDriverView: isDriver,
                    ),
                    primaryActionLabel:
                        isDriver || _isReadyForDeliveryStage(order)
                            ? 'Szczegoly'
                            : 'Zakoncz',
                    secondaryActionLabel:
                        isDriver || _isReadyForDeliveryStage(order)
                            ? null
                            : 'Cofnij',
                    onPrimaryAction: () => isDriver
                        ? _openTakenOrderDetails(order)
                        : _isReadyForDeliveryStage(order)
                            ? _openTakenOrderDetails(order)
                            : _updateOrderStatus(
                                order,
                                'completed',
                                'Zamowienie #${order.checkoutOrderId} zostalo zakonczone.',
                              ),
                    onSecondaryAction: isDriver
                        ? null
                        : () => _updateOrderStatus(
                              order,
                              'unassigned',
                              'Zamowienie #${order.checkoutOrderId} wrocilo do oczekujacych.',
                            ),
                    onTap: () => _openTakenOrderDetails(order),
                  ),
                  const SizedBox(height: 12),
                ],
              if (isDriver) ...[
                const SizedBox(height: 10),
                KeyedSubtree(
                  key: _closedOrdersSectionKey,
                  child: const _SectionHeader(
                    title: 'Zrealizowane dostawy',
                    subtitle:
                        'Historia dostaw zakonczonych przez zalogowanego kierowce.',
                  ),
                ),
                const SizedBox(height: 12),
                if (dashboard.closedOrders.isEmpty)
                  const _EmptyOrdersCard(
                    icon: Icons.assignment_turned_in_outlined,
                    title: 'Brak zakonczonych dostaw',
                    message:
                        'Po domknieciu pierwszej dostawy historia pojawi sie tutaj.',
                  )
                else
                  for (final order in dashboard.closedOrders) ...[
                    _AdminOrderCard(
                      order: order,
                      busy: false,
                      accentColor: const Color(0xFF79F5B8),
                      statusLabel: 'Zrealizowane',
                      primaryActionLabel: 'Podglad',
                      onPrimaryAction: () => _openTakenOrderDetails(order),
                      onTap: () => _openTakenOrderDetails(order),
                    ),
                    const SizedBox(height: 12),
                  ],
                if (dashboard.closedOrdersHasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Pokazujemy tylko najnowsze zamowienia. Pelna historia laduje sie strona po stronie po otwarciu archiwum.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFD4C4B8),
                            height: 1.35,
                          ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: _AdminBackground(child: body),
      bottomNavigationBar: dashboard == null ||
              dashboard.myTakenOrders.isEmpty ||
              widget.authSession.isDriver
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: _MyTakenOrdersBar(
                  orders: dashboard.myTakenOrders,
                  onOrderTap: _openTakenOrderDetails,
                ),
              ),
            ),
    );
  }
}

class _AdminBackground extends StatelessWidget {
  const _AdminBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(_AdminDashboardScreenState._backgroundAsset),
          fit: BoxFit.cover,
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFA060606),
              Color(0xF3080808),
              Color(0xFF050505),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              left: -20,
              child: _AdminGlow(
                color: const Color(0x22FFFFFF),
                size: 150,
              ),
            ),
            Positioned(
              top: 160,
              right: -30,
              child: _AdminGlow(
                color: const Color(0x30E08734),
                size: 180,
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.adminEmail,
    required this.isEmployee,
    required this.isDriver,
    required this.onRefresh,
    required this.onLogout,
  });

  final String? adminEmail;
  final bool isEmployee;
  final bool isDriver;
  final Future<void> Function() onRefresh;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isDriver
                    ? 'Panel kierowcy'
                    : isEmployee
                        ? 'Panel realizacji'
                        : 'Panel administratora',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFFF5EFE9),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                adminEmail == null || adminEmail!.isEmpty
                    ? isDriver
                        ? 'Obsluga dostaw, przypisan i historii kursow.'
                        : 'Nadzor zamowien online i stanu realizacji.'
                    : 'Zalogowano jako $adminEmail',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD7C7BC),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _TopIconButton(
          icon: Icons.refresh_rounded,
          onTap: () => onRefresh(),
        ),
        const SizedBox(width: 8),
        _TopIconButton(
          icon: Icons.logout_rounded,
          onTap: onLogout,
        ),
      ],
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
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
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: const Color(0x261D1B1B),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x2EFFFFFF)),
        ),
        child: Icon(icon, color: const Color(0xFFF8EEE7)),
      ),
    );
  }
}

class _StatCardData {
  const _StatCardData({
    required this.icon,
    required this.value,
    required this.label,
    this.activeEmployees = const [],
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final List<AdminDashboardActiveEmployee> activeEmployees;
  final VoidCallback? onTap;
}

class _AdminStatCard extends StatelessWidget {
  const _AdminStatCard({
    required this.data,
  });

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasEmployeePresence = data.activeEmployees.isNotEmpty;
    final card = Container(
      height: 212,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xEE3A3838),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  color: const Color(0x2A8DDAD5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  data.icon,
                  color: const Color(0xFFF3F0EC),
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    data.value,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            data.label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF4F0EC),
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const Spacer(),
          if (hasEmployeePresence) ...[
            const SizedBox(height: 12),
            _EmployeePresenceStrip(employees: data.activeEmployees),
          ],
        ],
      ),
    );

    if (data.onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}

class _EmployeePresenceStrip extends StatelessWidget {
  const _EmployeePresenceStrip({
    required this.employees,
  });

  final List<AdminDashboardActiveEmployee> employees;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const bubbleSize = 38.0;
        const bubbleGap = 8.0;
        final slots = math.max(
            1,
            ((constraints.maxWidth + bubbleGap) / (bubbleSize + bubbleGap))
                .floor());
        final maxVisibleEmployees = math.min(5, slots);
        final visibleEmployees =
            employees.take(maxVisibleEmployees).toList(growable: false);
        final remainingCount =
            math.max(0, employees.length - visibleEmployees.length);

        final children = <Widget>[];
        for (var index = 0; index < visibleEmployees.length; index++) {
          if (index > 0) {
            children.add(const SizedBox(width: 8));
          }
          children
              .add(_EmployeeInitialBubble(employee: visibleEmployees[index]));
        }
        if (remainingCount > 0) {
          if (children.isNotEmpty) {
            children.add(const SizedBox(width: 8));
          }
          children.add(_EmployeeOverflowBubble(count: remainingCount));
        }

        return Row(children: children);
      },
    );
  }
}

class _EmployeeInitialBubble extends StatelessWidget {
  const _EmployeeInitialBubble({
    required this.employee,
  });

  final AdminDashboardActiveEmployee employee;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _employeeBadgeColor(employee);
    final title = employee.displayName.trim().isEmpty
        ? employee.email
        : employee.displayName;
    final subtitle = employee.email.trim().isEmpty ||
            employee.email.trim().toLowerCase() == title.trim().toLowerCase()
        ? 'Aktywny: ${_formatDateTime(employee.lastSeenAt)}'
        : '${employee.email}\nAktywny: ${_formatDateTime(employee.lastSeenAt)}';

    return Tooltip(
      message: '$title\n$subtitle',
      waitDuration: const Duration(milliseconds: 200),
      child: Container(
        height: 38,
        width: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor,
          border: Border.all(color: const Color(0x45FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          employee.initials.isEmpty ? '?' : employee.initials,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
        ),
      ),
    );
  }
}

class _EmployeeOverflowBubble extends StatelessWidget {
  const _EmployeeOverflowBubble({
    required this.count,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      width: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x33251F1C),
        border: Border.all(color: const Color(0x28FFFFFF)),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFFF7EEE6),
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _PrepTimeCard extends StatelessWidget {
  const _PrepTimeCard({
    required this.setting,
    required this.busy,
    required this.onTap,
  });

  final AdminPrepTimeSetting setting;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 164,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xF0141414),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: busy ? const Color(0x30E98B38) : const Color(0x22FFFFFF),
            ),
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
                      color: const Color(0xFF1D1D1D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.timer_outlined,
                      color: busy
                          ? const Color(0xFFE98B38)
                          : const Color(0xFFE7DED7),
                    ),
                  ),
                  const Spacer(),
                  if (busy)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFFE98B38),
                      ),
                    )
                  else
                    const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Color(0xFF95867A),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                setting.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFF6EEE7),
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '${setting.minutes} min',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFF4B26C),
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Kliknij, aby zmienic.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB2A49A),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurnoverCard extends StatelessWidget {
  const _TurnoverCard({
    required this.points,
  });

  final List<AdminDashboardTurnoverPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xC9141414),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zrealizowane zamowienia on-line',
            style: theme.textTheme.titleLarge?.copyWith(
              color: const Color(0xFFF7F0EA),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _TurnoverChartPainter(points: points),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 28),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final point in points)
                            Text(
                              point.dayLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFFD0C1B6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
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

class _TurnoverChartPainter extends CustomPainter {
  const _TurnoverChartPainter({
    required this.points,
  });

  final List<AdminDashboardTurnoverPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final chartLeft = 36.0;
    final chartTop = 12.0;
    final chartBottom = size.height - 28.0;
    final chartRight = size.width - 8.0;
    final chartHeight = chartBottom - chartTop;
    final chartWidth = chartRight - chartLeft;
    final values =
        points.map((point) => point.totalAmount).toList(growable: false);
    final highestValue =
        values.fold<double>(0, (maxSoFar, value) => math.max(maxSoFar, value));
    final maxValue = highestValue <= 0
        ? 4.0
        : math.max(1, (highestValue * 1.5).ceil()).toDouble();
    const divisions = 4;
    final stepValue = maxValue / divisions;

    final gridPaint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    const labelStyle = TextStyle(
      color: Color(0xFFD5C8BD),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    for (var i = 0; i <= divisions; i++) {
      final y = chartBottom - (chartHeight * (i / divisions));
      canvas.drawLine(
        Offset(chartLeft, y),
        Offset(chartRight, y),
        gridPaint,
      );

      final labelPainter = TextPainter(
        text: TextSpan(text: '${(stepValue * i).round()}', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(
            chartLeft - labelPainter.width - 8, y - (labelPainter.height / 2)),
      );
    }

    if (points.isEmpty) {
      return;
    }

    final path = Path();
    final fillPath = Path();
    final pointPaint = Paint()
      ..color = const Color(0xFF65E0DB)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0x3365E0DB),
          Color(0x0665E0DB),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(
          Rect.fromLTWH(chartLeft, chartTop, chartWidth, chartHeight));

    for (var i = 0; i < points.length; i++) {
      final dx = points.length == 1
          ? chartLeft + (chartWidth / 2)
          : chartLeft + ((chartWidth / (points.length - 1)) * i);
      final ratio = maxValue == 0 ? 0.0 : (points[i].totalAmount / maxValue);
      final dy = chartBottom - (chartHeight * ratio);
      final point = Offset(dx, dy);

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
        fillPath
          ..moveTo(point.dx, chartBottom)
          ..lineTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
        fillPath.lineTo(point.dx, point.dy);
      }
    }

    fillPath
      ..lineTo(chartRight, chartBottom)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, pointPaint);

    for (var i = 0; i < points.length; i++) {
      final dx = points.length == 1
          ? chartLeft + (chartWidth / 2)
          : chartLeft + ((chartWidth / (points.length - 1)) * i);
      final ratio = maxValue == 0 ? 0.0 : (points[i].totalAmount / maxValue);
      final dy = chartBottom - (chartHeight * ratio);
      canvas.drawCircle(
        Offset(dx, dy),
        4.5,
        Paint()..color = const Color(0xFF65E0DB),
      );
      canvas.drawCircle(
        Offset(dx, dy),
        9,
        Paint()..color = const Color(0x1D65E0DB),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TurnoverChartPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: const Color(0xFFF5EEE7),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFD6C6BA),
          ),
        ),
      ],
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.busy,
    required this.accentColor,
    required this.statusLabel,
    required this.primaryActionLabel,
    required this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.onTap,
  });

  final AdminDashboardOrder order;
  final bool busy;
  final Color accentColor;
  final String statusLabel;
  final String primaryActionLabel;
  final VoidCallback onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = order.notes?.trim();
    final itemPreview = order.itemNames.take(3).join(', ');
    final showDriverDeliveryReminder = _needsDriverDeliveryReminder(order);
    final pendingAgeMinutes = order.isPending
        ? DateTime.now().toUtc().difference(order.createdAt.toUtc()).inMinutes
        : null;

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xD41A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zamowienie #${order.checkoutOrderId}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFF6EEE7),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Utworzone ${_formatDateTime(order.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD0C1B6),
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (pendingAgeMinutes != null)
                    _PendingOrderAgeBadge(minutesAgo: pendingAgeMinutes),
                  _StatusBadge(
                    label: statusLabel,
                    color: accentColor,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.payments_outlined,
                label:
                    '${order.paymentMethod} | PLN ${order.totalAmount.toStringAsFixed(2)}',
              ),
              _MetaChip(
                icon: Icons.timelapse_outlined,
                label: showDriverDeliveryReminder
                    ? 'ETA przekroczone'
                    : 'ETA ${order.remainingEtaMinutes} min',
              ),
              _MetaChip(
                icon: Icons.receipt_long_outlined,
                label: '${order.itemCount} poz.',
              ),
              _MetaChip(
                icon: Icons.delivery_dining_outlined,
                label: order.fulfillmentMethod,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.local_pizza_outlined,
            label: itemPreview.isEmpty ? 'Brak pozycji' : itemPreview,
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: '${order.addressTitle} | ${order.addressSubtitle}',
          ),
          if (order.customerEmail != null &&
              order.customerEmail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.mail_outline_rounded,
              label: order.customerEmail!,
            ),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.sticky_note_2_outlined,
              label: notes,
            ),
          ],
          if (showDriverDeliveryReminder) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x26FFB15D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x55FFB15D)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.notification_important_outlined,
                    color: Color(0xFFFFC891),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Przekroczono przewidywany czas dostawy. Sprawdz, czy zamowienie #${order.checkoutOrderId} zostalo dostarczone i domknij je, jesli tak.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFFD7B5),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onPrimaryAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(primaryActionLabel),
                ),
              ),
              if (secondaryActionLabel != null &&
                  onSecondaryAction != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onSecondaryAction,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF6EEE7),
                      side: const BorderSide(color: Color(0x30FFFFFF)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(secondaryActionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: card,
      ),
    );
  }
}

class _ClosedOrdersHistoryDialog extends StatelessWidget {
  const _ClosedOrdersHistoryDialog({
    required this.title,
    required this.subtitle,
    required this.authSession,
    required this.repository,
    required this.initialOrders,
    required this.totalCount,
    required this.hasMore,
    required this.todayOnly,
    required this.onClose,
    required this.onOrderTap,
  });

  final String title;
  final String subtitle;
  final AuthSession authSession;
  final AdminDashboardRepository repository;
  final List<AdminDashboardOrder> initialOrders;
  final int totalCount;
  final bool hasMore;
  final bool todayOnly;
  final VoidCallback onClose;
  final ValueChanged<AdminDashboardOrder> onOrderTap;

  @override
  Widget build(BuildContext context) {
    return _ClosedOrdersHistoryDialogBody(
      title: title,
      subtitle: subtitle,
      authSession: authSession,
      repository: repository,
      initialOrders: initialOrders,
      totalCount: totalCount,
      hasMore: hasMore,
      todayOnly: todayOnly,
      onClose: onClose,
      onOrderTap: onOrderTap,
    );
  }
}

class _ClosedOrdersHistoryDialogBody extends StatefulWidget {
  const _ClosedOrdersHistoryDialogBody({
    required this.title,
    required this.subtitle,
    required this.authSession,
    required this.repository,
    required this.initialOrders,
    required this.totalCount,
    required this.hasMore,
    required this.todayOnly,
    required this.onClose,
    required this.onOrderTap,
  });

  final String title;
  final String subtitle;
  final AuthSession authSession;
  final AdminDashboardRepository repository;
  final List<AdminDashboardOrder> initialOrders;
  final int totalCount;
  final bool hasMore;
  final bool todayOnly;
  final VoidCallback onClose;
  final ValueChanged<AdminDashboardOrder> onOrderTap;

  @override
  State<_ClosedOrdersHistoryDialogBody> createState() =>
      _ClosedOrdersHistoryDialogBodyState();
}

class _ClosedOrdersHistoryDialogBodyState
    extends State<_ClosedOrdersHistoryDialogBody> {
  static const _pageSize = 15;
  static const _loadMoreTriggerOffset = 220.0;

  late final List<AdminDashboardOrder> _orders =
      widget.initialOrders.toList(growable: true);
  late final ScrollController _scrollController = ScrollController()
    ..addListener(_handleScroll);
  late bool _hasMore = widget.hasMore;
  late int _nextPage =
      (_orders.length ~/ _pageSize) + (_orders.isEmpty ? 1 : 2);
  late int _totalCount = widget.totalCount;
  bool _isLoading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (_orders.isEmpty && _totalCount > 0) {
      unawaited(_loadMore());
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    final remainingScroll = position.maxScrollExtent - position.pixels;
    if (remainingScroll <= _loadMoreTriggerOffset) {
      unawaited(_loadMore());
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

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final page = await widget.repository.fetchClosedOrdersHistory(
        authSession: widget.authSession,
        page: _nextPage,
        pageSize: _pageSize,
        todayOnly: widget.todayOnly,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _orders.addAll(page.orders);
        _hasMore = page.hasMore;
        _totalCount = page.totalCount;
        _nextPage = page.page + 1;
        _isLoading = false;
      });
      _scheduleAutoLoadMoreCheck();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: const Color(0xF0141414),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFFF8EEE6),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.subtitle} Zaladowano ${_orders.length} z $_totalCount.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFD4C4B8),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                _TopIconButton(
                  icon: Icons.close_rounded,
                  onTap: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _orders.isEmpty
                  ? const _EmptyOrdersCard(
                      icon: Icons.history_toggle_off_rounded,
                      title: 'Brak zamknietych zamowien',
                      message:
                          'Kiedy zamowienia zostana zakonczone, pojawia sie tutaj.',
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _orders.length +
                          ((_hasMore || _error != null) ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index >= _orders.length) {
                          return _LoadMoreHistoryCard(
                            isLoading: _isLoading,
                            canLoadMore: _hasMore,
                            error: _error,
                            loadedCount: _orders.length,
                            totalCount: _totalCount,
                            onPressed: _loadMore,
                          );
                        }
                        final order = _orders[index];
                        return _ClosedOrderHistoryCard(
                          order: order,
                          onTap: () => widget.onOrderTap(order),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosedOrderHistoryCard extends StatelessWidget {
  const _ClosedOrderHistoryCard({
    required this.order,
    required this.onTap,
  });

  final AdminDashboardOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemPreview = order.itemNames.take(3).join(', ');
    final closedAt = order.closedAt ?? order.createdAt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xD41A1A1A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x1FFFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zamowienie #${order.checkoutOrderId}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: const Color(0xFFF6EEE7),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Zamkniete ${_formatDateTime(closedAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFD0C1B6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _StatusBadge(
                    label: 'Zamkniete',
                    color: Color(0xFF79F5B8),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    icon: Icons.payments_outlined,
                    label:
                        '${order.paymentMethod} | PLN ${order.totalAmount.toStringAsFixed(2)}',
                  ),
                  _MetaChip(
                    icon: Icons.receipt_long_outlined,
                    label: '${order.itemCount} poz.',
                  ),
                  _MetaChip(
                    icon: Icons.delivery_dining_outlined,
                    label: order.fulfillmentMethod,
                  ),
                  if (order.assignedOperatorEmail != null &&
                      order.assignedOperatorEmail!.isNotEmpty)
                    _MetaChip(
                      icon: Icons.badge_outlined,
                      label: order.assignedOperatorEmail!,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _InfoRow(
                icon: Icons.local_pizza_outlined,
                label: itemPreview.isEmpty ? 'Brak pozycji' : itemPreview,
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: '${order.addressTitle} | ${order.addressSubtitle}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadMoreHistoryCard extends StatelessWidget {
  const _LoadMoreHistoryCard({
    required this.isLoading,
    required this.canLoadMore,
    required this.error,
    required this.loadedCount,
    required this.totalCount,
    required this.onPressed,
  });

  final bool isLoading;
  final bool canLoadMore;
  final Object? error;
  final int loadedCount;
  final int totalCount;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xD41A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zaladowano $loadedCount z $totalCount zamowien',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFF7EEE6),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            error == null
                ? 'Kolejne strony historii pobieramy na zadanie, zeby nie trzymac calego archiwum w pamieci.'
                : error.toString(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD4C4B8),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: isLoading || !canLoadMore ? null : () => onPressed(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE98B38),
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({
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
        color: const Color(0xFF232323),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFF3A65A)),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFF2E6DB),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: const Color(0xFFD6C5BA)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFF4EDE7),
                  height: 1.3,
                ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _PendingOrderAgeBadge extends StatelessWidget {
  const _PendingOrderAgeBadge({
    required this.minutesAgo,
  });

  final int minutesAgo;

  @override
  Widget build(BuildContext context) {
    final isWarning = minutesAgo > 5;
    final color = isWarning ? const Color(0xFFF3A847) : const Color(0xFF8EE3DD);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isWarning ? 0.2 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isWarning ? 0.72 : 0.42),
          width: isWarning ? 1.4 : 1,
        ),
        boxShadow: isWarning
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.schedule_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            '$minutesAgo min temu',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOrdersCard extends StatelessWidget {
  const _EmptyOrdersCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xC0131313),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1CFFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: const Color(0x1DE38A38),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFF7E9DA)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF6EEE7),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFD2C3B8),
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

class _PrepTimePickerDialog extends StatelessWidget {
  const _PrepTimePickerDialog({
    required this.setting,
    required this.onClose,
  });

  static const _minuteOptions = <int>[5, 10, 15, 20, 25, 30, 35, 40];

  final AdminPrepTimeSetting setting;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: const Color(0xF0111111),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        setting.label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: const Color(0xFFF7EEE6),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Wybierz roboczy czas przygotowania.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFFBBAEA3),
                            ),
                      ),
                    ],
                  ),
                ),
                _TopIconButton(
                  icon: Icons.close_rounded,
                  onTap: onClose,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final minutes in _minuteOptions)
                  _PrepTimeOptionTile(
                    minutes: minutes,
                    selected: minutes == setting.minutes,
                    onTap: () => Navigator.of(context).pop(minutes),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrepTimeOptionTile extends StatelessWidget {
  const _PrepTimeOptionTile({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 92,
        height: 86,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2C2117) : const Color(0xFF181818),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFE98B38) : const Color(0x22FFFFFF),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$minutes',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: selected
                        ? const Color(0xFFF3B26F)
                        : const Color(0xFFF3ECE5),
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'min',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFFB5A89E),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyTakenOrdersBar extends StatelessWidget {
  const _MyTakenOrdersBar({
    required this.orders,
    required this.onOrderTap,
  });

  final List<AdminDashboardOrder> orders;
  final ValueChanged<AdminDashboardOrder> onOrderTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xF0121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.room_service_outlined,
                color: Color(0xFFEAB073),
              ),
              const SizedBox(width: 8),
              Text(
                'Moje podjete zamowienia',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFF7EEE6),
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _TakenOrderSquare(
                order: orders[index],
                onTap: () => onOrderTap(orders[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TakenOrderSquare extends StatelessWidget {
  const _TakenOrderSquare({
    required this.order,
    required this.onTap,
  });

  final AdminDashboardOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Container(
            width: 108,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF191919),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x28FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${order.checkoutOrderId}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFF8EEE6),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const Spacer(),
                Text(
                  '${order.itemCount} poz.',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFFE8D0BD),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ETA ${order.remainingEtaMinutes} min',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFCFC0B4),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          if (order.unreadCustomerMessageCount > 0)
            Positioned(
              top: 8,
              right: 8,
              child: _UnreadChatBadge(
                count: order.unreadCustomerMessageCount,
              ),
            ),
        ],
      ),
    );
  }
}

class _TakenOrderDetailsDialog extends StatelessWidget {
  const _TakenOrderDetailsDialog({
    required this.order,
    required this.isDriverView,
    required this.messages,
    required this.onClose,
    this.onMarkInOven,
    this.onMarkReadyForDispatch,
    this.onMarkOnTheWay,
    this.onComplete,
  });

  final AdminDashboardOrder order;
  final bool isDriverView;
  final List<CheckoutChatMessage> messages;
  final VoidCallback onClose;
  final Future<void> Function()? onMarkInOven;
  final Future<void> Function()? onMarkReadyForDispatch;
  final Future<void> Function()? onMarkOnTheWay;
  final Future<void> Function()? onComplete;

  @override
  Widget build(BuildContext context) {
    final notes = order.notes?.trim();
    final deltaSummary = _summarizeOrderAddonChanges(order);
    final stageLabel = _operatorStageLabel(order);
    final assignedOperatorEmail = order.assignedOperatorEmail?.trim();
    final showDriverDeliveryReminder = _needsDriverDeliveryReminder(order);
    final canManageWorkflow = order.assignedToMe && order.isInProgress;
    final hasIntermediateWorkflow = onMarkInOven != null ||
        onMarkReadyForDispatch != null ||
        onMarkOnTheWay != null;
    final hasWorkflowActions =
        canManageWorkflow && (hasIntermediateWorkflow || onComplete != null);
    final showOvenCapacityNotice = canManageWorkflow &&
        order.supportsProgressUpdates &&
        !order.canMarkInOven &&
        _operatorStageIndex(order) < 2;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: const Color(0xF0141414),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Podglad zamowienia #${order.checkoutOrderId}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFFF8EEE6),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                _TopIconButton(
                  icon: Icons.close_rounded,
                  onTap: onClose,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  icon: Icons.receipt_long_outlined,
                  label: '${order.itemCount} poz.',
                ),
                _MetaChip(
                  icon: Icons.add_circle_outline_rounded,
                  label: '+${deltaSummary.addedCount}',
                ),
                _MetaChip(
                  icon: Icons.remove_circle_outline_rounded,
                  label: '-${deltaSummary.removedCount}',
                ),
                if (stageLabel.isNotEmpty)
                  _MetaChip(
                    icon: Icons.route_outlined,
                    label: stageLabel,
                  ),
                _MetaChip(
                  icon: Icons.location_on_outlined,
                  label: order.addressTitle,
                ),
              ],
            ),
            if (hasWorkflowActions) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1B1B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x24FFFFFF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Postep realizacji',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFFF7EEE6),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasIntermediateWorkflow
                          ? isDriverView
                              ? 'Aktualny etap dostawy: $stageLabel. Zmiany trafiaja od razu do trackera klienta.'
                              : onMarkReadyForDispatch != null
                                  ? 'Aktualny etap: $stageLabel. Po oznaczeniu gotowosci zlecenie trafi do kolejki kierowcy.'
                                  : 'Aktualny etap: $stageLabel. Te akcje od razu aktualizuja tracker klienta.'
                          : 'To zamowienie nie korzysta z etapow posrednich. Mozesz je tylko podjac i zakonczyc.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFD6C6BA),
                            height: 1.35,
                          ),
                    ),
                    if (showOvenCapacityNotice) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${order.ovenKind == 'udka' ? 'Piec udek' : 'Piec zapiekanek'} jest aktualnie zajety (${order.ovenLoad}/${order.ovenCapacity}). To zamowienie potrzebuje ${order.ovenSlotCount} ${order.ovenSlotCount == 1 ? 'miejsca' : 'miejsc'}, wiec poczeka na wolny wsad.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFFFC891),
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                      ),
                    ],
                    if (showDriverDeliveryReminder) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Przekroczono ETA tej dostawy. Potwierdz z klientem, czy zamowienie #${order.checkoutOrderId} zostalo dostarczone.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFFFC891),
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (onMarkInOven != null)
                          FilledButton.icon(
                            onPressed: () => onMarkInOven!.call(),
                            icon: const Icon(Icons.local_fire_department),
                            label: const Text('Wstawiono do pieca'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFE98B38),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        if (onMarkReadyForDispatch != null)
                          OutlinedButton.icon(
                            onPressed: () => onMarkReadyForDispatch!.call(),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Gotowe do wysylki'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFFD8B4),
                              side: const BorderSide(
                                color: Color(0x40FFB061),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        if (onMarkOnTheWay != null)
                          OutlinedButton.icon(
                            onPressed: () => onMarkOnTheWay!.call(),
                            icon: const Icon(Icons.delivery_dining_outlined),
                            label: Text(
                              isDriverView ? 'Rozpocznij dostawe' : 'W drodze',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFF6EEE7),
                              side: const BorderSide(
                                color: Color(0x30FFFFFF),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        if (onComplete != null)
                          OutlinedButton.icon(
                            onPressed: () => onComplete!.call(),
                            icon: const Icon(Icons.done_all_rounded),
                            label: Text(
                              isDriverView ? 'Dostarczono' : 'Zakoncz',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF79F5B8),
                              side: const BorderSide(
                                color: Color(0x4479F5B8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else if (order.isInProgress &&
                assignedOperatorEmail != null &&
                assignedOperatorEmail.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1B1B),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  order.assignedToMe
                      ? 'To zamowienie jest przypisane do Ciebie.'
                      : 'To zamowienie prowadzi $assignedOperatorEmail. Szczegoly sa dostepne tylko do podgladu.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD6C6BA),
                        height: 1.35,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in order.items) ...[
                      _TakenOrderItemTile(item: item),
                      const SizedBox(height: 10),
                    ],
                    if (messages.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1B1B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x24FFFFFF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mini-chat klienta',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFFF7EEE6),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            for (var index = 0;
                                index < messages.length;
                                index++) ...[
                              _TakenOrderChatBubble(message: messages[index]),
                              if (index < messages.length - 1)
                                const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (notes != null && notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1B1B),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Uwagi',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFFF7EEE6),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              notes,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: const Color(0xFFD4C4B8),
                                    height: 1.35,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TakenOrderItemTile extends StatelessWidget {
  const _TakenOrderItemTile({
    required this.item,
  });

  final AdminDashboardOrderItem item;

  @override
  Widget build(BuildContext context) {
    final changes = _parseAddonChangeCounts(item.description);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.quantity == 1
                      ? item.name
                      : '${item.name} x${item.quantity}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFF7EEE6),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (item.price != null)
                Text(
                  'PLN ${item.price!.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFFE7D0BB),
                        fontWeight: FontWeight.w800,
                      ),
                ),
            ],
          ),
          if (item.description != null &&
              item.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.description!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFD4C4B8),
                    height: 1.35,
                  ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.add_circle_outline_rounded,
                label: '+${changes.addedCount} dodatkow',
              ),
              _MetaChip(
                icon: Icons.remove_circle_outline_rounded,
                label: '-${changes.removedCount} dodatkow',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TakenOrderChatBubble extends StatelessWidget {
  const _TakenOrderChatBubble({
    required this.message,
  });

  final CheckoutChatMessage message;

  @override
  Widget build(BuildContext context) {
    final senderRole = message.senderRole.trim().toLowerCase();
    final isCustomer = senderRole == 'customer';
    final accentColor =
        isCustomer ? const Color(0xFFE48A32) : const Color(0xFF63D7D2);

    return Align(
      alignment: isCustomer ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCustomer ? const Color(0xFF241A12) : const Color(0xFF162322),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isCustomer ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(
              message.authorLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              message.message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFF3E8DE),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatDateTime(message.createdAt),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFB8AAA0),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadChatBadge extends StatelessWidget {
  const _UnreadChatBadge({
    required this.count,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5E57),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFBE4E3), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44FF5E57),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _CatalogRepositoryDialog extends StatefulWidget {
  const _CatalogRepositoryDialog({
    required this.authSession,
    required this.repository,
    required this.onClose,
  });

  final AuthSession authSession;
  final AdminDashboardRepository repository;
  final VoidCallback onClose;

  @override
  State<_CatalogRepositoryDialog> createState() =>
      _CatalogRepositoryDialogState();
}

class _CatalogRepositoryDialogState extends State<_CatalogRepositoryDialog> {
  AdminCatalogData? _catalog;
  Object? _error;
  bool _isLoading = true;
  final Set<String> _busyItems = <String>{};

  AdminCatalogData _copyCatalog({
    required AdminCatalogData current,
    AdminCatalogData? replacement,
    List<AdminCatalogPosition>? positions,
    List<AdminCatalogAddon>? addons,
  }) {
    if (replacement != null) {
      return replacement;
    }
    return AdminCatalogData(
      deliveryMinimumAmount: current.deliveryMinimumAmount,
      deliveryRadiusKm: current.deliveryRadiusKm,
      deliveryOriginAddress: current.deliveryOriginAddress,
      openingHours: current.openingHours,
      positions: positions ?? current.positions,
      addons: addons ?? current.addons,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final catalog = await widget.repository.fetchCatalog(
        authSession: widget.authSession,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = catalog;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePosition(AdminCatalogPosition position) async {
    final busyKey = 'position:${position.positionId}';
    setState(() {
      _busyItems.add(busyKey);
    });

    try {
      final updated = await widget.repository.updatePositionActive(
        authSession: widget.authSession,
        positionId: position.positionId,
        isActive: !position.isActive,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final current = _catalog;
        if (current == null) {
          return;
        }
        _catalog = _copyCatalog(
          current: current,
          positions: current.positions
              .map((item) =>
                  item.positionId == updated.positionId ? updated : item)
              .toList(growable: false),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyItems.remove(busyKey);
        });
      }
    }
  }

  Future<void> _toggleAddon(AdminCatalogAddon addon) async {
    final busyKey = 'addon:${addon.addonId}';
    setState(() {
      _busyItems.add(busyKey);
    });

    try {
      final updated = await widget.repository.updateAddonActive(
        authSession: widget.authSession,
        addonId: addon.addonId,
        isActive: !addon.isActive,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final current = _catalog;
        if (current == null) {
          return;
        }
        _catalog = _copyCatalog(
          current: current,
          addons: current.addons
              .map((item) => item.addonId == updated.addonId ? updated : item)
              .toList(growable: false),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyItems.remove(busyKey);
        });
      }
    }
  }

  Future<double?> _showAmountEditorDialog({
    required String title,
    required String hintText,
    required double initialValue,
  }) async {
    final controller = TextEditingController(
      text: initialValue.toStringAsFixed(2),
    );

    try {
      return await showDialog<double>(
        context: context,
        barrierColor: const Color(0xC4000000),
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF181311),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(
            title,
            style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFF8EEE7),
                  fontWeight: FontWeight.w900,
                ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: const TextStyle(color: Color(0xFFF8EEE7)),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Color(0x80F8EEE7)),
              filled: true,
              fillColor: const Color(0xFF26201D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x24FFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x24FFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x66FFB061)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Anuluj',
                style: TextStyle(
                  color: Color(0xFFD0C1B5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                final normalized = controller.text.replaceAll(',', '.').trim();
                final parsed = double.tryParse(normalized);
                if (parsed == null) {
                  return;
                }
                Navigator.of(dialogContext).pop(parsed);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE98B38),
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Zapisz',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _showTextEditorDialog({
    required String title,
    required String hintText,
    required String initialValue,
    int maxLines = 3,
  }) async {
    final controller = TextEditingController(text: initialValue);

    try {
      return await showDialog<String>(
        context: context,
        barrierColor: const Color(0xC4000000),
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF181311),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(
            title,
            style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFFF8EEE7),
                  fontWeight: FontWeight.w900,
                ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: maxLines,
            style: const TextStyle(color: Color(0xFFF8EEE7)),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Color(0x80F8EEE7)),
              filled: true,
              fillColor: const Color(0xFF26201D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x24FFFFFF)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x24FFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0x66FFB061)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Anuluj',
                style: TextStyle(
                  color: Color(0xFFD0C1B5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                final normalized = controller.text.trim();
                if (normalized.isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(normalized);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE98B38),
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Zapisz',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  String? _normalizeOpeningHoursValue(String rawValue) {
    final normalized = rawValue.trim();
    final match =
        RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return normalized;
  }

  int _openingHoursToMinutes(String value) {
    final parts = value.split(':');
    return (int.parse(parts[0]) * 60) + int.parse(parts[1]);
  }

  Future<({String openTime, String closeTime})?> _showOpeningHoursEditorDialog({
    required String openTime,
    required String closeTime,
  }) async {
    final openController = TextEditingController(text: openTime);
    final closeController = TextEditingController(text: closeTime);
    String? errorText;

    try {
      return await showDialog<({String openTime, String closeTime})>(
        context: context,
        barrierColor: const Color(0xC4000000),
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF181311),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(
              'Godziny otwarcia lokalu',
              style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFFF8EEE7),
                    fontWeight: FontWeight.w900,
                  ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: openController,
                  keyboardType: TextInputType.datetime,
                  autofocus: true,
                  style: const TextStyle(color: Color(0xFFF8EEE7)),
                  decoration: InputDecoration(
                    labelText: 'Otwarcie',
                    hintText: 'HH:mm',
                    errorText: errorText,
                    hintStyle: const TextStyle(color: Color(0x80F8EEE7)),
                    filled: true,
                    fillColor: const Color(0xFF26201D),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x24FFFFFF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x24FFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x66FFB061)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: closeController,
                  keyboardType: TextInputType.datetime,
                  style: const TextStyle(color: Color(0xFFF8EEE7)),
                  decoration: InputDecoration(
                    labelText: 'Zamkniecie',
                    hintText: 'HH:mm',
                    hintStyle: const TextStyle(color: Color(0x80F8EEE7)),
                    filled: true,
                    fillColor: const Color(0xFF26201D),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x24FFFFFF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x24FFFFFF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x66FFB061)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Podaj godziny w formacie HH:mm, np. 12:00 i 21:00.',
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD0C1B5),
                        height: 1.35,
                      ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text(
                  'Anuluj',
                  style: TextStyle(
                    color: Color(0xFFD0C1B5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final normalizedOpen =
                      _normalizeOpeningHoursValue(openController.text);
                  final normalizedClose =
                      _normalizeOpeningHoursValue(closeController.text);
                  if (normalizedOpen == null || normalizedClose == null) {
                    setDialogState(() {
                      errorText = 'Uzyj formatu HH:mm.';
                    });
                    return;
                  }
                  if (_openingHoursToMinutes(normalizedClose) <=
                      _openingHoursToMinutes(normalizedOpen)) {
                    setDialogState(() {
                      errorText =
                          'Godzina zamkniecia musi byc pozniejsza niz otwarcia.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    (
                      openTime: normalizedOpen,
                      closeTime: normalizedClose,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE98B38),
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'Zapisz',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      openController.dispose();
      closeController.dispose();
    }
  }

  Future<void> _editOpeningHours() async {
    final currentHours = _catalog?.openingHours;
    final nextHours = await _showOpeningHoursEditorDialog(
      openTime: currentHours?.openTime ?? '12:00',
      closeTime: currentHours?.closeTime ?? '21:00',
    );
    if (nextHours == null) {
      return;
    }

    const busyKey = 'opening-hours';
    setState(() {
      _busyItems.add(busyKey);
    });

    try {
      final updatedCatalog = await widget.repository.updateOpeningHours(
        authSession: widget.authSession,
        openTime: nextHours.openTime,
        closeTime: nextHours.closeTime,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = updatedCatalog;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zaktualizowano godziny otwarcia lokalu.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyItems.remove(busyKey);
        });
      }
    }
  }

  Future<void> _editPositionPrice(AdminCatalogPosition position) async {
    final nextPrice = await _showAmountEditorDialog(
      title: 'Cena produktu',
      hintText: 'np. 22.00',
      initialValue: position.price ?? 0,
    );
    if (nextPrice == null) {
      return;
    }

    final busyKey = 'position:${position.positionId}';
    setState(() {
      _busyItems.add(busyKey);
    });

    try {
      final updated = await widget.repository.updatePositionActive(
        authSession: widget.authSession,
        positionId: position.positionId,
        price: nextPrice,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final current = _catalog;
        if (current == null) {
          return;
        }
        _catalog = _copyCatalog(
          current: current,
          positions: current.positions
              .map((item) =>
                  item.positionId == updated.positionId ? updated : item)
              .toList(growable: false),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyItems.remove(busyKey);
        });
      }
    }
  }

  Future<void> _editAddonPrice(AdminCatalogAddon addon) async {
    final nextPrice = await _showAmountEditorDialog(
      title: 'Cena dodatku',
      hintText: 'np. 3.50',
      initialValue: addon.price,
    );
    if (nextPrice == null) {
      return;
    }

    final busyKey = 'addon:${addon.addonId}';
    setState(() {
      _busyItems.add(busyKey);
    });

    try {
      final updated = await widget.repository.updateAddonActive(
        authSession: widget.authSession,
        addonId: addon.addonId,
        price: nextPrice,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final current = _catalog;
        if (current == null) {
          return;
        }
        _catalog = _copyCatalog(
          current: current,
          addons: current.addons
              .map((item) => item.addonId == updated.addonId ? updated : item)
              .toList(growable: false),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyItems.remove(busyKey);
        });
      }
    }
  }

  Future<void> _editDeliveryMinimumAmount() async {
    final currentAmount = _catalog?.deliveryMinimumAmount ?? 20;
    final nextAmount = await _showAmountEditorDialog(
      title: 'Minimalna wartosc dostawy',
      hintText: 'np. 20.00',
      initialValue: currentAmount,
    );
    if (nextAmount == null) {
      return;
    }

    const busyKey = 'delivery-minimum';
    setState(() {
      _busyItems.add(busyKey);
    });

    try {
      final updatedCatalog =
          await widget.repository.updateDeliveryMinimumAmount(
        authSession: widget.authSession,
        amount: nextAmount,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = updatedCatalog;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyItems.remove(busyKey);
        });
      }
    }
  }

  Future<void> _editDeliveryRadius() async {
    final currentRadius = _catalog?.deliveryRadiusKm ?? 8;
    final nextRadius = await _showAmountEditorDialog(
      title: 'Promien dostawy',
      hintText: 'np. 8.00',
      initialValue: currentRadius,
    );
    if (nextRadius == null) {
      return;
    }

    const busyKey = 'delivery-radius';
    setState(() {
      _busyItems.add(busyKey);
    });

    try {
      final updatedCatalog = await widget.repository.updateDeliveryRadius(
        authSession: widget.authSession,
        radiusKm: nextRadius,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = updatedCatalog;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyItems.remove(busyKey);
        });
      }
    }
  }

  Future<void> _editDeliveryOriginAddress() async {
    final currentAddress = _catalog?.deliveryOriginAddress ?? '';
    final nextAddress = await _showTextEditorDialog(
      title: 'Adres lokalu dla dostaw',
      hintText: 'np. ul. Marszalkowska 1, 00-001 Warszawa',
      initialValue: currentAddress,
      maxLines: 4,
    );
    if (nextAddress == null) {
      return;
    }

    const busyKey = 'delivery-origin-address';
    setState(() {
      _busyItems.add(busyKey);
    });

    try {
      final updatedCatalog =
          await widget.repository.updateDeliveryOriginAddress(
        authSession: widget.authSession,
        address: nextAddress,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = updatedCatalog;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyItems.remove(busyKey);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final media = MediaQuery.of(context);
    final compactLayout = media.size.width < 640;
    final deliveryOriginAddress = catalog?.deliveryOriginAddress ?? '';

    Widget body;
    if (_isLoading && catalog == null) {
      body = const Center(
        child: CircularProgressIndicator(color: Color(0xFFE98B38)),
      );
    } else if (_error != null && catalog == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nie udalo sie pobrac repozytorium produktow.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF8EEE6),
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              _error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFD3C4B9),
                  ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loadCatalog,
              child: const Text('Sprobuj ponownie'),
            ),
          ],
        ),
      );
    } else {
      final positions = catalog?.positions ?? const <AdminCatalogPosition>[];
      final addons = catalog?.addons ?? const <AdminCatalogAddon>[];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CatalogSectionHeader(
            title: 'Ustawienia dostawy',
            subtitle:
                'Tutaj ustawisz minimum, promien i punkt odniesienia dla walidacji dostaw.',
          ),
          const SizedBox(height: 12),
          _CatalogSettingTile(
            title: 'Minimalna wartosc zamowienia z dostawa',
            valueLabel:
                'PLN ${(catalog?.deliveryMinimumAmount ?? 20).toStringAsFixed(2)}',
            subtitle:
                'Przy zamowieniach ponizej tego progu klient dostanie komunikat i nie sfinalizuje dostawy.',
            busy: _busyItems.contains('delivery-minimum'),
            onEdit: _editDeliveryMinimumAmount,
          ),
          const SizedBox(height: 10),
          _CatalogSettingTile(
            title: 'Promien dostawy',
            valueLabel:
                '${(catalog?.deliveryRadiusKm ?? 8).toStringAsFixed(2)} km',
            subtitle:
                'Nowe adresy dostawy sa akceptowane tylko w tym promieniu od adresu lokalu.',
            busy: _busyItems.contains('delivery-radius'),
            onEdit: _editDeliveryRadius,
          ),
          const SizedBox(height: 10),
          _CatalogSettingTile(
            title: 'Adres lokalu dla dostaw',
            valueLabel: deliveryOriginAddress.trim().isNotEmpty
                ? deliveryOriginAddress
                : 'Nie ustawiono',
            subtitle:
                'Ten adres jest geokodowany i stanowi punkt odniesienia dla promienia dostawy.',
            busy: _busyItems.contains('delivery-origin-address'),
            onEdit: _editDeliveryOriginAddress,
          ),
          const SizedBox(height: 10),
          _CatalogSettingTile(
            title: 'Godziny otwarcia lokalu',
            valueLabel: catalog?.openingHours.formattedRange ?? '12:00-21:00',
            subtitle:
                'Ten zakres jest pokazywany na dashboardzie klienta oraz panelach admina, pracownika i kierowcy.',
            busy: _busyItems.contains('opening-hours'),
            onEdit: _editOpeningHours,
          ),
          const SizedBox(height: 18),
          _CatalogSectionHeader(
            title: 'Produkty',
            subtitle:
                'Dezaktywowany produkt nie pojawi sie juz na dashboardzie klienta.',
          ),
          const SizedBox(height: 12),
          for (final position in positions) ...[
            _CatalogPositionTile(
              position: position,
              busy: _busyItems.contains('position:${position.positionId}'),
              onToggle: () => _togglePosition(position),
              onEditPrice: () => _editPositionPrice(position),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          _CatalogSectionHeader(
            title: 'Dodatki',
            subtitle:
                'Dezaktywowany dodatek zniknie z personalizacji pozycji po stronie klienta.',
          ),
          const SizedBox(height: 12),
          for (final addon in addons) ...[
            _CatalogAddonTile(
              addon: addon,
              busy: _busyItems.contains('addon:${addon.addonId}'),
              onToggle: () => _toggleAddon(addon),
              onEditPrice: () => _editAddonPrice(addon),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compactLayout ? 8 : 24,
        vertical: compactLayout ? 8 : 24,
      ),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: compactLayout ? media.size.width - 16 : 760,
          maxHeight: compactLayout ? media.size.height - 16 : 760,
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: const Color(0xF0141414),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x24FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compactLayout)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repozytorium produktow',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFFF8EEE6),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Administrator moze tutaj sterowac dostepnoscia, cenami, dostawa i godzinami otwarcia.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFD4C4B8),
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TopIconButton(
                          icon: Icons.refresh_rounded,
                          onTap: _loadCatalog,
                        ),
                        const SizedBox(width: 8),
                        _TopIconButton(
                          icon: Icons.close_rounded,
                          onTap: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Repozytorium produktow',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: const Color(0xFFF8EEE6),
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Administrator moze tutaj sterowac dostepnoscia, cenami, dostawa i godzinami otwarcia.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFFD4C4B8),
                                    height: 1.35,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  _TopIconButton(
                    icon: Icons.refresh_rounded,
                    onTap: _loadCatalog,
                  ),
                  const SizedBox(width: 8),
                  _TopIconButton(
                    icon: Icons.close_rounded,
                    onTap: widget.onClose,
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Expanded(
              child: ScrollConfiguration(
                behavior:
                    const MaterialScrollBehavior().copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogSectionHeader extends StatelessWidget {
  const _CatalogSectionHeader({
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
                color: const Color(0xFFF7EEE6),
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFD4C4B8),
                height: 1.35,
              ),
        ),
      ],
    );
  }
}

class _CatalogPositionTile extends StatelessWidget {
  const _CatalogPositionTile({
    required this.position,
    required this.busy,
    required this.onToggle,
    required this.onEditPrice,
  });

  final AdminCatalogPosition position;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onEditPrice;

  @override
  Widget build(BuildContext context) {
    final priceLabel = position.price == null
        ? 'PLN --'
        : 'PLN ${position.price!.toStringAsFixed(2)}';

    return _CatalogEntryTile(
      title: position.name,
      subtitle: position.description ?? 'Pozycja menu bez dodatkowego opisu.',
      metaLabel: position.positionType.trim().isEmpty
          ? priceLabel
          : '${position.positionType} | $priceLabel',
      isActive: position.isActive,
      busy: busy,
      onEditPrice: onEditPrice,
      onToggle: onToggle,
    );
  }
}

class _CatalogAddonTile extends StatelessWidget {
  const _CatalogAddonTile({
    required this.addon,
    required this.busy,
    required this.onToggle,
    required this.onEditPrice,
  });

  final AdminCatalogAddon addon;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onEditPrice;

  @override
  Widget build(BuildContext context) {
    return _CatalogEntryTile(
      title: addon.name,
      subtitle: addon.description ?? 'Dodatek bez dodatkowego opisu.',
      metaLabel:
          'Dodatek | PLN ${addon.price.toStringAsFixed(2)} | sort ${addon.sortOrder}',
      isActive: addon.isActive,
      busy: busy,
      onEditPrice: onEditPrice,
      onToggle: onToggle,
    );
  }
}

class _CatalogEntryTile extends StatelessWidget {
  const _CatalogEntryTile({
    required this.title,
    required this.subtitle,
    required this.metaLabel,
    required this.isActive,
    required this.busy,
    required this.onEditPrice,
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final String metaLabel;
  final bool isActive;
  final bool busy;
  final VoidCallback onEditPrice;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        isActive ? const Color(0xFF79F5B8) : const Color(0xFFF29F60);
    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        isActive ? 'Aktywny' : 'Ukryty',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
    final actionControls = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        statusBadge,
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy ? null : onEditPrice,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Cena'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFFD7B5),
            side: const BorderSide(color: Color(0x40FFB061)),
          ),
        ),
        const SizedBox(height: 10),
        busy
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFFE98B38),
                ),
              )
            : Switch.adaptive(
                value: isActive,
                onChanged: (_) => onToggle(),
                activeThumbColor: const Color(0xFF79F5B8),
              ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFF7EEE6),
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                metaLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFE7D0BB),
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                maxLines: compact ? 4 : 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD4C4B8),
                      height: 1.35,
                    ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 12),
                actionControls,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: 14),
              actionControls,
            ],
          );
        },
      ),
    );
  }

}

class _StaffPresenceDialog extends StatefulWidget {
  const _StaffPresenceDialog({
    required this.authSession,
    required this.repository,
    required this.onClose,
  });

  final AuthSession authSession;
  final AdminDashboardRepository repository;
  final VoidCallback onClose;

  @override
  State<_StaffPresenceDialog> createState() => _StaffPresenceDialogState();
}

class _StaffPresenceDialogState extends State<_StaffPresenceDialog> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  AdminStaffPresenceData? _data;
  Object? _error;
  bool _isLoading = true;
  String _query = '';

  bool get _isSearchActive => _query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadPresence();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      final nextQuery = _searchController.text.trim();
      if (nextQuery == _query) {
        return;
      }
      if (mounted) {
        setState(() {
          _query = nextQuery;
        });
      }
      _loadPresence(showLoading: false);
    });
  }

  Future<void> _loadPresence({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final presence = await widget.repository.fetchStaffPresence(
        authSession: widget.authSession,
        query: _query,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _data = presence;
        _error = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    final searchResults = data?.allResults ?? const <AdminStaffPresencePerson>[];
    final currentlyAvailable =
        data?.currentlyAvailable ?? const <AdminStaffPresencePerson>[];
    final recentlyAvailable =
        data?.recentlyAvailable ?? const <AdminStaffPresencePerson>[];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        decoration: BoxDecoration(
          color: const Color(0xF01C1A19),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x2AFFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x70000000),
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Obecnosc pracownikow',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: const Color(0xFFF8F0E8),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Dostepni teraz, aktywni w ostatniej godzinie i wyszukiwarka calego personelu.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFD3C4B8),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _TopIconButton(
                    icon: Icons.close_rounded,
                    onTap: widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Szukaj wszystkich pracownikow',
                style: const TextStyle(color: Color(0xFFF7EEE6)),
                placeholderStyle: const TextStyle(color: Color(0xFF9F9389)),
                backgroundColor: const Color(0xFF2A2624),
                itemColor: const Color(0xFFF4E7DC),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (_isLoading && data == null) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFE98B38),
                        ),
                      );
                    }
                    if (_error != null && data == null) {
                      return _StaffPresenceEmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Nie udalo sie pobrac listy pracownikow',
                        subtitle: _error.toString(),
                      );
                    }

                    if (_isSearchActive) {
                      if (searchResults.isEmpty) {
                        return const _StaffPresenceEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'Brak wynikow',
                          subtitle: 'Nie znaleziono pracownikow dla podanej frazy.',
                        );
                      }
                      return _StaffPresenceSection(
                        title: 'Wyniki wyszukiwania',
                        people: searchResults,
                      );
                    }

                    return ListView(
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _StaffPresenceSection(
                          title: 'Dostepni teraz',
                          people: currentlyAvailable,
                          emptyLabel: 'Brak aktualnie dostepnych pracownikow.',
                        ),
                        const SizedBox(height: 18),
                        _StaffPresenceSection(
                          title: 'Dostepni w ostatniej godzinie',
                          people: recentlyAvailable,
                          emptyLabel:
                              'Nikt nie byl dostepny w ostatniej godzinie poza aktywnymi teraz.',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffPresenceSection extends StatelessWidget {
  const _StaffPresenceSection({
    required this.title,
    required this.people,
    this.emptyLabel,
  });

  final String title;
  final List<AdminStaffPresencePerson> people;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFFF7EFE6),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        if (people.isEmpty)
          _StaffPresenceEmptyState(
            icon: Icons.groups_rounded,
            title: emptyLabel ?? 'Brak danych',
            subtitle: '',
            compact: true,
          )
        else
          ...people.map(
            (person) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StaffPresencePersonTile(person: person),
            ),
          ),
      ],
    );
  }
}

class _StaffPresencePersonTile extends StatelessWidget {
  const _StaffPresencePersonTile({
    required this.person,
  });

  final AdminStaffPresencePerson person;

  @override
  Widget build(BuildContext context) {
    final title = person.displayName.trim().isEmpty ? person.email : person.displayName;
    final subtitle = person.email.trim().isNotEmpty &&
            person.email.trim().toLowerCase() != title.trim().toLowerCase()
        ? person.email
        : null;
    final activityLabel = person.lastSeenAt == null
        ? 'Brak historii dostepnosci'
        : 'Ostatnio dostepny: ${_formatDateTime(person.lastSeenAt!)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xC9262321),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: person.isCurrentlyAvailable
              ? const Color(0x5533D17A)
              : const Color(0x1EFFFFFF),
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _staffPresenceBadgeColor(person),
            ),
            alignment: Alignment.center,
            child: Text(
              person.initials.isEmpty ? '?' : person.initials,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFFF8F0E8),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    if (person.isCurrentlyAvailable) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x2233D17A),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x6633D17A)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 8,
                              color: Color(0xFF33D17A),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Dostepny',
                              style:
                                  Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: const Color(0xFFBFF2D3),
                                        fontWeight: FontWeight.w800,
                                      ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFD0C0B5),
                        ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  activityLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFAA9D92),
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

class _StaffPresenceEmptyState extends StatelessWidget {
  const _StaffPresenceEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 16 : 28,
      ),
      decoration: BoxDecoration(
        color: const Color(0xA922201F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFD1C0B3), size: compact ? 24 : 30),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFF5ECE4),
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFC8B9AF),
                    height: 1.35,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogSettingTile extends StatelessWidget {
  const _CatalogSettingTile({
    required this.title,
    required this.valueLabel,
    required this.subtitle,
    required this.busy,
    required this.onEdit,
  });

  final String title;
  final String valueLabel;
  final String subtitle;
  final bool busy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFF7EEE6),
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                valueLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFFFFD7B5),
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                maxLines: compact ? 4 : 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD4C4B8),
                      height: 1.35,
                    ),
              ),
            ],
          );
          final action = busy
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFFE98B38),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Edytuj'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD7B5),
                    side: const BorderSide(color: Color(0x40FFB061)),
                  ),
                );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 12),
                action,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              const SizedBox(width: 14),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _AdminStateCard extends StatelessWidget {
  const _AdminStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xE0161616),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0x22FFFFFF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 66,
                width: 66,
                decoration: BoxDecoration(
                  color: const Color(0x1DE38A38),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 34, color: const Color(0xFFF9E9DA)),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFFF6EEE7),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD3C4B9),
                  height: 1.4,
                ),
              ),
              if (buttonLabel != null && onPressed != null) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => onPressed!(),
                  child: Text(buttonLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminGlow extends StatelessWidget {
  const _AdminGlow({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _AddonChangeCounts {
  const _AddonChangeCounts({
    this.addedCount = 0,
    this.removedCount = 0,
  });

  final int addedCount;
  final int removedCount;

  _AddonChangeCounts add(_AddonChangeCounts other) {
    return _AddonChangeCounts(
      addedCount: addedCount + other.addedCount,
      removedCount: removedCount + other.removedCount,
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day.$month, $hour:$minute';
}

_AddonChangeCounts _summarizeOrderAddonChanges(AdminDashboardOrder order) {
  var summary = const _AddonChangeCounts();
  for (final item in order.items) {
    summary = summary.add(_parseAddonChangeCounts(item.description));
  }
  return summary;
}

int _operatorStageIndex(AdminDashboardOrder order) {
  if (!order.supportsProgressUpdates) {
    final lifecycleStatus = order.lifecycleStatus.trim().toLowerCase();
    if (lifecycleStatus == 'completed') {
      return _isDeliveryOrder(order) ? 4 : 3;
    }
    if (_isReadyForDeliveryStage(order)) {
      return 3;
    }
    if (order.processingStatus.trim().toLowerCase() == 'assigned') {
      return 1;
    }
    return 0;
  }

  final verificationStage = order.verificationStage.trim().toLowerCase();
  final lifecycleStatus = order.lifecycleStatus.trim().toLowerCase();

  if (verificationStage == 'in_oven' || verificationStage == 'oven') {
    return 2;
  }

  if (verificationStage == 'ready_for_delivery') {
    return 3;
  }

  if ({
        'on_the_way',
        'delivery_started',
        'awaiting_receipt_confirmation',
        'delivery_extended',
        'delivered_confirmed',
        'completed_by_admin',
      }.contains(verificationStage) ||
      lifecycleStatus == 'completed') {
    return _isDeliveryOrder(order) ? 4 : 3;
  }

  if (order.processingStatus.trim().toLowerCase() == 'assigned') {
    return 1;
  }

  return 0;
}

String _operatorStageLabel(AdminDashboardOrder order) {
  if (!order.supportsProgressUpdates) {
    switch (_operatorStageIndex(order)) {
      case 0:
        return 'Oczekuje na podjecie';
      case 1:
        return 'Przyjete do realizacji';
      case 3:
        return _isDeliveryOrder(order) ? 'Gotowe do wysylki' : 'Zakonczone';
      case 4:
        return 'W dostawie';
      default:
        return '';
    }
  }

  switch (_operatorStageIndex(order)) {
    case 0:
      return 'Oczekuje na podjecie';
    case 1:
      return 'Przyjete do realizacji';
    case 2:
      return 'W piecu';
    case 3:
      return _isDeliveryOrder(order) ? 'Gotowe do wysylki' : 'Gotowe';
    case 4:
      return 'W dostawie';
    default:
      return '';
  }
}

bool _isDeliveryOrder(AdminDashboardOrder order) {
  final fulfillmentMethod = order.fulfillmentMethod.trim().toLowerCase();
  return fulfillmentMethod == 'dostawa' || fulfillmentMethod == 'delivery';
}

bool _isReadyForDeliveryStage(AdminDashboardOrder order) {
  return order.verificationStage.trim().toLowerCase() == 'ready_for_delivery';
}

bool _needsDriverDeliveryReminder(AdminDashboardOrder order) {
  if (!_isDeliveryOrder(order) || !order.assignedToMe) {
    return false;
  }

  final lifecycleStatus = order.lifecycleStatus.trim().toLowerCase();
  if (lifecycleStatus == 'completed') {
    return false;
  }

  final verificationStage = order.verificationStage.trim().toLowerCase();
  if (!{
    'on_the_way',
    'delivery_started',
    'delivery_extended',
  }.contains(verificationStage)) {
    return false;
  }

  return order.remainingEtaMinutes <= 0;
}

String _boardStatusLabelForOrder(
  AdminDashboardOrder order, {
  required bool isDriverView,
}) {
  if (isDriverView) {
    return 'W dostawie';
  }
  if (_isReadyForDeliveryStage(order)) {
    return 'Gotowe do wysylki';
  }
  return 'Podjete';
}

_AddonChangeCounts _parseAddonChangeCounts(String? description) {
  if (description == null || description.isEmpty) {
    return const _AddonChangeCounts();
  }

  final addonSectionMatch = RegExp(r'Dodatki:\s*(.+)$').firstMatch(description);
  final addonSection = addonSectionMatch?.group(1);
  if (addonSection == null || addonSection.trim().isEmpty) {
    return const _AddonChangeCounts();
  }

  var added = 0;
  var removed = 0;
  final matches =
      RegExp(r'([+-])[^,+-]+?(?: x(\d+))?(?=,|$)').allMatches(addonSection);

  for (final match in matches) {
    final sign = match.group(1);
    final quantity = int.tryParse(match.group(2) ?? '') ?? 1;
    if (sign == '+') {
      added += quantity;
    } else if (sign == '-') {
      removed += quantity;
    }
  }

  return _AddonChangeCounts(
    addedCount: added,
    removedCount: removed,
  );
}

Color _employeeBadgeColor(AdminDashboardActiveEmployee employee) {
  final seed = employee.userId == 0 ? employee.email.hashCode : employee.userId;
  final hue = (seed.abs() * 37) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.58, 0.46).toColor();
}

Color _staffPresenceBadgeColor(AdminStaffPresencePerson person) {
  final seed = person.userId == 0 ? person.email.hashCode : person.userId;
  final hue = (seed.abs() * 37) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.58, 0.46).toColor();
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../data/local/session_persistence.dart';
import '../../data/models/admin_dashboard.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/checkout_verification.dart';
import '../../data/repositories/admin_dashboard_repository.dart';
import '../../data/repositories/checkout_repository.dart';
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

    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _TakenOrderDetailsDialog(
        order: order,
        messages: orderMessages,
        onClose: () => Navigator.of(dialogContext).pop(),
        onMarkInOven: !order.supportsProgressUpdates ||
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
        onMarkOnTheWay: !order.supportsProgressUpdates ||
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
                  'Zamowienie #${order.checkoutOrderId} zostalo oznaczone jako w drodze.',
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
                  'Zamowienie #${order.checkoutOrderId} zostalo zakonczone.',
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
        title: widget.authSession.isEmployee
            ? 'Moja historia zamowien'
            : 'Historia zamknietych zamowien',
        subtitle: widget.authSession.isEmployee
            ? 'Zamowienia zakonczone przez zalogowanego pracownika.'
            : 'Wszystkie zamkniete zamowienia z panelu administratora.',
        orders: dashboard.closedOrders,
        onClose: () => Navigator.of(dialogContext).pop(),
        onOrderTap: (order) async {
          Navigator.of(dialogContext).pop();
          await _openTakenOrderDetails(order);
        },
      ),
    );
  }

  Future<void> _openTodayCompletedOrders(AdminDashboardData dashboard) async {
    final now = DateTime.now();
    final todayOrders = dashboard.closedOrders.where((order) {
      final reference = (order.closedAt ?? order.createdAt).toLocal();
      return reference.year == now.year &&
          reference.month == now.month &&
          reference.day == now.day;
    }).toList(growable: false);

    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xC4000000),
      builder: (dialogContext) => _ClosedOrdersHistoryDialog(
        title: 'Zamowienia zrealizowane dzis',
        subtitle: 'Lista zamknietych zamowien dla biezacego dnia.',
        orders: todayOrders,
        onClose: () => Navigator.of(dialogContext).pop(),
        onOrderTap: (order) async {
          Navigator.of(dialogContext).pop();
          await _openTakenOrderDetails(order);
        },
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
      final statCards = [
        _StatCardData(
          icon: Icons.support_agent_outlined,
          value: dashboard.pendingOrderCount.toString(),
          label: 'Oczekujace\nzamowienia',
          onTap: () => _scrollToSection(_pendingOrdersSectionKey),
        ),
        _StatCardData(
          icon: Icons.room_service_outlined,
          value: dashboard.inProgressOrderCount.toString(),
          label: 'Zamowienia w\nrealizacji',
          onTap: () => _scrollToSection(_inProgressOrdersSectionKey),
        ),
        _StatCardData(
          icon: Icons.history_outlined,
          value: dashboard.orderHistoryCount.toString(),
          label: isEmployee ? 'Moja historia\nzamowien' : 'Historia\nzamowien',
          onTap: () => _openClosedOrdersHistory(dashboard),
        ),
      ];
      if (!isEmployee) {
        statCards.insert(
          0,
          _StatCardData(
            icon: Icons.badge_outlined,
            value: dashboard.loggedInEmployeeCount.toString(),
            label: 'Zalogowani\npracownicy',
            activeEmployees: dashboard.activeEmployees,
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
                onRefresh: _loadDashboard,
                onLogout: _logout,
              ),
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
              if (!isEmployee) ...[
                const SizedBox(height: 22),
                _TurnoverCard(points: dashboard.turnoverLastDays),
                const SizedBox(height: 22),
              ] else
                const SizedBox(height: 22),
              KeyedSubtree(
                key: _pendingOrdersSectionKey,
                child: const _SectionHeader(
                  title: 'Oczekujace zamowienia',
                  subtitle:
                      'Nowe zamowienia z checkoutu, ktore nie zostaly jeszcze podjete.',
                ),
              ),
              const SizedBox(height: 12),
              if (dashboard.pendingOrders.isEmpty)
                const _EmptyOrdersCard(
                  icon: Icons.mark_chat_unread_outlined,
                  title: 'Brak zamowien niepodjetych',
                  message:
                      'Nowe zamowienia pojawia sie tutaj automatycznie po zapisie checkoutu.',
                )
              else
                for (final order in dashboard.pendingOrders) ...[
                  _AdminOrderCard(
                    order: order,
                    busy: _busyOrderIds.contains(order.checkoutOrderId),
                    accentColor: const Color(0xFFE48A32),
                    statusLabel: 'Niepodjete',
                    primaryActionLabel: 'Podejmij',
                    onPrimaryAction: () => _updateOrderStatus(
                      order,
                      'assigned',
                      'Zamowienie #${order.checkoutOrderId} zostalo podjete.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 10),
              KeyedSubtree(
                key: _inProgressOrdersSectionKey,
                child: const _SectionHeader(
                  title: 'Zamowienia w realizacji',
                  subtitle:
                      'Pozycje juz podjete przez zespol i gotowe do dalszej obslugi.',
                ),
              ),
              const SizedBox(height: 12),
              if (dashboard.inProgressOrders.isEmpty)
                const _EmptyOrdersCard(
                  icon: Icons.room_service_outlined,
                  title: 'Brak zamowien podjetych',
                  message: 'Po podjeciu zlecenia pojawi sie ono w tej sekcji.',
                )
              else
                for (final order in dashboard.inProgressOrders) ...[
                  _AdminOrderCard(
                    order: order,
                    busy: _busyOrderIds.contains(order.checkoutOrderId),
                    accentColor: const Color(0xFF63D7D2),
                    statusLabel: 'Podjete',
                    primaryActionLabel: 'Zakoncz',
                    secondaryActionLabel: 'Cofnij',
                    onPrimaryAction: () => _updateOrderStatus(
                      order,
                      'completed',
                      'Zamowienie #${order.checkoutOrderId} zostalo zakonczone.',
                    ),
                    onSecondaryAction: () => _updateOrderStatus(
                      order,
                      'unassigned',
                      'Zamowienie #${order.checkoutOrderId} wrocilo do oczekujacych.',
                    ),
                    onTap: () => _openTakenOrderDetails(order),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: _AdminBackground(child: body),
      bottomNavigationBar: dashboard == null || dashboard.myTakenOrders.isEmpty
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
    required this.onRefresh,
    required this.onLogout,
  });

  final String? adminEmail;
  final bool isEmployee;
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
                isEmployee ? 'Panel realizacji' : 'Panel administratora',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFFF5EFE9),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                adminEmail == null || adminEmail!.isEmpty
                    ? 'Nadzor zamowien online i stanu realizacji.'
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
        final slots =
            math.max(1, ((constraints.maxWidth + bubbleGap) / (bubbleSize + bubbleGap)).floor());
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
          children.add(_EmployeeInitialBubble(employee: visibleEmployees[index]));
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
    final title =
        employee.displayName.trim().isEmpty ? employee.email : employee.displayName;
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
    final values = points
        .map((point) => point.totalAmount)
        .toList(growable: false);
    final highestValue =
        values.fold<double>(0, (maxSoFar, value) => math.max(maxSoFar, value));
    final maxValue =
        highestValue <= 0 ? 4.0 : math.max(1, (highestValue * 1.5).ceil()).toDouble();
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
                label: 'ETA ${order.remainingEtaMinutes} min',
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
    required this.orders,
    required this.onClose,
    required this.onOrderTap,
  });

  final String title;
  final String subtitle;
  final List<AdminDashboardOrder> orders;
  final VoidCallback onClose;
  final ValueChanged<AdminDashboardOrder> onOrderTap;

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
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: const Color(0xFFF8EEE6),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
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
                  onTap: onClose,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: orders.isEmpty
                  ? const _EmptyOrdersCard(
                      icon: Icons.history_toggle_off_rounded,
                      title: 'Brak zamknietych zamowien',
                      message:
                          'Kiedy zamowienia zostana zakonczone, pojawia sie tutaj.',
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        return _ClosedOrderHistoryCard(
                          order: order,
                          onTap: () => onOrderTap(order),
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
    final color = isWarning
        ? const Color(0xFFF3A847)
        : const Color(0xFF8EE3DD);

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
            color:
                selected ? const Color(0xFFE98B38) : const Color(0x22FFFFFF),
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
    required this.messages,
    required this.onClose,
    this.onMarkInOven,
    this.onMarkOnTheWay,
    this.onComplete,
  });

  final AdminDashboardOrder order;
  final List<CheckoutChatMessage> messages;
  final VoidCallback onClose;
  final Future<void> Function()? onMarkInOven;
  final Future<void> Function()? onMarkOnTheWay;
  final Future<void> Function()? onComplete;

  @override
  Widget build(BuildContext context) {
    final notes = order.notes?.trim();
    final deltaSummary = _summarizeOrderAddonChanges(order);
    final stageLabel = _operatorStageLabel(order);
    final assignedOperatorEmail = order.assignedOperatorEmail?.trim();
    final canManageWorkflow = order.assignedToMe && order.isInProgress;
    final hasIntermediateWorkflow =
        onMarkInOven != null || onMarkOnTheWay != null;
    final hasWorkflowActions = canManageWorkflow &&
        (hasIntermediateWorkflow || onComplete != null);

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
                          ? 'Aktualny etap: $stageLabel. Te akcje od razu aktualizuja tracker klienta.'
                          : 'To zamowienie nie korzysta z etapow posrednich. Mozesz je tylko podjac i zakonczyc.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFD6C6BA),
                            height: 1.35,
                          ),
                    ),
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
                        if (onMarkOnTheWay != null)
                          OutlinedButton.icon(
                            onPressed: () => onMarkOnTheWay!.call(),
                            icon: const Icon(Icons.delivery_dining_outlined),
                            label: const Text('W drodze'),
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
                            label: const Text('Zakoncz'),
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
                            for (var index = 0; index < messages.length; index++) ...[
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
        _catalog = AdminCatalogData(
          positions: current.positions
              .map((item) =>
                  item.positionId == updated.positionId ? updated : item)
              .toList(growable: false),
          addons: current.addons,
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
        _catalog = AdminCatalogData(
          positions: current.positions,
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

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;

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
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                        'Repozytorium produktow',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFFF8EEE6),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Administrator moze tutaj wlaczac i wylaczac produkty oraz dodatki widoczne dla klienta.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
  });

  final AdminCatalogPosition position;
  final bool busy;
  final VoidCallback onToggle;

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
      onToggle: onToggle,
    );
  }
}

class _CatalogAddonTile extends StatelessWidget {
  const _CatalogAddonTile({
    required this.addon,
    required this.busy,
    required this.onToggle,
  });

  final AdminCatalogAddon addon;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return _CatalogEntryTile(
      title: addon.name,
      subtitle: addon.description ?? 'Dodatek bez dodatkowego opisu.',
      metaLabel:
          'Dodatek | PLN ${addon.price.toStringAsFixed(2)} | sort ${addon.sortOrder}',
      isActive: addon.isActive,
      busy: busy,
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
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final String metaLabel;
  final bool isActive;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        isActive ? const Color(0xFF79F5B8) : const Color(0xFFF29F60);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFFF7EEE6),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  metaLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: const Color(0xFFE7D0BB),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD4C4B8),
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              ),
              const SizedBox(height: 12),
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
                      activeColor: const Color(0xFF79F5B8),
                    ),
            ],
          ),
        ],
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

  if ({
        'on_the_way',
        'delivery_started',
        'awaiting_receipt_confirmation',
        'delivery_extended',
        'delivered_confirmed',
        'completed_by_admin',
      }.contains(verificationStage) ||
      lifecycleStatus == 'completed') {
    return 3;
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
        return 'Zakonczone';
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
      return 'W drodze';
    default:
      return '';
  }
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
  final seed = employee.userId == 0
      ? employee.email.hashCode
      : employee.userId;
  final hue = (seed.abs() * 37) % 360;
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.58, 0.46).toColor();
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/auth_session.dart';
import '../../data/models/checkout_verification.dart';
import '../../router/app_router.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({
    super.key,
    required this.checkout,
    required this.authSession,
  });

  final CheckoutVerificationResponse checkout;
  final AuthSession authSession;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with SingleTickerProviderStateMixin {
  static const _backgroundAsset =
      'assets/images/background_big_ingredients_darker.png';

  static const _stages = <String>[
    'Potwierdzone',
    'Przyjete do realizacji',
    'W piecu',
    'W drodze',
  ];

  late final AnimationController _controller;
  late final Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _progressAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubicEmphasized,
    ).drive(Tween<double>(begin: 0, end: 1 / (_stages.length - 1)));

    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.checkout;
    final request = order.receivedOrder;
    final itemCount = request.items.length;
    final leadItem = itemCount == 0 ? 'Brak pozycji' : request.items.first.name;

    return Scaffold(
      extendBody: true,
      body: _TrackingBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 120),
            children: [
              Row(
                children: [
                  Text(
                    'Trwajace zamowienie',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFF9EEE2),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  _TopPill(
                    icon: Icons.bolt_rounded,
                    label: 'LIVE',
                    color: const Color(0xFF3BC977),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF58B2A), Color(0xFFE25D1F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4DC95A1B),
                      blurRadius: 34,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Zamowienie #${order.savedOrderId}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFFFFF4EB),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x1FFFFFFF),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0x30FFFFFF)),
                          ),
                          child: Text(
                            order.paymentMethod,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: const Color(0xFFFFF6EF),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Platnosc zasymulowano jako zakonczona sukcesem. Zamowienie jest juz widoczne w module sledzenia i czeka na dalsze etapy z backendu.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFFCEBDE),
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _HeroStat(
                            icon: Icons.receipt_long_rounded,
                            title: '$itemCount ${itemCount == 1 ? 'pozycja' : 'pozycje'}',
                            subtitle: leadItem,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HeroStat(
                            icon: Icons.schedule_rounded,
                            title: '${request.etaMinutes} min',
                            subtitle: request.fulfillmentMethod,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xEF12100F),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x28FFFFFF)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Postep realizacji',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFF8EEE6),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Na razie to frontendowa symulacja jednego kroku procesu. Zielony pasek biegnie do drugiego etapu i aktywuje go po dotarciu.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD7C5B8),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, _) => _StageTimeline(
                        labels: _stages,
                        progress: _progressAnimation.value,
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, _) => Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1817),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0x1FFFFFFF)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              height: 46,
                              width: 46,
                              decoration: BoxDecoration(
                                color: const Color(0x163BC977),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.local_fire_department_rounded,
                                color: Color(0xFF3BC977),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _progressAnimation.value >= 0.32
                                        ? 'Kuchnia przejela zamowienie'
                                        : 'Uruchamiamy realizacje',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: const Color(0xFFF7EEE6),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _progressAnimation.value >= 0.32
                                        ? 'Drugi etap zostal aktywowany po dojsciu paska postepu.'
                                        : 'Animacja jest w drodze do drugiego etapu.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFFD3C3B7),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _InfoCard(
                      title: 'Dostawa',
                      content:
                          '${request.address.title}\n${request.address.subtitle}\n${request.address.etaLabel}',
                      icon: Icons.place_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InfoCard(
                      title: 'Backend',
                      content:
                          'verification_id\n${order.verificationId}\nstatus: ${order.status}',
                      icon: Icons.dns_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xEE100E0D),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x24FFFFFF)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pozycje w zamowieniu',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: const Color(0xFFF7EEE6),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final item in request.items.take(4)) ...[
                      _TrackingItemTile(item: item),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: FilledButton(
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.dashboard,
                (route) => false,
                arguments: widget.authSession.toRouteArgs(),
              );
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: const Color(0xFF2E8F57),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text(
              'Wroc do dashboardu',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingBackground extends StatelessWidget {
  const _TrackingBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(_OrderTrackingScreenState._backgroundAsset),
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
        child: Stack(
          children: [
            Positioned(
              top: -32,
              right: -14,
              child: _Glow(
                size: 170,
                color: const Color(0x30FF7A22),
              ),
            ),
            Positioned(
              top: 220,
              left: -36,
              child: _Glow(
                size: 128,
                color: const Color(0x263BC977),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _StageTimeline extends StatelessWidget {
  const _StageTimeline({
    required this.labels,
    required this.progress,
  });

  final List<String> labels;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final stepWidth = labels.length == 1 ? width : width / (labels.length - 1);
        final clampedProgress = progress.clamp(0.0, 1.0).toDouble();

        return SizedBox(
          height: 104,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 17,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2522),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 17,
                child: Container(
                  height: 8,
                  width: width * clampedProgress,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2BAF68), Color(0xFF4FDE86)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x663BC977),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              for (var index = 0; index < labels.length; index++)
                Positioned(
                  left: math
                      .max(0.0, math.min(width - 96, stepWidth * index - 48))
                      .toDouble(),
                  top: 0,
                  child: SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        _StageDot(
                          active: index == 0 ||
                              clampedProgress >=
                                  (labels.length == 1 ? 1 : index / (labels.length - 1)) - 0.003,
                          current: index == 1 && clampedProgress < (1 / (labels.length - 1)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          labels[index],
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: const Color(0xFFF2E5DA),
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({
    required this.active,
    required this.current,
  });

  final bool active;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: active ? 26 : 22,
      width: active ? 26 : 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? const Color(0xFF3BC977) : const Color(0xFF2D2926),
        border: Border.all(
          color: active ? const Color(0xFFD9FFE8) : const Color(0x44FFFFFF),
          width: active ? 3 : 1.4,
        ),
        boxShadow: active
            ? const [
                BoxShadow(
                  color: Color(0x663BC977),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: current
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Color(0xFFF3FFF8),
              ),
            )
          : null,
    );
  }
}

class _TrackingItemTile extends StatelessWidget {
  const _TrackingItemTile({required this.item});

  final CheckoutVerificationItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191615),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFEF802F), Color(0xFFB64C17)],
              ),
            ),
            child: const Icon(
              Icons.local_pizza_rounded,
              color: Color(0xFFFFF2E8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF7EEE6),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.description ?? 'Pozycja w aktywnym zamowieniu.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFD2C0B4),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item.price == null ? 'PLN --' : 'PLN ${_fmt(item.price!)}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFFF6D9C5),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.content,
    required this.icon,
  });

  final String title;
  final String content;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xEE11100F),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFFA858)),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFF8EEE5),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFD3C1B5),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x1EFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFFF2E7)),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFFFFF7F0),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFF9E3D4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopPill extends StatelessWidget {
  const _TopPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111010),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFF7EEE4),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
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
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}

String _fmt(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

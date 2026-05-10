import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/local/session_persistence.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/checkout_verification.dart';
import '../../data/repositories/checkout_repository.dart';
import '../../router/app_router.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({
    super.key,
    required this.checkout,
    required this.authSession,
    required this.checkoutRepository,
    this.isHistoryView = false,
  });

  final CheckoutVerificationResponse checkout;
  final AuthSession authSession;
  final CheckoutRepository checkoutRepository;
  final bool isHistoryView;

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with SingleTickerProviderStateMixin {
  static const _backgroundAsset =
      'assets/images/background_big_ingredients_darker.png';

  static const _deliveryStages = <String>[
    'Potwierdzone',
    'Przyjete do realizacji',
    'W piecu',
    'Gotowe do wysylki',
    'W dostawie',
  ];
  static const _deliveryStageImages = <String>[
    'assets/images/confirmed.png',
    'assets/images/orderReceived.png',
    'assets/images/inOven.png',
    'assets/images/paperBox.png',
    'assets/images/onTheWay.png',
  ];
  static const _pickupStages = <String>[
    'Potwierdzone',
    'Przyjete do realizacji',
    'W piecu',
    'Gotowe',
  ];
  static const _pickupStageImages = <String>[
    'assets/images/confirmed.png',
    'assets/images/orderReceived.png',
    'assets/images/inOven.png',
    'assets/images/paperBox.png',
  ];
  static const _deliveryStagesNoOven = <String>[
    'Potwierdzone',
    'Przyjete do realizacji',
    'Gotowe do wysylki',
    'W dostawie',
  ];
  static const _deliveryStageImagesNoOven = <String>[
    'assets/images/confirmed.png',
    'assets/images/orderReceived.png',
    'assets/images/paperBox.png',
    'assets/images/onTheWay.png',
  ];
  static const _pickupStagesNoOven = <String>[
    'Potwierdzone',
    'Przyjete do realizacji',
    'Gotowe',
  ];
  static const _pickupStageImagesNoOven = <String>[
    'assets/images/confirmed.png',
    'assets/images/orderReceived.png',
    'assets/images/paperBox.png',
  ];

  late final AnimationController _controller;
  late CheckoutVerificationResponse _currentCheckout;
  Timer? _refreshTimer;
  bool _isSubmittingReceiptConfirmation = false;

  @override
  void initState() {
    super.initState();
    _currentCheckout = widget.checkout;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _controller.value = _progressValueForCheckout(_currentCheckout);

    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshOrderData(),
    );
    _refreshOrderData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshCheckoutState() async {
    if (!widget.authSession.hasIdentity) {
      return;
    }

    try {
      final checkout = await widget.checkoutRepository.fetchActiveCheckout(
        sessionToken: widget.authSession.sessionToken,
        email: widget.authSession.email,
      );

      if (!mounted || checkout == null) {
        return;
      }

      setState(() {
        _currentCheckout = checkout;
      });
      _animateTimelineToCurrentStage();
    } catch (_) {
      // Keep the current local state if refresh fails.
    }
  }

  Future<void> _refreshOrderData() async {
    await _refreshCheckoutState();
  }

  Future<void> _confirmReceipt(bool received) async {
    if (_isSubmittingReceiptConfirmation) {
      return;
    }

    setState(() {
      _isSubmittingReceiptConfirmation = true;
    });

    try {
      final checkout = await widget.checkoutRepository.confirmReceipt(
        CheckoutReceiptConfirmationRequest(
          received: received,
          sessionToken: widget.authSession.sessionToken,
          userEmail: widget.authSession.email,
        ),
      );

      if (!mounted) {
        return;
      }

      if (received) {
        final routeArgs = <String, dynamic>{
          ...widget.authSession.toRouteArgs(),
        };
        await SessionPersistence.saveActiveCheckout(null);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(checkout.message)),
        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.dashboard,
          (route) => false,
          arguments: routeArgs,
        );
        return;
      }

      setState(() {
        _currentCheckout = checkout;
      });
      _animateTimelineToCurrentStage();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(checkout.message)),
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
          _isSubmittingReceiptConfirmation = false;
        });
      }
    }
  }

  void _animateTimelineToCurrentStage() {
    final target = _progressValueForCheckout(_currentCheckout);
    if ((_controller.value - target).abs() < 0.001) {
      _controller.value = target;
      return;
    }

    _controller.animateTo(
      target,
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  bool _isDeliveryCheckout(CheckoutVerificationResponse checkout) {
    final fulfillmentMethod =
        checkout.receivedOrder.fulfillmentMethod.trim().toLowerCase();
    return fulfillmentMethod == 'dostawa' || fulfillmentMethod == 'delivery';
  }

  bool _supportsOvenStageForCheckout(CheckoutVerificationResponse checkout) {
    if (checkout.receivedOrder.items.isEmpty) {
      return true;
    }

    return checkout.receivedOrder.items.any((item) {
      final signature =
          '${item.name.toLowerCase()} ${(item.description ?? '').toLowerCase()}';
      const noOvenKeywords = <String>[
        'mroz',
        'frozen',
        'odgrzan',
        'hermetycz',
        'lod',
        'ice cream',
        'gelato',
        'cola',
        'sprite',
        'fanta',
        'pepsi',
        'napoj',
        'woda',
        'sok',
        'kawa',
        'herbata',
      ];
      return !noOvenKeywords.any(signature.contains);
    });
  }

  List<String> _stageLabelsForCheckout(CheckoutVerificationResponse checkout) {
    final isDelivery = _isDeliveryCheckout(checkout);
    final supportsOven = _supportsOvenStageForCheckout(checkout);
    if (isDelivery) {
      return supportsOven ? _deliveryStages : _deliveryStagesNoOven;
    }
    return supportsOven ? _pickupStages : _pickupStagesNoOven;
  }

  List<String> _stageImagesForCheckout(CheckoutVerificationResponse checkout) {
    final isDelivery = _isDeliveryCheckout(checkout);
    final supportsOven = _supportsOvenStageForCheckout(checkout);
    if (isDelivery) {
      return supportsOven ? _deliveryStageImages : _deliveryStageImagesNoOven;
    }
    return supportsOven ? _pickupStageImages : _pickupStageImagesNoOven;
  }

  int _activeStageIndexForCheckout(CheckoutVerificationResponse checkout) {
    final processingStatus = checkout.processingStatus.trim().toLowerCase();
    final verificationStage = checkout.verificationStage.trim().toLowerCase();
    final lifecycleStatus = checkout.status.trim().toLowerCase();
    final isDelivery = _isDeliveryCheckout(checkout);
    final supportsOven = _supportsOvenStageForCheckout(checkout);

    if (supportsOven &&
        (verificationStage == 'in_oven' || verificationStage == 'oven')) {
      return 2;
    }

    if (verificationStage == 'ready_for_delivery') {
      if (isDelivery) {
        return supportsOven ? 3 : 2;
      }
      return supportsOven ? 2 : 2;
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
      if (isDelivery) {
        return supportsOven ? 4 : 3;
      }
      return supportsOven ? 3 : 2;
    }

    if (processingStatus == 'assigned') {
      return 1;
    }

    return 0;
  }

  double _progressValueForCheckout(CheckoutVerificationResponse checkout) {
    final labels = _stageLabelsForCheckout(checkout);
    if (labels.length <= 1) {
      return 1;
    }
    return _activeStageIndexForCheckout(checkout) / (labels.length - 1);
  }

  String _trackingHeadlineForCheckout(CheckoutVerificationResponse checkout) {
    final isDelivery = _isDeliveryCheckout(checkout);
    final supportsOven = _supportsOvenStageForCheckout(checkout);
    switch (_activeStageIndexForCheckout(checkout)) {
      case 0:
        return 'Zamowienie czeka na podjecie';
      case 1:
        return 'Kuchnia przejela zamowienie';
      case 2:
        if (supportsOven) {
          return 'Zamowienie jest w piecu';
        }
        return isDelivery
            ? 'Zamowienie jest gotowe do wysylki'
            : 'Zamowienie jest gotowe';
      case 3:
        return isDelivery
            ? 'Zamowienie jest w dostawie'
            : 'Zamowienie jest gotowe';
      case 4:
        return 'Zamowienie jest w dostawie';
      default:
        return 'Trwa realizacja zamowienia';
    }
  }

  String _trackingMessageForCheckout(CheckoutVerificationResponse checkout) {
    final isDelivery = _isDeliveryCheckout(checkout);
    final supportsOven = _supportsOvenStageForCheckout(checkout);
    switch (_activeStageIndexForCheckout(checkout)) {
      case 0:
        return 'Etap "Przyjete do realizacji" wlaczy sie dopiero po kliknieciu "Podejmij" przez administratora lub pracownika.';
      case 1:
        return 'Zamowienie zostalo podjete do realizacji przez obsluge.';
      case 2:
        if (supportsOven) {
          return 'Produkt jest aktualnie przygotowywany w piecu.';
        }
        return isDelivery
            ? 'Zamowienie jest spakowane i czeka na podjecie przez kierowce.'
            : 'Zamowienie jest gotowe do odbioru.';
      case 3:
        return isDelivery
            ? 'Zamowienie zostalo podjete przez kierowce i jest w drodze do klienta.'
            : 'Zamowienie jest gotowe do odbioru.';
      case 4:
        return 'Zamowienie zostalo podjete przez kierowce i jest w drodze do klienta.';
      default:
        return 'Status realizacji jest aktualizowany na podstawie backendu.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _currentCheckout;
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
                    widget.isHistoryView
                        ? 'Szczegoly zamowienia'
                        : 'Trwajace zamowienie',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFFF9EEE2),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  _TopPill(
                    icon: widget.isHistoryView
                        ? Icons.history_rounded
                        : Icons.bolt_rounded,
                    label: widget.isHistoryView ? 'ARCHIWUM' : 'LIVE',
                    color: widget.isHistoryView
                        ? const Color(0xFFE98B38)
                        : const Color(0xFF3BC977),
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
                            title:
                                '$itemCount ${itemCount == 1 ? 'pozycja' : 'pozycje'}',
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
                      'Status jest synchronizowany z backendem. Etap "Przyjete do realizacji" wlacza sie dopiero po kliknieciu "Podejmij" przez administratora lub pracownika.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFD7C5B8),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => _StageTimeline(
                        labels: _stageLabelsForCheckout(order),
                        imagePaths: _stageImagesForCheckout(order),
                        progress: _controller.value,
                        activeStageIndex: _activeStageIndexForCheckout(order),
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedBuilder(
                      animation: _controller,
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
                                    _trackingHeadlineForCheckout(order),
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: const Color(0xFFF7EEE6),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _trackingMessageForCheckout(order),
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
              if (order.requiresReceiptConfirmation) ...[
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xEE100E0D),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x34FFB061)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Otrzymales zamowienie?',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: const Color(0xFFF7EEE6),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        order.message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFD3C1B5),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (order.deliveryExtensionCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Liczba przedluzen oczekiwania: ${order.deliveryExtensionCount}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: const Color(0xFFFFD7B5),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _isSubmittingReceiptConfirmation
                                  ? null
                                  : () => _confirmReceipt(true),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: const Color(0xFF2E8F57),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Tak',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _isSubmittingReceiptConfirmation
                                  ? null
                                  : () => _confirmReceipt(false),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: const Color(0xFFFF8B00),
                                foregroundColor: const Color(0xFF2B1808),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isSubmittingReceiptConfirmation
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Color(0xFF2B1808),
                                      ),
                                    )
                                  : const Text(
                                      'Nie',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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
                    if (request.redeemedPoints > 0 ||
                        request.redeemedAmount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Wykorzystano ${request.redeemedPoints} pkt',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFFD3C1B5),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '-PLN ${_fmt(request.redeemedAmount)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: const Color(0xFFFFB66A),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
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
              final routeArgs = <String, dynamic>{
                ...widget.authSession.toRouteArgs(),
              };
              if (!widget.isHistoryView) {
                routeArgs['activeCheckout'] = _currentCheckout.toJson();
              }
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.dashboard,
                (route) => false,
                arguments: routeArgs,
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
    required this.imagePaths,
    required this.progress,
    required this.activeStageIndex,
  });

  final List<String> labels;
  final List<String> imagePaths;
  final double progress;
  final int activeStageIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
        final stageCount = labels.isEmpty ? 1 : labels.length;
        final columnWidth = width / stageCount;
        final startX = columnWidth / 2;
        final endX = width - (columnWidth / 2);
        final progressX = labels.length <= 1
            ? endX
            : startX + ((endX - startX) * clampedProgress);

        return SizedBox(
          height: 194,
          child: Stack(
            children: [
              Positioned(
                left: startX,
                right: width - endX,
                top: 104,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2522),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: startX,
                top: 104,
                child: Container(
                  height: 8,
                  width: math.max(0.0, progressX - startX),
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
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < labels.length; index++)
                      Expanded(
                        child: Column(
                          children: [
                            _StageIllustration(
                              imagePath: imagePaths.length > index
                                  ? imagePaths[index]
                                  : null,
                              active: index <= activeStageIndex,
                            ),
                            const SizedBox(height: 6),
                            _StageDot(
                              active: index <= activeStageIndex,
                              current: false,
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                labels[index],
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFFF2E5DA),
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
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

class _StageIllustration extends StatelessWidget {
  const _StageIllustration({
    required this.imagePath,
    required this.active,
  });

  final String? imagePath;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final content = imagePath == null
        ? const SizedBox.shrink()
        : kIsWeb
            ? Image.network(
                _webStageImagePath(imagePath!),
                height: 82,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) {
                  return _stageFallbackIcon();
                },
              )
            : Image.asset(
                imagePath!,
                height: 82,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (context, error, stackTrace) {
                  return _stageFallbackIcon();
                },
              );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: active ? 1 : 0.42,
      child: SizedBox(
        height: 82,
        child: Center(child: content),
      ),
    );
  }

  Widget _stageFallbackIcon() {
    return Icon(
      Icons.local_shipping_outlined,
      size: 34,
      color: active ? const Color(0xFFF5EFE8) : const Color(0x88F5EFE8),
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
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

String _fmt(double value) {
  return value.toStringAsFixed(2);
}

String _webStageImagePath(String imagePath) {
  final normalized = imagePath.replaceAll('\\', '/');
  const marker = 'assets/images/';
  final markerIndex = normalized.lastIndexOf(marker);
  if (markerIndex >= 0) {
    return normalized.substring(markerIndex);
  }
  return normalized;
}

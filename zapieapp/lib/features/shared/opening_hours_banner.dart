import 'package:flutter/material.dart';

import '../../data/models/opening_hours.dart';

class OpeningHoursBanner extends StatelessWidget {
  const OpeningHoursBanner({
    super.key,
    required this.hours,
  });

  final OpeningHoursData hours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor =
        hours.isOpenNow ? const Color(0xFF62D48F) : const Color(0xFFF0AA6B);
    final statusBackground =
        hours.isOpenNow ? const Color(0x1E62D48F) : const Color(0x1EF0AA6B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x24FFFFFF)),
        gradient: const LinearGradient(
          colors: [Color(0xF11A1715), Color(0xEB13100F), Color(0xE1141110)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Color(0x14FF7A1A),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFFE98A42), Color(0xFFCC5F1A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              size: 20,
              color: Color(0xFFFFF5EE),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Godziny otwarcia',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFD8C6B9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hours.primaryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFFFF4EC),
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: statusBackground,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
            ),
            child: Text(
              hours.statusLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

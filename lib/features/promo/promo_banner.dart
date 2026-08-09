// lib/features/promo/promo_banner.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design_system/components/ad_banner.dart';
import '../../design_system/tokens/radius.dart';
import '../../design_system/tokens/spacing.dart';
import '../../design_system/tokens/typography.dart';
import '../../services/analytics_service.dart';
import '../../services/backend_service.dart';

/// An admin-managed banner. Admins create these from the dashboard (catalog →
/// Banners); each has a [slot], and each slot shows its highest-priority active
/// banner. [kind] lets an admin pick, per slot: a clickable house [promo], the
/// AdMob ad, or [none] (hidden).
@immutable
class PromoBanner {
  final String id;
  final String slot;
  final String kind; // 'promo' | 'admob' | 'none'
  final String title;
  final String subtitle;
  final String imageUrl;
  final String ctaLabel;
  final String linkType; // 'internal' | 'external'
  final String linkTarget;
  final String bgColor; // hex, optional
  final bool active;
  final int sortOrder;

  const PromoBanner({
    required this.id,
    required this.slot,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.ctaLabel,
    required this.linkType,
    required this.linkTarget,
    required this.bgColor,
    required this.active,
    required this.sortOrder,
  });

  factory PromoBanner.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] as String?)?.trim() ?? '';
    return PromoBanner(
      id: s('id'),
      slot: s('slot'),
      kind: s('kind').isEmpty ? 'promo' : s('kind'),
      title: s('title'),
      subtitle: s('subtitle'),
      imageUrl: s('imageUrl'),
      ctaLabel: s('ctaLabel'),
      linkType: s('linkType').isEmpty ? 'internal' : s('linkType'),
      linkTarget: s('linkTarget'),
      bgColor: s('bgColor'),
      active: j['active'] as bool? ?? true,
      sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Color? get parsedBgColor {
    var hex = bgColor.replaceAll('#', '').trim();
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(v);
  }
}

/// Loads all active banners once, sorted by priority. Slots filter this.
final _bannersProvider = FutureProvider<List<PromoBanner>>((ref) async {
  final data = await BackendService().getCatalog('banners');
  final raw = (data['items'] as List?) ?? const [];
  final list = raw
      .whereType<Map>()
      .map((e) => PromoBanner.fromJson(Map<String, dynamic>.from(e)))
      .where((b) => b.active)
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return list;
});

/// The highest-priority active banner for [slot], or null if none configured.
final slotBannerProvider =
    Provider.family<PromoBanner?, String>((ref, slot) {
  final list = ref.watch(_bannersProvider).valueOrNull ?? const [];
  for (final b in list) {
    if (b.slot == slot) return b;
  }
  return null;
});

/// Drop-in banner for a named slot. Renders whatever the admin configured:
///   • no config for the slot → the AdMob ad (default: keep monetizing)
///   • kind 'none'            → nothing
///   • kind 'admob'           → the AdMob ad
///   • kind 'promo'           → a clickable house banner
class SlotBanner extends ConsumerWidget {
  const SlotBanner({required this.slot, super.key});

  final String slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banner = ref.watch(slotBannerProvider(slot));

    // Default when nothing is configured: show the ad, so slots monetize until
    // an admin deliberately overrides them.
    if (banner == null || banner.kind == 'admob') {
      return const MetroSafarAdBanner();
    }
    if (banner.kind == 'none') return const SizedBox.shrink();
    return _PromoCard(banner: banner);
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.banner});

  final PromoBanner banner;

  Future<void> _onTap(BuildContext context) async {
    // Fire-and-forget analytics; never block navigation on it.
    unawaited(AnalyticsService.logEvent('promo_banner_click', parameters: {
      'slot': banner.slot,
      'id': banner.id,
    }));

    final target = banner.linkTarget.trim();
    if (target.isEmpty) return;

    if (banner.linkType == 'external') {
      final uri = Uri.tryParse(target);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          if (kDebugMode) debugPrint('PromoBanner.launch failed: $e');
        }
      }
      return;
    }

    // Internal: only follow in-app absolute paths.
    if (target.startsWith('/') && context.mounted) {
      context.push(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = banner.parsedBgColor ?? cs.primaryContainer;

    // Image banner takes the whole slot; otherwise a text/gradient card.
    final Widget content = banner.imageUrl.isNotEmpty
        ? ClipRRect(
            borderRadius: AppRadius.borderRadiusL,
            child: AspectRatio(
              aspectRatio: 320 / 100,
              child: Image.network(
                banner.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _TextCard(banner: banner, bg: bg),
                loadingBuilder: (ctx, child, progress) =>
                    progress == null ? child : _TextCard(banner: banner, bg: bg),
              ),
            ),
          )
        : _TextCard(banner: banner, bg: bg);

    return Semantics(
      button: true,
      label: banner.title.isNotEmpty ? banner.title : 'Promotion',
      child: InkWell(
        onTap: () => _onTap(context),
        borderRadius: AppRadius.borderRadiusL,
        child: content,
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({required this.banner, required this.bg});

  final PromoBanner banner;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    // Pick a readable foreground for the chosen background.
    final onBg =
        ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : Colors.black87;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (banner.title.isNotEmpty)
                  Text(
                    banner.title,
                    style: AppTypography.titleMedium
                        .copyWith(color: onBg, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (banner.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    banner.subtitle,
                    style: AppTypography.bodySmall
                        .copyWith(color: onBg.withValues(alpha: 0.9)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (banner.ctaLabel.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.s3),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3, vertical: 6),
              decoration: BoxDecoration(
                color: onBg.withValues(alpha: 0.15),
                borderRadius: AppRadius.borderRadiusFull,
              ),
              child: Text(
                banner.ctaLabel,
                style: AppTypography.labelLarge
                    .copyWith(color: onBg, fontWeight: FontWeight.w700),
              ),
            ),
          ] else
            Icon(Icons.chevron_right_rounded, color: onBg),
        ],
      ),
    );
  }
}

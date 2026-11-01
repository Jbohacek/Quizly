import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'wishlist.dart';

/// Obchod (design screens 7–8): balance, "Šetříš na", Odměny / Moje nákupy, purchase sheet.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  bool _claimsTab = false;

  Future<void> _refresh() {
    ref.invalidate(claimsProvider);
    return ref.refresh(shopProvider.future);
  }

  Future<void> _toggle(ShopItem item) async {
    try {
      await ref.read(shopProvider.notifier).toggleWishlist(item);
    } on ApiException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(S.wishFailed)));
    }
  }

  Future<void> _open(Shop shop, ShopItem item) async {
    final bought = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB806060A),
      builder: (context) => _ConfirmSheet(item: item, balance: shop.balance),
    );
    if (bought == true && mounted) {
      setState(() => _claimsTab = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.bought(item.name))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(shopProvider);
    final claims = ref.watch(claimsProvider);
    return SafeArea(
      bottom: false,
      child: switch (shop) {
        AsyncValue(:final value?) => RefreshIndicator(
            color: Q.primary,
            backgroundColor: Q.surface,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                ScreenHeader(title: S.navShop, trailing: PointsPill(balance: value.balance)),
                const SizedBox(height: 16),
                _SavingCard(shop: value),
                const SizedBox(height: 16),
                _Tabs(
                  claimsTab: _claimsTab,
                  claimsCount: claims.value?.length ?? 0,
                  onChanged: (claimsTab) => setState(() => _claimsTab = claimsTab),
                ),
                const SizedBox(height: 16),
                if (_claimsTab)
                  _Claims(claims: claims, onRetry: () => ref.invalidate(claimsProvider))
                else
                  _Items(shop: value, onOpen: (item) => _open(value, item), onHeart: _toggle),
              ],
            ),
          ),
        AsyncValue(:final error?) => ErrorView(
            message: error is ApiException ? error.message : S.loadFailed,
            onRetry: () => ref.invalidate(shopProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _SavingCard extends StatelessWidget {
  const _SavingCard({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final target = wishlistTarget(shop.items);
    if (target == null) {
      return Panel(
        radius: 22,
        child: Row(
          children: [
            const Icon(Icons.favorite_border_rounded, color: Q.points),
            const SizedBox(width: 12),
            Expanded(
              child: Text(S.savingEmpty, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
            ),
          ],
        ),
      );
    }
    final item = target.item;
    return WishlistCard(
      label: S.savingFor,
      name: item.name,
      balance: shop.balance,
      price: item.price,
      text: target.reached ? S.savingReady : S.savingMissing(item.missing),
    );
  }
}

/// The yellow wishlist progress card (Obchod and Hotovo).
class WishlistCard extends StatelessWidget {
  const WishlistCard({
    super.key,
    required this.label,
    required this.name,
    required this.balance,
    required this.price,
    required this.text,
    this.onTap,
  });

  final String label;
  final String name;
  final int balance;
  final int price;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final progress = price == 0 ? 1.0 : (balance / price).clamp(0.0, 1.0);
    return Material(
      color: Q.points.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Q.points.withValues(alpha: 0.45), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.favorite_rounded, color: Q.points, size: 16),
                  const SizedBox(width: 8),
                  Text(label, style: QText.body(13, color: Q.points, weight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text(name, style: QText.heading(21), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text(
                    S.savingProgress(balance.clamp(0, price), price),
                    style: QText.body(13, color: Q.textMuted, weight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: motion(context, const Duration(milliseconds: 900)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) =>
                      LinearProgressIndicator(value: value, minHeight: 10, backgroundColor: Q.border, color: Q.points),
                ),
              ),
              const SizedBox(height: 10),
              Text(text, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w600, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.claimsTab, required this.claimsCount, required this.onChanged});

  final bool claimsTab;
  final int claimsCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool selected, bool value) => Expanded(
          child: Semantics(
            selected: selected,
            button: true,
            child: Material(
              color: selected ? Q.text : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onChanged(value),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      label,
                      style: QText.body(
                        15,
                        color: selected ? Q.cardText : Q.textMuted,
                        weight: selected ? FontWeight.w800 : FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Q.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          tab(S.tabRewards, !claimsTab, false),
          const SizedBox(width: 4),
          tab(S.tabClaims(claimsCount), claimsTab, true),
        ],
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.shop, required this.onOpen, required this.onHeart});

  final Shop shop;
  final ValueChanged<ShopItem> onOpen;
  final ValueChanged<ShopItem> onHeart;

  @override
  Widget build(BuildContext context) {
    final items = shop.items;
    if (items.isEmpty) {
      return Panel(
        radius: 18,
        child: Text(S.noItems, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5)),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < items.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ItemCard(item: items[i], onOpen: onOpen, onHeart: onHeart)),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < items.length
                      ? _ItemCard(item: items[i + 1], onOpen: onOpen, onHeart: onHeart)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// "Vyprodáno" / "Poslední kus" / "Zbývá N ks" and its color.
(String, Color) stockLine(ShopItem item) => item.soldOut
    ? (S.soldOut, Q.dontKnow)
    : item.stock == 1
        ? (S.lastPiece, Q.primary)
        : (S.stockLeft(item.stock), Q.textMuted);

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onOpen, required this.onHeart});

  final ShopItem item;
  final ValueChanged<ShopItem> onOpen;
  final ValueChanged<ShopItem> onHeart;

  @override
  Widget build(BuildContext context) {
    final (stock, stockColor) = stockLine(item);
    return Opacity(
      opacity: item.soldOut ? 0.55 : 1,
      child: Material(
        color: Q.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: item.wishlisted ? Q.points.withValues(alpha: 0.45) : Q.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onOpen(item),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 30),
                      child: Text(item.name, style: QText.heading(16).copyWith(height: 1.25)),
                    ),
                    const SizedBox(height: 6),
                    Text(stock, style: QText.body(12, color: stockColor, weight: FontWeight.w700)),
                    const Spacer(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Q.points, size: 17),
                        const SizedBox(width: 3),
                        Text(formatInt(item.price), style: QText.body(16, color: Q.points, weight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // A full-width row: "Chybí 1 436" doesn't fit next to the price on a phone.
                    SizedBox(
                      width: double.infinity,
                      child: item.canBuy
                          ? SizedBox(
                              height: 44,
                              child: FilledButton(
                                onPressed: () => onOpen(item),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Q.primary,
                                  foregroundColor: Q.onPrimary,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  textStyle: QText.body(14, weight: FontWeight.w800),
                                ),
                                child: const Text(S.buy),
                              ),
                            )
                          : Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Q.surface2, borderRadius: BorderRadius.circular(14)),
                              child: Text(
                                item.soldOut ? S.soldOut : S.missingShort(item.missing),
                                style: QText.body(12, color: Q.textMuted, weight: FontWeight.w700),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  tooltip: item.wishlisted ? S.wishRemove : S.wishAdd,
                  isSelected: item.wishlisted,
                  onPressed: () => onHeart(item),
                  color: item.wishlisted ? Q.points : Q.heart,
                  constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                  icon: Icon(item.wishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmSheet extends ConsumerStatefulWidget {
  const _ConfirmSheet({required this.item, required this.balance});

  final ShopItem item;
  final int balance;

  @override
  ConsumerState<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends ConsumerState<_ConfirmSheet> {
  // One id per sheet: a retry after a network error can't buy twice (api.md §8).
  final _requestId = const Uuid().v4();
  bool _busy = false;
  String? _error;

  Future<void> _buy() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(shopProvider.notifier).buy(widget.item, _requestId);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final (stock, stockColor) = stockLine(item);
    final after = widget.balance - item.price;
    return Container(
      decoration: const BoxDecoration(
        color: Q.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Q.inputBorder)),
      ),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 28 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: Q.legendNew, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 18),
          Text(stock, style: QText.body(13, color: stockColor, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          Semantics(header: true, child: Text(S.confirmTitle(item.name), style: QText.heading(28).copyWith(height: 1.15))),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(item.description, style: QText.body(15, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Q.surface2, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                _SheetRow(S.price, points(item.price), color: Q.points, strong: true),
                const SizedBox(height: 10),
                _SheetRow(S.yourBalance, points(widget.balance)),
                const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Q.inputBorder)),
                _SheetRow(S.afterPurchase, points(after), strong: true, labelStrong: true),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Q.inputBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user_outlined, color: Q.multiplier, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: S.confirmInfoStart),
                        TextSpan(text: S.confirmInfoStrong, style: QText.body(14, color: Q.text, weight: FontWeight.w800)),
                        const TextSpan(text: S.confirmInfoEnd),
                      ],
                    ),
                    style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null || !item.canBuy) ...[
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              child: Text(
                _error ?? (item.soldOut ? S.soldOut : S.cannotBuyYet(item.missing)),
                style: QText.body(14, color: Q.dontKnow, weight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(flex: 10, child: SecondaryButton(label: S.cancel, onPressed: () => Navigator.pop(context, false))),
              const SizedBox(width: 10),
              Expanded(
                flex: 16,
                child: PrimaryButton(
                  label: S.buyFor(item.price),
                  busy: _busy,
                  onPressed: item.canBuy ? _buy : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow(this.label, this.value, {this.color = Q.text, this.strong = false, this.labelStrong = false});

  final String label;
  final String value;
  final Color color;
  final bool strong;
  final bool labelStrong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: labelStrong
                ? QText.body(15, weight: FontWeight.w800)
                : QText.body(15, color: Q.textMuted, weight: FontWeight.w600),
          ),
        ),
        Text(value, style: QText.body(15, color: color, weight: strong ? FontWeight.w800 : FontWeight.w700)),
      ],
    );
  }
}

class _Claims extends StatelessWidget {
  const _Claims({required this.claims, required this.onRetry});

  final AsyncValue<List<Claim>> claims;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (claims) {
      AsyncValue(:final value?) when value.isEmpty => Panel(
          radius: 18,
          child: Text(S.claimsEmpty, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5)),
        ),
      AsyncValue(:final value?) => Column(
          children: [
            for (final claim in value) ...[
              _ClaimTile(claim: claim, now: DateTime.now()),
              const SizedBox(height: 8),
            ],
          ],
        ),
      AsyncValue(:final error?) => Panel(
          radius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                error is ApiException ? error.message : S.loadFailed,
                style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5),
              ),
              const SizedBox(height: 12),
              SecondaryButton(label: S.retry, onPressed: onRetry),
            ],
          ),
        ),
      _ => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
    };
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({required this.claim, required this.now});

  final Claim claim;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (claim.status) {
      ClaimStatus.pending => (S.claimPending, Q.points),
      ClaimStatus.confirmed => (S.claimConfirmed, Q.primary),
      ClaimStatus.rejected => (S.claimRejected, Q.dontKnow),
    };
    final when = formatWhen(claim.status == ClaimStatus.pending ? claim.createdAt : claim.decidedAt ?? claim.createdAt, now);
    final amount = claim.status == ClaimStatus.rejected ? S.claimRefunded(claim.price) : points(claim.price);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Q.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Q.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(claim.itemName, style: QText.body(15, weight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('$amount · $when', style: QText.body(12, color: Q.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tag(label: label, color: color),
        ],
      ),
    );
  }
}

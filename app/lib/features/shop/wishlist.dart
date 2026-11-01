import '../../core/api/models.dart';

/// The wishlist item shown in "Šetříš na" and on Hotovo.
///
/// The nearest item not yet affordable (fewest points missing); when every hearted
/// item is affordable, the cheapest of them ([reached] is then true). Sold-out items
/// are left out. Null when nothing is hearted.
({ShopItem item, bool reached})? wishlistTarget(Iterable<ShopItem> items) {
  final hearted = items.where((i) => i.wishlisted && !i.soldOut).toList();
  final saving = hearted.where((i) => i.missing > 0).toList()..sort((a, b) => a.missing.compareTo(b.missing));
  if (saving.isNotEmpty) return (item: saving.first, reached: false);
  final ready = hearted.toList()..sort((a, b) => a.price.compareTo(b.price));
  return ready.isEmpty ? null : (item: ready.first, reached: true);
}

/// How many Vím answers worth [knowPoints] cover [missing] points.
int knowAnswersFor(int missing, int knowPoints) =>
    missing <= 0 ? 0 : (missing / (knowPoints <= 0 ? 10 : knowPoints)).ceil();

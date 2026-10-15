class WishFoodPackage {
  const WishFoodPackage({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
  });

  final String id;
  final String name;
  final double price;
  final int quantity;

  factory WishFoodPackage.fromJson(Map<String, dynamic> json) {
    return WishFoodPackage(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '鱼食包',
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0,
      quantity: int.tryParse(json['quantity']?.toString() ?? '') ?? 0,
    );
  }
}

class WishFeedState {
  const WishFeedState({
    required this.walletBalance,
    required this.foodBalance,
    required this.totalPurchased,
    required this.totalFed,
    required this.packages,
    this.feedQuantities = const <int>[1],
    this.maxFeedQuantity = 1,
  });

  final double walletBalance;
  final int foodBalance;
  final int totalPurchased;
  final int totalFed;
  final List<WishFoodPackage> packages;
  final List<int> feedQuantities;
  final int maxFeedQuantity;

  factory WishFeedState.fromJson(Map<String, dynamic> json) {
    final rawPackages = json['packages'];
    final parsedMax = int.tryParse(
          json['maxFeedQuantity']?.toString() ?? '',
        ) ??
        1;
    final rawQuantities = json['feedQuantities'];
    final quantities = rawQuantities is List
        ? rawQuantities
            .map((item) => int.tryParse(item.toString()))
            .whereType<int>()
            .where((item) => item > 0 && item <= parsedMax)
            .toSet()
            .toList()
        : <int>[1];
    quantities.sort();
    return WishFeedState(
      walletBalance:
          double.tryParse(json['walletBalance']?.toString() ?? '') ?? 0,
      foodBalance: int.tryParse(json['foodBalance']?.toString() ?? '') ?? 0,
      totalPurchased:
          int.tryParse(json['totalPurchased']?.toString() ?? '') ?? 0,
      totalFed: int.tryParse(json['totalFed']?.toString() ?? '') ?? 0,
      packages: rawPackages is List
          ? rawPackages
              .whereType<Map>()
              .map(
                (item) => WishFoodPackage.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .where((item) => item.id.isNotEmpty && item.quantity > 0)
              .toList(growable: false)
          : const <WishFoodPackage>[],
      feedQuantities: quantities.isEmpty ? const <int>[1] : quantities,
      maxFeedQuantity: parsedMax < 1 ? 1 : parsedMax,
    );
  }

  WishFeedState mergeBalance(Map<String, dynamic> json) {
    return WishFeedState(
      walletBalance: double.tryParse(
            json['walletBalance']?.toString() ?? '',
          ) ??
          walletBalance,
      foodBalance:
          int.tryParse(json['foodBalance']?.toString() ?? '') ?? foodBalance,
      totalPurchased: int.tryParse(json['totalPurchased']?.toString() ?? '') ??
          totalPurchased,
      totalFed: int.tryParse(json['totalFed']?.toString() ?? '') ?? totalFed,
      packages: packages,
      feedQuantities: feedQuantities,
      maxFeedQuantity: maxFeedQuantity,
    );
  }

  List<int> availableFeedQuantities() {
    return feedQuantities
        .where((item) => item <= foodBalance && item <= maxFeedQuantity)
        .toList(growable: false);
  }
}

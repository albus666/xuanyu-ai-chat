import 'package:flutter/material.dart';

import '../../core/cache/page_snapshot_cache.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_session_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_toast.dart';
import 'goodwill_echo_page.dart';
import 'shop_address_page.dart';
import 'shop_after_sale_page.dart';
import 'shop_checkout_page.dart';
import 'shop_common.dart';
import 'shop_orders_page.dart';
import 'shop_product_detail_page.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  int _index = 0;
  int _cartVersion = 0;
  final _visitedTabs = <int>{0};

  void _selectTab(int value) {
    setState(() {
      _visitedTabs.add(value);
      if (value == 2 && _index != 2) _cartVersion++;
      _index = value;
    });
  }

  int? _categoryId;

  void _openProduct(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShopProductDetailPage(productId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ShopHomeTab(
        onProduct: _openProduct,
        onCategory: (id) => setState(() {
          _categoryId = id;
          _visitedTabs.add(1);
          _index = 1;
        }),
        onCart: () => _selectTab(2),
      ),
      ShopCategoryTab(onProduct: _openProduct, selectedCategoryId: _categoryId),
      ShopCartTab(key: ValueKey(_cartVersion)),
      const ShopMineTab(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: Text(['玄遇好物', '商品分类', '购物车', '商城我的'][_index]),
        actions: _index == 0
            ? [
                IconButton(
                  onPressed: () => _selectTab(2),
                  icon: const Icon(Icons.shopping_bag_outlined),
                ),
              ]
            : null,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < pages.length; i++)
            _visitedTabs.contains(i) ? pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '分类',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart_rounded),
            label: '购物车',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class ShopHomeTab extends StatefulWidget {
  const ShopHomeTab(
      {super.key,
      required this.onProduct,
      required this.onCategory,
      required this.onCart});
  final ValueChanged<int> onProduct;
  final ValueChanged<int> onCategory;
  final VoidCallback onCart;

  @override
  State<ShopHomeTab> createState() => _ShopHomeTabState();
}

class _ShopHomeTabState extends State<ShopHomeTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _loadSerial++;
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {
      _data = null;
      _loading = true;
    });
    _load();
  }

  Future<void> _load() async {
    final serial = ++_loadSerial;
    final scope = ApiSessionScope();
    final cache = PageSnapshotCache('shop_home', persist: true);
    bool current() => mounted && scope.current && serial == _loadSerial;
    if (_data == null) {
      final snapshot = await cache.read();
      if (!current()) return;
      if (snapshot != null) {
        setState(() {
          _data = snapshot;
          _loading = false;
        });
      }
    }
    try {
      final data = shopData(await scope.get('/api/shop/home'));
      if (data == null) throw const FormatException('商城返回异常');
      if (current()) {
        setState(() {
          _data = data;
          _loading = false;
        });
        await cache.write(data);
      }
    } catch (error) {
      if (mounted && current()) showAppToast(context, shopError(error, '商城加载失败'));
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final banners = _data?['banners'] as List? ?? [];
    final categories = _data?['categories'] as List? ?? [];
    final products = _data?['products'] as List? ?? [];
    final goodwill = _data?['goodwill'] is Map
        ? Map<String, dynamic>.from(_data!['goodwill'] as Map)
        : null;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          SizedBox(
            height: 154,
            child: banners.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF5CBCAF), Color(0xFF94D5C8)]),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('玄遇自营好物',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800)),
                          SizedBox(height: 8),
                          Text('东方生活 · 身心安顿 · 正品自营',
                              style: TextStyle(color: Colors.white70)),
                        ]),
                  )
                : PageView.builder(
                    itemCount: banners.length,
                    itemBuilder: (_, index) {
                      final banner =
                          Map<String, dynamic>.from(banners[index] as Map);
                      return GestureDetector(
                        onTap: banner['productId'] is num
                            ? () => widget
                                .onProduct((banner['productId'] as num).toInt())
                            : null,
                        child: Stack(fit: StackFit.expand, children: [
                          ShopNetworkImage(banner['imageUrl']?.toString(),
                              borderRadius: 20),
                          Positioned(
                              left: 18,
                              bottom: 15,
                              right: 18,
                              child: Text(banner['title']?.toString() ?? '',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      shadows: [
                                        Shadow(
                                            blurRadius: 6,
                                            color: Colors.black45)
                                      ]))),
                        ]),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 20),
          if (categories.isNotEmpty)
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 18),
                itemBuilder: (_, index) {
                  final item =
                      Map<String, dynamic>.from(categories[index] as Map);
                  return GestureDetector(
                    onTap: () => widget.onCategory((item['id'] as num).toInt()),
                    child: SizedBox(
                        width: 58,
                        child: Column(children: [
                          SizedBox(
                              width: 52,
                              height: 52,
                              child: ShopNetworkImage(
                                  item['iconUrl']?.toString(),
                                  borderRadius: 18)),
                          const SizedBox(height: 6),
                          Text(item['name']?.toString() ?? '',
                              maxLines: 1,
                              style: const TextStyle(fontSize: 12)),
                        ])),
                  );
                },
              ),
            ),
          if (goodwill != null) ...[
            const SizedBox(height: 18),
            Material(
              color: const Color(0xFFFFF6EC),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const GoodwillEchoPage())),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(children: [
                    CircleAvatar(
                        radius: 27,
                        backgroundColor: Color(0xFFFFE7D4),
                        child: Icon(Icons.volunteer_activism_rounded,
                            color: Color(0xFFC2683B))),
                    SizedBox(width: 13),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('善意回声',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF6F4D35))),
                        ])),
                    Icon(Icons.chevron_right, color: Color(0xFFC49A7A)),
                  ]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text('为你推荐',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (products.isEmpty)
            Container(
                padding: const EdgeInsets.all(34),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: const Text('暂无可选商品，稍后再来看看',
                    style: TextStyle(color: AppColors.textHint)))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: products.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: .68),
              itemBuilder: (_, index) {
                final product =
                    Map<String, dynamic>.from(products[index] as Map);
                return ShopProductCard(
                    product: product,
                    onTap: () =>
                        widget.onProduct((product['id'] as num).toInt()));
              },
            ),
        ],
      ),
    );
  }
}

class ShopCategoryTab extends StatefulWidget {
  const ShopCategoryTab(
      {super.key, required this.onProduct, this.selectedCategoryId});
  final ValueChanged<int> onProduct;
  final int? selectedCategoryId;
  @override
  State<ShopCategoryTab> createState() => _ShopCategoryTabState();
}

class _ShopCategoryTabState extends State<ShopCategoryTab> {
  final List<Map<String, dynamic>> _categories = [];
  final List<Map<String, dynamic>> _products = [];
  int? _selected;
  int? _displayedCategory;
  bool _loading = true;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedCategoryId;
    apiSessionChanges.addListener(_accountChanged);
    _loadCategories();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _loadSerial++;
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    _loadSerial++;
    setState(() {
      _categories.clear();
      _products.clear();
      _displayedCategory = null;
      _loading = true;
    });
    _loadCategories();
  }

  @override
  void didUpdateWidget(covariant ShopCategoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCategoryId != null &&
        widget.selectedCategoryId != _selected) {
      _selected = widget.selectedCategoryId;
      _loadProducts();
    }
  }

  void _applyCategories(Map<String, dynamic> data, {bool live = false}) {
    final list = data['list'] as List? ?? [];
    _categories
      ..clear()
      ..addAll(list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    if (live && !_categories.any((item) => item['id'] == _selected)) {
      _selected = _categories.isEmpty
          ? null
          : (_categories.first['id'] as num).toInt();
      _loadSerial++;
      _products.clear();
      _displayedCategory = null;
      _loading = _selected != null;
    } else if (_categories.isNotEmpty) {
      _selected ??= (_categories.first['id'] as num).toInt();
    }
  }

  Future<void> _loadCategories() async {
    final scope = ApiSessionScope();
    final cache = PageSnapshotCache('shop_categories', persist: true);
    final snapshot = await cache.read();
    if (!mounted || !scope.current) return;
    // Cached categories can start the visible product request immediately.
    if (snapshot != null) {
      setState(() => _applyCategories(snapshot));
      _loadProducts();
    }
    try {
      final data = shopData(await scope.get('/api/shop/categories'));
      if (data == null) throw const FormatException('分类返回异常');
      if (!mounted || !scope.current) return;
      final previousCategory = _selected;
      setState(() => _applyCategories(data, live: true));
      // Start the visible products before waiting for optional disk storage.
      final productLoad = snapshot == null || previousCategory != _selected
          ? _loadProducts()
          : Future<void>.value();
      await cache.write(data);
      await productLoad;
    } catch (error) {
      if (mounted && scope.current) {
        showAppToast(context, shopError(error, '分类加载失败'));
        if (snapshot == null) setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadProducts() async {
    final category = _selected;
    final serial = ++_loadSerial;
    final scope = ApiSessionScope();
    bool current() => mounted && scope.current && serial == _loadSerial;
    if (category == null) {
      if (mounted) {
        setState(() {
          _products.clear();
          _displayedCategory = null;
          _loading = false;
        });
      }
      return;
    }
    final cache = PageSnapshotCache(
      'shop_products',
      parameters: {'category': category},
      persist: true,
    );
    setState(() {
      if (_displayedCategory != category) _products.clear();
      _loading = _products.isEmpty;
    });
    final snapshot = await cache.read();
    if (!current()) return;
    if (snapshot != null) {
      setState(() {
        _setProducts(snapshot);
        _displayedCategory = category;
        _loading = false;
      });
    }
    try {
      final data = shopData(
        await scope.get(
          '/api/shop/products',
          queryParameters: {'category_id': category, 'page_size': 50},
        ),
      );
      if (data == null) throw const FormatException('商品返回异常');
      if (current()) {
        setState(() {
          _setProducts(data);
          _displayedCategory = category;
          _loading = false;
        });
        await cache.write(data);
      }
    } catch (error) {
      if (mounted && current()) showAppToast(context, shopError(error, '商品加载失败'));
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  void _setProducts(Map<String, dynamic> data) {
    _products
      ..clear()
      ..addAll(
        (data['list'] as List? ?? []).whereType<Map>().map(
              (e) => Map<String, dynamic>.from(e),
            ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_categories.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Row(children: [
      SizedBox(
        width: 92,
        child: ListView.builder(
          itemCount: _categories.length,
          itemBuilder: (_, index) {
            final item = _categories[index];
            final id = (item['id'] as num).toInt();
            final active = id == _selected;
            return InkWell(
              onTap: () {
                setState(() => _selected = id);
                _loadProducts();
              },
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.transparent,
                    border: Border(
                        left: BorderSide(
                            color:
                                active ? AppColors.primary : Colors.transparent,
                            width: 3))),
                child: Text(item['name']?.toString() ?? '',
                    style: TextStyle(
                        color: active
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.normal)),
              ),
            );
          },
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _products.isEmpty
                ? const Center(child: Text('该分类暂未上架商品'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _products.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 9,
                            mainAxisSpacing: 9,
                            childAspectRatio: .63),
                    itemBuilder: (_, index) => ShopProductCard(
                        product: _products[index],
                        onTap: () => widget.onProduct(
                            (_products[index]['id'] as num).toInt())),
                  ),
      ),
    ]);
  }
}

class ShopCartTab extends StatefulWidget {
  const ShopCartTab({super.key});
  @override
  State<ShopCartTab> createState() => _ShopCartTabState();
}

class _ShopCartTabState extends State<ShopCartTab> {
  final List<Map<String, dynamic>> _items = [];
  ApiSessionScope _session = ApiSessionScope();
  bool _loading = true;
  bool _refreshing = false;
  bool _updating = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    apiSessionChanges.addListener(_accountChanged);
    _load();
  }

  @override
  void dispose() {
    apiSessionChanges.removeListener(_accountChanged);
    _generation++;
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    _session = ApiSessionScope();
    _generation++;
    setState(() {
      _items.clear();
      _loading = true;
      _updating = false;
      _error = null;
    });
    _load();
  }

  Map<dynamic, dynamic> _checked(dynamic body) {
    if (body is! Map || body['code'] is! num) {
      throw const FormatException('购物车返回数据异常，请重试');
    }
    if (body['code'] != 0) {
      throw StateError(body['message']?.toString() ?? '购物车操作失败，请重试');
    }
    return body;
  }

  Future<void> _load({bool afterMutation = false}) async {
    if (!mounted || (_updating && !afterMutation)) return;
    final session = _session;
    final generation = ++_generation;
    setState(() => _refreshing = true);
    try {
      final response = await session.get('/api/shop/cart');
      final data = _checked(response.data)['data'];
      final list = data is Map ? data['list'] : null;
      if (list is! List) throw StateError('购物车返回数据异常，请重试');
      final items = <Map<String, dynamic>>[];
      for (final item in list) {
        if (item is! Map ||
            item['id'] is! num ||
            item['quantity'] is! num ||
            item['product'] is! Map ||
            item['sku'] is! Map) {
          throw StateError('购物车返回数据异常，请重试');
        }
        final value = Map<String, dynamic>.from(item);
        value['product'] = Map<String, dynamic>.from(item['product'] as Map);
        value['sku'] = Map<String, dynamic>.from(item['sku'] as Map);
        items.add(value);
      }
      if (mounted && session.current && generation == _generation) {
        setState(() {
          _error = null;
          _items
            ..clear()
            ..addAll(items);
        });
      }
    } catch (error) {
      if (mounted && session.current && generation == _generation) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : shopError(error, '购物车加载失败'));
      }
    } finally {
      if (mounted && session.current && generation == _generation) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _patch(Map<String, dynamic> item,
      {int? quantity, bool? selected, bool remove = false}) async {
    if (!mounted ||
        !_session.current ||
        _updating ||
        _refreshing ||
        _error != null) {
      return;
    }
    final session = _session;
    _generation++;
    setState(() => _updating = true);
    try {
      if (remove) {
        _checked((await session.delete('/api/shop/cart/${item['id']}')).data);
      } else {
        _checked((await session.patch('/api/shop/cart/${item['id']}', data: {
          if (quantity != null) 'quantity': quantity,
          if (selected != null) 'selected': selected
        }))
            .data);
      }
      if (!mounted || !session.current) return;
      await _load(afterMutation: true);
    } catch (error) {
      if (mounted && session.current) {
        if (error is! StateError) {
          setState(() => _error = '购物车更新结果尚未确认，请重新加载后继续');
        }
        showAppToast(context,
            error is StateError ? error.message.toString() : shopError(error));
      }
    } finally {
      if (mounted && session.current) setState(() => _updating = false);
    }
  }

  List<Map<String, dynamic>> get _selected =>
      _items.where((x) => x['selected'] == true && x['valid'] == true).toList();
  double get _total =>
      _selected.fold(0, (sum, item) => sum + shopPrice(item['subtotal']));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final busy = _updating || _refreshing;
    final cannotEdit = busy || _error != null;
    return Column(children: [
      if (_refreshing || _updating) const LinearProgressIndicator(minHeight: 2),
      if (_error != null) ...[
        Text(_error!, textAlign: TextAlign.center),
        TextButton(
            onPressed: busy ? null : _load, child: const Text('重新加载购物车')),
      ],
      Expanded(
        child: _items.isEmpty
            ? (_error == null
                ? const Center(child: Text('购物车还是空的'))
                : const SizedBox.shrink())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final item = _items[index];
                    final product =
                        Map<String, dynamic>.from(item['product'] as Map);
                    final sku = Map<String, dynamic>.from(item['sku'] as Map);
                    final quantity = (item['quantity'] as num).toInt();
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)),
                      child: Row(children: [
                        Checkbox(
                            value: item['selected'] == true,
                            onChanged: item['valid'] == true && !cannotEdit
                                ? (value) => _patch(item, selected: value)
                                : null),
                        SizedBox(
                            width: 76,
                            height: 76,
                            child: ShopNetworkImage(
                                product['coverUrl']?.toString(),
                                borderRadius: 10)),
                        const SizedBox(width: 11),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(product['name']?.toString() ?? '',
                                  maxLines: 2,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(sku['name']?.toString() ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textHint, fontSize: 12)),
                              const SizedBox(height: 7),
                              Row(children: [
                                Text('¥${shopMoney(sku['price'])}',
                                    style: const TextStyle(
                                        color: Color(0xFFD76C45),
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                IconButton(
                                    onPressed: quantity > 1 && !cannotEdit
                                        ? () =>
                                            _patch(item, quantity: quantity - 1)
                                        : null,
                                    icon: const Icon(
                                        Icons.remove_circle_outline,
                                        size: 20)),
                                Text('$quantity'),
                                IconButton(
                                    onPressed: cannotEdit
                                        ? null
                                        : () => _patch(item,
                                            quantity: quantity + 1),
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 20)),
                                IconButton(
                                    onPressed: cannotEdit
                                        ? null
                                        : () => _patch(item, remove: true),
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20, color: AppColors.textHint)),
                              ]),
                            ])),
                      ]),
                    );
                  },
                ),
              ),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color: Colors.white,
          child: Row(children: [
            Text('合计 ¥${_total.toStringAsFixed(2)}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Spacer(),
            FilledButton(
              onPressed: _selected.isEmpty || busy || _error != null
                  ? null
                  : () async {
                      if (!_session.current || _updating || _refreshing) return;
                      final session = _session;
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ShopCheckoutPage(
                              cartItemIds: _selected
                                  .map((x) => (x['id'] as num).toInt())
                                  .toList())));
                      if (mounted && session.current) _load();
                    },
              child: Text('结算(${_selected.length})'),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class ShopMineTab extends StatelessWidget {
  const ShopMineTab({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String title, VoidCallback onTap,
            {String? subtitle}) =>
        Material(
          color: Colors.white,
          child: ListTile(
              leading: Icon(icon, color: AppColors.primary),
              title: Text(title),
              subtitle: subtitle == null ? null : Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap),
        );
    return ListView(padding: const EdgeInsets.all(14), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF3DAF9E), Color(0xFF7AC9BC)]),
            borderRadius: BorderRadius.circular(20)),
        child: const Row(children: [
          CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white24,
              child: Icon(Icons.shopping_bag_outlined,
                  color: Colors.white, size: 28)),
          SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('我的玄遇好物',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('订单、物流与善意赠礼统一管理', style: TextStyle(color: Colors.white70))
              ]))
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          _OrderShortcut(
              label: '待付款',
              icon: Icons.payments_outlined,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const ShopOrdersPage(initialStatus: 'pending_payment')))),
          _OrderShortcut(
              label: '待发货',
              icon: Icons.inventory_2_outlined,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ShopOrdersPage(
                      initialStatus: 'pending_shipment')))),
          _OrderShortcut(
              label: '待收货',
              icon: Icons.local_shipping_outlined,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      const ShopOrdersPage(initialStatus: 'shipped')))),
          _OrderShortcut(
              label: '全部订单',
              icon: Icons.receipt_long_outlined,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ShopOrdersPage()))),
        ]),
      ),
      const SizedBox(height: 14),
      ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(children: [
            row(
                Icons.volunteer_activism_outlined,
                '善意回声',
                () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const GoodwillEchoPage())),
                subtitle: '申请记录与善意赠礼'),
            const Divider(height: 1, indent: 56),
            row(
                Icons.location_on_outlined,
                '收货地址',
                () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ShopAddressPage()))),
            const Divider(height: 1, indent: 56),
            row(
                Icons.assignment_return_outlined,
                '退款与售后',
                () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ShopAfterSalePage()))),
          ])),
    ]);
  }
}

class _OrderShortcut extends StatelessWidget {
  const _OrderShortcut(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Column(children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(height: 7),
                Text(label, style: const TextStyle(fontSize: 12))
              ]))));
}

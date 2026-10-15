import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/region.dart';
import '../utils/region_loader.dart';

const _purple = AppColors.primary;
const _greyText = AppColors.textSecondary;

/// 出生地址选择弹窗，与 myresource/bazi_gui 的省市区三级一致，数据来自 assets/region_map.json
class BirthPlacePickerSheet extends StatefulWidget {
  final Region? initialRegion;
  final void Function(Region) onConfirm;
  final String title;

  const BirthPlacePickerSheet({
    super.key,
    this.initialRegion,
    this.title = '出生地址',
    required this.onConfirm,
  });

  static Future<void> show(
    BuildContext context, {
    Region? initialRegion,
    String title = '出生地址',
    required void Function(Region) onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BirthPlacePickerSheet(
        initialRegion: initialRegion,
        title: title,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<BirthPlacePickerSheet> createState() => _BirthPlacePickerSheetState();
}

class _BirthPlacePickerSheetState extends State<BirthPlacePickerSheet> {
  List<Region> _provinces = [];
  Region? _province;
  Region? _city;
  Region? _district;
  bool _loading = true;
  String? _error;

  static const _assetPath = 'assets/region_map.json';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await RegionLoader.loadFromAsset(_assetPath);
      if (mounted) {
        setState(() {
          _provinces = list;
          _loading = false;
          _applyInitialRegion(list);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '暂时无法加载地区列表，请稍后重试';
        });
      }
    }
  }

  void _applyInitialRegion(List<Region> provinces) {
    final r = widget.initialRegion;
    if (r == null) return;
    final parts = r.extPath.split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    final p = provinces.cast<Region?>().firstWhere(
          (x) => x?.name == parts[0],
          orElse: () => null,
        );
    if (p == null) return;
    _province = p;
    if (parts.length < 2) return;
    final c = p.children.cast<Region?>().firstWhere(
          (x) => x?.name == parts[1],
          orElse: () => null,
        );
    if (c == null) return;
    _city = c;
    if (parts.length < 3) return;
    final d = c.children.cast<Region?>().firstWhere(
          (x) => x?.name == parts[2],
          orElse: () => null,
        );
    if (d != null) _district = d;
  }

  List<Region> get _cities => _province?.children ?? [];
  List<Region> get _districts => _city?.children ?? [];

  void _onConfirm(Region r) {
    widget.onConfirm(r);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    return Container(
      margin: EdgeInsets.only(top: safePadding.top + 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child:
                          const Text('取消', style: TextStyle(color: _greyText)),
                    ),
                  ],
                ),
              ),
              if (!_loading &&
                  _error == null &&
                  (_province != null || _city != null))
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      if (_province != null) ...[
                        Text(_province!.name,
                            style:
                                const TextStyle(color: _purple, fontSize: 14)),
                        if (_city != null) ...[
                          const Text(' > ',
                              style: TextStyle(color: _greyText, fontSize: 14)),
                          Text(_city!.name,
                              style: const TextStyle(
                                  color: _purple, fontSize: 14)),
                        ],
                      ],
                      const Spacer(),
                      if (_city != null || _province != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              if (_city != null) {
                                _city = null;
                              } else {
                                _province = null;
                              }
                              _district = null;
                            });
                          },
                          child: const Text('上一级',
                              style: TextStyle(fontSize: 14, color: _greyText)),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: _purple))
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_error!,
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center),
                            ),
                          )
                        : _buildList(scrollController),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(ScrollController scrollController) {
    if (_province == null) {
      return _regionList(_provinces, scrollController, (r) {
        setState(() => _province = r);
        if (r.children.isEmpty) _onConfirm(r);
      });
    }
    if (_city == null) {
      return _regionList(_cities, scrollController, (r) {
        if (r.children.isEmpty || r.isLeaf) {
          _onConfirm(r);
          return;
        }
        setState(() => _city = r);
      });
    }
    if (_districts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: TextButton(
            onPressed: () => _onConfirm(_city!),
            child: const Text('确认选择',
                style: TextStyle(color: _purple, fontSize: 16)),
          ),
        ),
      );
    }
    return _regionList(_districts, scrollController, _onConfirm);
  }

  Widget _regionList(List<Region> items, ScrollController scrollController,
      void Function(Region) onTap) {
    return ListView.builder(
      controller: scrollController,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final r = items[index];
        return ListTile(
          title: Text(r.name,
              style:
                  const TextStyle(fontSize: 16, color: AppColors.textPrimary)),
          trailing: r.children.isNotEmpty
              ? const Icon(Icons.chevron_right, color: _greyText)
              : null,
          onTap: () => onTap(r),
        );
      },
    );
  }
}

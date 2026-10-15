abstract final class VirtualAvatarCatalog {
  static const styleNames = <String, String>{
    'micro': '高级微卡通',
    'oriental': '新中式精绘',
    'urban': '都市轻写实',
    'healing': '治愈手绘',
    'night': '夜幕暗黑',
    'shanhai': '山海异灵',
    'clay': '轻3D人像',
    'anime': '潮流插画',
    'starsea': '星海幻想',
  };

  static const finishedAssets = <String, String>{
    'micro_qinghe': 'assets/avatars/finished/micro_qinghe.webp',
    'micro_nuanxi': 'assets/avatars/finished/micro_nuanxi.webp',
    'micro_jinglan': 'assets/avatars/finished/micro_jinglan.webp',
    'oriental_moyu': 'assets/avatars/finished/oriental_moyu.webp',
    'oriental_yuetang': 'assets/avatars/finished/oriental_yuetang.webp',
    'oriental_qingheng': 'assets/avatars/finished/oriental_qingheng.webp',
    'urban_chengye': 'assets/avatars/finished/urban_chengye.webp',
    'urban_wanqing': 'assets/avatars/finished/urban_wanqing.webp',
    'urban_lingjie': 'assets/avatars/finished/urban_lingjie.webp',
    'healing_nuanyang': 'assets/avatars/finished/healing_nuanyang.webp',
    'healing_huamian': 'assets/avatars/finished/healing_huamian.webp',
    'healing_muguang': 'assets/avatars/finished/healing_muguang.webp',
    'night_heiyi': 'assets/avatars/finished/night_heiyi.webp',
    'night_yelan': 'assets/avatars/finished/night_yelan.webp',
    'night_yuehen': 'assets/avatars/finished/night_yuehen.webp',
    'shanhai_canglin': 'assets/avatars/finished/shanhai_canglin.webp',
    'shanhai_yunjing': 'assets/avatars/finished/shanhai_yunjing.webp',
    'shanhai_xueyuan': 'assets/avatars/finished/shanhai_xueyuan.webp',
    'clay_yanxu': 'assets/avatars/finished/clay_yanxu.webp',
    'clay_nuanxia': 'assets/avatars/finished/clay_nuanxia.webp',
    'clay_qingye': 'assets/avatars/finished/clay_qingye.webp',
    'anime_xuanche': 'assets/avatars/finished/anime_xuanche.webp',
    'anime_mitao': 'assets/avatars/finished/anime_mitao.webp',
    'anime_zimu': 'assets/avatars/finished/anime_zimu.webp',
  };

  /// 头像商品编号与成品素材编号不同：商品编号用于运营和订单，素材编号
  /// 用于客户端渲染。聊天里的送装扮消息只携带商品编号，因此这里保留
  /// 一份稳定映射，确保发送方和接收方看到同一张头像。
  static const productAssetCodes = <String, String>{
    'micro_free_qinghe': 'micro_qinghe',
    'micro_free_nuanxi': 'micro_nuanxi',
    'micro_free_jinglan': 'micro_jinglan',
    'new_chinese_ink': 'oriental_moyu',
    'oriental_lotus': 'oriental_yuetang',
    'oriental_qingheng': 'oriental_qingheng',
    'urban_light': 'urban_chengye',
    'urban_afterglow': 'urban_wanqing',
    'urban_lingjie': 'urban_lingjie',
    'healing_hand': 'healing_nuanyang',
    'healing_cloud': 'healing_huamian',
    'healing_muguang': 'healing_muguang',
    'night_spark': 'night_heiyi',
    'night_rose': 'night_yelan',
    'night_yuehen': 'night_yuehen',
    'shanhai_deer': 'shanhai_canglin',
    'shanhai_moon': 'shanhai_yunjing',
    'shanhai_xueyuan': 'shanhai_xueyuan',
    'clay_tea': 'clay_yanxu',
    'clay_green': 'clay_nuanxia',
    'clay_qingye': 'clay_qingye',
    'jade_toy': 'anime_xuanche',
    'anime_breeze': 'anime_mitao',
    'anime_zimu': 'anime_zimu',
  };

  static String? assetPath(Map<dynamic, dynamic>? config) {
    final code = config?['assetCode']?.toString();
    return code == null ? null : finishedAssets[code];
  }

  static Map<String, dynamic> configForProductCode(String? productCode) {
    final assetCode = productAssetCodes[productCode];
    if (assetCode == null) return initialConfig();
    final style = assetCode.split('_').first;
    return {
      ...initialConfig(),
      'renderStyle': style,
      'categoryCode': style,
      'assetCode': assetCode,
    };
  }

  static String? assetUrl(Map<dynamic, dynamic>? config) =>
      _httpsUrl(config?['assetUrl']);

  static String? thumbnailUrl(Map<dynamic, dynamic>? config) =>
      _httpsUrl(config?['thumbnailUrl']) ?? assetUrl(config);

  static bool hasArtwork(Map<dynamic, dynamic>? config) =>
      assetPath(config) != null || assetUrl(config) != null;

  static String? _httpsUrl(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return raw;
  }

  static String initialAssetCode([int? gender]) => gender == 1
      ? 'micro_qinghe'
      : gender == 2
      ? 'micro_nuanxi'
      : 'micro_jinglan';

  static Map<String, dynamic> initialConfig([int? gender]) => {
    'schemaVersion': 6,
    'renderStyle': 'micro',
    'productType': 'finished',
    'safeCircleApproved': true,
    'safeCircleInsetPercent': 13,
    'presentation': gender == 1
        ? 'male'
        : gender == 2
        ? 'female'
        : 'neutral',
    'categoryCode': 'micro',
    'assetCode': initialAssetCode(gender),
  };

  /// 接口暂不可用时仍可选择和保存三张平台免费初始款。
  static List<Map<String, dynamic>> get builtInFreeProducts => [
    _freeProduct(
      id: -1,
      code: 'micro_free_qinghe',
      name: '清和',
      description: '清朗自然的高级微卡通初始款',
      gender: 1,
    ),
    _freeProduct(
      id: -2,
      code: 'micro_free_nuanxi',
      name: '暖夕',
      description: '温柔明亮的高级微卡通初始款',
      gender: 2,
    ),
    _freeProduct(
      id: -3,
      code: 'micro_free_jinglan',
      name: '静岚',
      description: '安静清醒的高级微卡通初始款',
      gender: null,
    ),
  ];

  static Map<String, dynamic> _freeProduct({
    required int id,
    required String code,
    required String name,
    required String description,
    required int? gender,
  }) => {
    'id': id,
    'code': code,
    'name': name,
    'style': styleNames['micro'],
    'description': description,
    'price': '0',
    'config': initialConfig(gender),
    'productType': 'finished',
    'categoryCode': 'micro',
    'categoryName': styleNames['micro'],
    'creatorName': '玄遇设计所',
    'owned': true,
  };
}

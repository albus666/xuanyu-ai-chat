/// 八字日主对应的官方命灵身份。
///
/// 命灵名称、立绘与性格短句只在这里维护，排盘个人信息和缘分档案卡共用，
/// 避免同一个日主在不同页面出现不同命灵。
class MinglingIdentity {
  const MinglingIdentity({
    required this.dayGan,
    required this.element,
    required this.name,
    required this.assetKey,
    required this.temperament,
  });

  final String dayGan;
  final String element;
  final String name;
  final String assetKey;
  final String temperament;

  String get title => '$dayGan$element · $name';
  String get assetPath => 'assets/mingling_v2/$assetKey.png';
}

const _minglingIdentities = <String, MinglingIdentity>{
  '甲': MinglingIdentity(
    dayGan: '甲',
    element: '木',
    name: '青角鹿',
    assetKey: 'jia_full_v3',
    temperament: '正直进取 · 生机舒展',
  ),
  '乙': MinglingIdentity(
    dayGan: '乙',
    element: '木',
    name: '藤耳兔',
    assetKey: 'yi_full_v3',
    temperament: '外柔内韧 · 感知细腻',
  ),
  '丙': MinglingIdentity(
    dayGan: '丙',
    element: '火',
    name: '曜阳狮',
    assetKey: 'bing_full_v3',
    temperament: '坦率明朗 · 行动力强',
  ),
  '丁': MinglingIdentity(
    dayGan: '丁',
    element: '火',
    name: '灯角羊',
    assetKey: 'ding_lamb_full_v3',
    temperament: '温暖敏锐 · 重视氛围',
  ),
  '戊': MinglingIdentity(
    dayGan: '戊',
    element: '土',
    name: '山灵熊',
    assetKey: 'wu_full_v3',
    temperament: '稳重担当 · 重视承诺',
  ),
  '己': MinglingIdentity(
    dayGan: '己',
    element: '土',
    name: '云田狸',
    assetKey: 'ji_full_v3',
    temperament: '务实包容 · 善理细节',
  ),
  '庚': MinglingIdentity(
    dayGan: '庚',
    element: '金',
    name: '银纹虎',
    assetKey: 'geng_full_v3',
    temperament: '果断清醒 · 边界分明',
  ),
  '辛': MinglingIdentity(
    dayGan: '辛',
    element: '金',
    name: '月羽鹤',
    assetKey: 'xin_full_v3',
    temperament: '精致敏锐 · 重视品质',
  ),
  '壬': MinglingIdentity(
    dayGan: '壬',
    element: '水',
    name: '沧浪龙灵',
    assetKey: 'ren_full_v3',
    temperament: '开阔灵活 · 善于应变',
  ),
  '癸': MinglingIdentity(
    dayGan: '癸',
    element: '水',
    name: '雨耳獭',
    assetKey: 'gui_full_v3',
    temperament: '细腻聪慧 · 善于观察',
  ),
};

MinglingIdentity? minglingIdentityForDayGan(String dayGan) =>
    _minglingIdentities[dayGan.trim()];

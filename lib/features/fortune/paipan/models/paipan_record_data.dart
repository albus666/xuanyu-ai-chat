import 'region.dart';

/// 从记录文件解析出的排盘数据，用于回填首页表单
class PaipanRecordData {
  final String? name;
  final DateTime birthDateTime;
  final bool isFemale;
  final int calendarTypeIndex;
  final Region? birthPlace;

  const PaipanRecordData({
    this.name,
    required this.birthDateTime,
    required this.isFemale,
    required this.calendarTypeIndex,
    this.birthPlace,
  });
}

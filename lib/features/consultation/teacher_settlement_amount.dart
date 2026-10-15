/// Server settlement amounts may contain fractions of a cent. Withdrawals must
/// never round those fractions up beyond the actual available balance.
String withdrawableAmountText(Object? value) {
  final raw = '$value';
  final amount = double.tryParse(raw);
  if (amount == null || !amount.isFinite || amount <= 0) return '0.00';
  final decimal = RegExp(r'^\+?(\d+)(?:\.(\d*))?$').firstMatch(raw);
  if (decimal != null) {
    final whole = int.parse(decimal.group(1)!);
    final cents = (decimal.group(2) ?? '').padRight(2, '0').substring(0, 2);
    return '$whole.$cents';
  }
  final cents = (amount * 100).floor();
  return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

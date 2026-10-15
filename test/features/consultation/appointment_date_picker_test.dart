import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xuanyu/features/consultation/appointment_date_picker.dart';

void main() {
  testWidgets('预约日期采用滚轮并限制预约范围，确认返回选择值', (tester) async {
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  child: const Text('日期'),
                  onPressed: () async {
                    selected = await showAppointmentDatePicker(context,
                        initialDate: DateTime(2026, 10, 12),
                        now: DateTime(2026, 10, 11));
                  },
                ))));
    await tester.tap(find.text('日期'));
    await tester.pumpAndSettle();
    final wheel =
        tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(wheel.mode, CupertinoDatePickerMode.date);
    expect(wheel.minimumDate, DateTime(2026, 10, 11));
    wheel.onDateTimeChanged(DateTime(2026, 10, 15));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(selected, DateTime(2026, 10, 15));
  });
  testWidgets('预约时间采用24小时滚轮，确认返回时分', (tester) async {
    TimeOfDay? selected;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () async => selected =
                      await showAppointmentTimePicker(context,
                          initialTime: const TimeOfDay(hour: 9, minute: 24)),
                  child: const Text('时间'),
                ))));
    await tester.tap(find.text('时间'));
    await tester.pumpAndSettle();
    final picker =
        tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(picker.mode, CupertinoDatePickerMode.time);
    expect(picker.use24hFormat, isTrue);
    picker.onDateTimeChanged(DateTime(2026, 1, 1, 16, 35));
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(selected, const TimeOfDay(hour: 16, minute: 35));
  });
}

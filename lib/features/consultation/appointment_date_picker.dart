import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<DateTime?> showAppointmentDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime now,
}) {
  final first = DateTime(now.year, now.month, now.day);
  final last = first.add(const Duration(days: 90));
  var selected = DateTime(initialDate.year, initialDate.month, initialDate.day);
  if (selected.isBefore(first)) selected = first;
  if (selected.isAfter(last)) selected = last;
  return showModalBottomSheet<DateTime>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: 300,
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              const Text('选择预约日期'),
              TextButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('确定')),
            ]),
            Expanded(
                child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              dateOrder: DatePickerDateOrder.ymd,
              initialDateTime: selected,
              minimumDate: first,
              maximumDate: last,
              onDateTimeChanged: (date) => selected = date,
            )),
          ]),
        )),
  );
}

Future<TimeOfDay?> showAppointmentTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  var selected = initialTime;
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: 300,
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              const Text('选择预约时间'),
              TextButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('确定')),
            ]),
            Expanded(
                child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              use24hFormat: true,
              initialDateTime:
                  DateTime(2026, 1, 1, initialTime.hour, initialTime.minute),
              onDateTimeChanged: (value) =>
                  selected = TimeOfDay.fromDateTime(value),
            )),
          ]),
        )),
  );
}

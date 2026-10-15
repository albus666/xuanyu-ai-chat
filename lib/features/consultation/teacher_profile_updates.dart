import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';

/// Notify open teacher screens using the successfully saved server profile.
class TeacherProfileUpdate {
  TeacherProfileUpdate(Map<String, dynamic> value)
      : profile = Map.unmodifiable(value),
        session = apiSessionChanges.value;
  final Map<String, dynamic> profile;
  final int session;
  bool get current => session == apiSessionChanges.value;
}

final teacherProfileUpdates = ValueNotifier<TeacherProfileUpdate?>(null);

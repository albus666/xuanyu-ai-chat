import 'package:dio/dio.dart';

import 'api_session_scope.dart';

/// Coalesce simultaneous profile reads only; never reuse a completed response.
/// Editing a profile invalidates the in-flight group before the follow-up read.
class AccountProfileRequests {
  AccountProfileRequests._();
  static int _generation = 0;
  static final Map<int, Future<Response<dynamic>>> _pending = {};

  static Future<Response<dynamic>> fetch(ApiSessionScope scope) {
    scope.ensureCurrent();
    final existing = _pending[scope.session];
    if (existing != null) return existing;
    late final Future<Response<dynamic>> task;
    final generation = _generation;
    task = scope.get('/api/auth/me').then<Response<dynamic>>((response) {
      scope.ensureCurrent();
      // A profile edit supersedes this read; join the replacement live request.
      return generation == _generation ? response : fetch(scope);
    }).whenComplete(() {
      if (identical(_pending[scope.session], task)) {
        _pending.remove(scope.session);
      }
    });
    _pending[scope.session] = task;
    return task;
  }

  static void invalidate() {
    _generation++;
    _pending.clear();
  }
}

import 'package:flutter/material.dart';

import '../../models/role.dart';

/// Holds the active demo role. Injected into the shell so widget tests can
/// drive it without any Supabase dependency.
class RoleScope extends ChangeNotifier {
  RoleScope({Role initialRole = Role.parent}) : _role = initialRole;

  Role _role;

  Role get role => _role;

  set role(Role r) {
    if (r == _role) return;
    _role = r;
    notifyListeners();
  }

  void toggle() => role = _role == Role.parent ? Role.kid : Role.parent;
}

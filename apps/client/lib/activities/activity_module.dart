import 'package:flutter/widgets.dart';

abstract interface class ActivityModule {
  String get id;
  String get title;
  IconData get icon;
  WidgetBuilder get home;
  WidgetBuilder? get settings;
}

class ActivityRegistry {
  ActivityRegistry(List<ActivityModule> modules)
    : modules = List.unmodifiable(modules) {
    final ids = <String>{};
    for (final module in modules) {
      if (!RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(module.id)) {
        throw ArgumentError('Invalid activity module ID: ${module.id}');
      }
      if (!ids.add(module.id)) {
        throw ArgumentError('Duplicate activity module ID: ${module.id}');
      }
    }
  }

  final List<ActivityModule> modules;
}

final activityRegistry = ActivityRegistry([]);

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/curriculum.dart';
import 'data/store.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final course = await Curriculum.load();
  // YUE_DATA lets a test run keep its own data, away from your progress.
  final folder = Platform.environment['YUE_DATA'] ?? p.join((await getApplicationSupportDirectory()).path, 'data');
  runApp(YueApp(state: AppState(Store.open(folder), course)));
}

class YueApp extends StatefulWidget {
  const YueApp({super.key, required this.state});
  final AppState state;

  @override
  State<YueApp> createState() => _YueAppState();
}

class _YueAppState extends State<YueApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A window left open overnight still rolls over to the new day.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.state.openDay();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: widget.state,
      child: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) => MaterialApp(
          title: 'Yue',
          debugShowCheckedModeBanner: false,
          theme: themeNamed(widget.state.themeName),
          themeAnimationDuration: Motion.morph,
          themeAnimationCurve: Motion.morphCurve,
          home: const Shell(),
        ),
      ),
    );
  }
}

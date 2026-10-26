import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state/app_state.dart';
import 'home_shell.dart';
import 'phone_shell.dart';
import 'theme.dart';

class BoonApp extends StatelessWidget {
  const BoonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final state = AppState();
        unawaited(state.init());
        return state;
      },
      child: MaterialApp(
        title: 'Boon',
        debugShowCheckedModeBanner: false,
        theme: buildBoonTheme(),
        // Android runs the phone-flavored companion; desktop keeps the
        // full unified panel shell unchanged.
        home: Platform.isAndroid ? const PhoneShell() : const HomeShell(),
      ),
    );
  }
}

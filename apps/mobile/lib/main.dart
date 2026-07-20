import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Hosted under /web/; hash routes avoid go_router path mismatches with base-href.
  if (kIsWeb) {
    setUrlStrategy(HashUrlStrategy());
  }
  runApp(const ProviderScope(child: ShareListApp()));
}

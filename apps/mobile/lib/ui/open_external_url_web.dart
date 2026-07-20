import 'package:web/web.dart' as web;

/// Opens [url] in a new browser tab.
Future<void> openExternalUrl(String url) async {
  web.window.open(url, '_blank');
}

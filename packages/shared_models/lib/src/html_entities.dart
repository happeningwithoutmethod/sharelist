/// Decodes common HTML entities YouTube returns in snippet titles
/// (e.g. `&#39;` → `'`, `&amp;` → `&`).
String decodeHtmlEntities(String value) {
  var out = value;
  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
    final code = int.tryParse(match.group(1)!, radix: 16);
    if (code == null) return match.group(0)!;
    return String.fromCharCode(code);
  });
  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    final code = int.tryParse(match.group(1)!);
    if (code == null) return match.group(0)!;
    return String.fromCharCode(code);
  });
  return out
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}

import 'package:http/http.dart' as http;

/// Latest net asset value of one mutual fund scheme.
class NavQuote {
  const NavQuote({
    required this.code,
    required this.name,
    required this.nav,
    required this.date,
  });

  final String code;
  final String name;
  final double nav;
  final DateTime date;
}

/// AMFI publishes every scheme's NAV daily in one public text file.
const amfiNavUrl = 'https://www.amfiindia.com/spages/NAVAll.txt';

/// Downloads and parses the AMFI NAV file.
Future<Map<String, NavQuote>> fetchAmfiNavs({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(Uri.parse(amfiNavUrl))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw http.ClientException('AMFI returned HTTP ${response.statusCode}');
    }
    return parseAmfiNavs(response.body);
  } finally {
    if (client == null) c.close();
  }
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Parses lines of the form
/// `code;isin1;isin2;scheme name;nav;dd-Mon-yyyy`. Headings, blank lines and
/// schemes without a NAV ("N.A.") are skipped.
Map<String, NavQuote> parseAmfiNavs(String text) {
  final result = <String, NavQuote>{};
  for (final line in text.split('\n')) {
    final f = line.split(';');
    if (f.length < 6) continue;
    final code = f[0].trim();
    if (int.tryParse(code) == null) continue;
    final nav = double.tryParse(f[4].trim());
    final date = _parseDate(f[5].trim());
    if (nav == null || nav <= 0 || date == null) continue;
    result[code] = NavQuote(
      code: code,
      name: f[3].trim().replaceAll(RegExp(r'\s+'), ' '),
      nav: nav,
      date: date,
    );
  }
  return result;
}

DateTime? _parseDate(String s) {
  final p = s.split('-');
  if (p.length != 3) return null;
  final day = int.tryParse(p[0]);
  final month = _months[p[1].toLowerCase()];
  final year = int.tryParse(p[2]);
  if (day == null || month == null || year == null) return null;
  return DateTime.utc(year, month, day);
}

/// Schemes whose name contains every word of [query], best matches first.
List<NavQuote> searchSchemes(
  Map<String, NavQuote> navs,
  String query, {
  int limit = 50,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final matches = navs.values.where((q) {
    final name = q.name.toLowerCase();
    return q.code == query.trim() || words.every(name.contains);
  }).toList()..sort((a, b) => a.name.length.compareTo(b.name.length));
  return matches.take(limit).toList();
}

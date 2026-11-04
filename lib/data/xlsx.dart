/// Minimal Excel (.xlsx) writer: a zip of SpreadsheetML parts with text,
/// numbers, a bold header row and a money format. Enough for exports, with
/// no extra dependency.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class XlsxSheet {
  const XlsxSheet(this.name, this.rows, {this.widths = const []});

  /// Sheet tab name (max 31 characters, no []:*?/\).
  final String name;

  /// First row is the header. Cells are String, int, double, [Money] or null.
  final List<List<Object?>> rows;

  /// Column widths in characters.
  final List<double> widths;
}

/// A rupee amount, written as a number with two decimals so Excel can sum it.
class Money {
  const Money(this.paise);
  final int paise;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Control characters other than tab/newline are not allowed in XML.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _col(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

String _sheetXml(XlsxSheet sheet) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    )
    ..write(
      '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" '
      'topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView>'
      '</sheetViews>',
    );
  if (sheet.widths.isNotEmpty) {
    b.write('<cols>');
    for (var i = 0; i < sheet.widths.length; i++) {
      b.write(
        '<col min="${i + 1}" max="${i + 1}" width="${sheet.widths[i]}" '
        'customWidth="1"/>',
      );
    }
    b.write('</cols>');
  }
  b.write('<sheetData>');
  for (var r = 0; r < sheet.rows.length; r++) {
    b.write('<row r="${r + 1}">');
    final row = sheet.rows[r];
    for (var c = 0; c < row.length; c++) {
      final v = row[c];
      if (v == null) continue;
      final ref = '${_col(c)}${r + 1}';
      // Style 1 = bold header, 2 = money.
      if (v is Money) {
        b.write(
          '<c r="$ref" s="2"><v>${(v.paise / 100).toStringAsFixed(2)}</v></c>',
        );
      } else if (v is num) {
        b.write('<c r="$ref"${r == 0 ? ' s="1"' : ''}><v>$v</v></c>');
      } else {
        b.write(
          '<c r="$ref" t="inlineStr"${r == 0 ? ' s="1"' : ''}><is><t xml:space="preserve">'
          '${_esc(v.toString())}</t></is></c>',
        );
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}

/// The workbook as .xlsx bytes.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  final names = <String>{};
  String safeName(String n) {
    var s = n.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    if (s.length > 31) s = s.substring(0, 31);
    var unique = s;
    var i = 2;
    while (!names.add(unique)) {
      unique = '${s.substring(0, s.length.clamp(0, 28))} $i';
      i++;
    }
    return unique;
  }

  final sheetNames = [for (final s in sheets) safeName(s.name)];
  final archive = Archive();
  void add(String path, String xml) =>
      archive.add(ArchiveFile.bytes(path, utf8.encode(xml)));

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(sheetNames[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
  );
  add(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="1"><numFmt numFmtId="164" formatCode="&quot;₹&quot;#,##0.00"/></numFmts>'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="3">'
        '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
        '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
        '</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>',
  );
  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i]));
  }
  return ZipEncoder().encodeBytes(archive);
}

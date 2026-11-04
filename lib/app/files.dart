/// Sharing exported files, picking files to import, and storing receipt
/// photos in the app's private folder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [contents] to a temporary file and opens the Android share sheet
/// (Drive, Gmail, WhatsApp, Files, ...).
Future<void> shareTextFile(
  String fileName,
  String contents, {
  required String mimeType,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(contents, encoding: utf8);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      subject: subject ?? fileName,
    ),
  );
}

/// Like [shareTextFile] for binary files (Excel, PDF).
Future<void> shareBytesFile(
  String fileName,
  List<int> bytes, {
  required String mimeType,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      subject: subject ?? fileName,
    ),
  );
}

/// Lets the user pick a file and returns its text, or null if cancelled.
Future<String?> pickTextFile() async {
  // Some Android file providers do not map .csv / .json to a MIME type, so
  // filtering by extension can hide valid files; accept any file instead.
  final f = await FilePicker.pickFile(type: FileType.any);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  return utf8.decode(bytes, allowMalformed: true);
}

/// Takes or picks a photo and copies it into the app's receipts folder.
/// Returns the stored path, or null if cancelled.
Future<String?> captureReceipt({required bool camera}) async {
  final picked = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 75,
  );
  if (picked == null) return null;
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/receipts');
  await dir.create(recursive: true);
  final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';
  final dest = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext';
  await File(picked.path).copy(dest);
  return dest;
}

/// Removes a stored receipt photo; missing files are ignored.
Future<void> deleteReceipt(String? path) async {
  if (path == null) return;
  try {
    await File(path).delete();
  } on FileSystemException {
    // Already gone.
  }
}

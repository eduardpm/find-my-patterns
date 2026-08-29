import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_error.dart';
import 'export_format.dart';
import 'export_repository.dart';
import 'export_state.dart';

/// Hands a staged export file off to the platform's share sheet.
///
/// A function type, not a direct call into [SharePlus], so a test can
/// substitute a no-op — the same seam `DiaryAudioRecorder.cacheDirectory`
/// uses for the filesystem, applied here to a plugin call instead.
typedef ShareExportFile = Future<void> Function(
  String path, {
  required String mimeType,
});

Future<void> _shareViaSystemSheet(
  String path, {
  required String mimeType,
}) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(path, mimeType: mimeType)]),
  );
}

/// Resolves the directory an export is staged into before being handed to
/// the share sheet.
///
/// The app's cache directory by default — the same directory
/// `DiaryAudioRecorder` stages voice recordings in, and for the same reason:
/// this file is a temporary copy of diary content on its way out of the app,
/// not something that belongs in shared storage on its own.
final exportCacheDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
);

/// The function the Export flow calls to open the share sheet.
final shareExportProvider = Provider<ShareExportFile>(
  (ref) => _shareViaSystemSheet,
);

/// Orchestrates one export: download the chosen format, stage it as a file,
/// hand it to the share sheet.
///
/// Progress and failure both live in [state] rather than being returned from
/// [export], so the Settings row and the format sheet can both watch the same
/// provider and agree about whether a download is in flight.
class ExportController extends Notifier<ExportState> {
  @override
  ExportState build() => const ExportIdle();

  /// Downloads the diary as [format], writes it to the cache directory, and
  /// opens the share sheet on it.
  ///
  /// Leaves [state] as [ExportIdle] again once the share sheet has been
  /// handed the file — this does not wait for or report what the user does
  /// with the share sheet itself, only whether getting the file *to* it
  /// succeeded.
  Future<void> export(ExportFormat format) async {
    state = const ExportInProgress();
    try {
      final downloaded = await ref
          .read(exportRepositoryProvider)
          .download(format);
      final directory = await ref.read(exportCacheDirectoryProvider)();
      final filename = downloaded.filename ?? format.defaultFilename;
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(downloaded.bytes, flush: true);
      await ref.read(shareExportProvider)(file.path, mimeType: format.mimeType);
      state = const ExportIdle();
    } on ApiError catch (e) {
      state = ExportError(e.message);
    } on FileSystemException {
      state = const ExportError('Could not save the export on this device.');
    }
  }

  /// Clears an error, so the sheet can be reopened cleanly.
  void reset() => state = const ExportIdle();
}

/// The controller the Export row and its format sheet read and act through.
final exportControllerProvider =
    NotifierProvider<ExportController, ExportState>(
      ExportController.new,
    );

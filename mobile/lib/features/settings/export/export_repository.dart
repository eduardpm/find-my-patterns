import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import 'export_format.dart';

/// Downloads the whole diary from the backend (M-6), in either format.
class ExportRepository {
  /// Creates a repository over [_client].
  const ExportRepository(this._client);

  final ApiClient _client;

  /// Fetches the whole diary rendered as [format].
  Future<DownloadedFile> download(ExportFormat format) =>
      _client.getBytes(AppConfig.exportPath(format.queryValue));
}

/// The repository the Export flow reads through.
final exportRepositoryProvider = Provider<ExportRepository>(
  (ref) => ExportRepository(ref.watch(apiClientProvider)),
);

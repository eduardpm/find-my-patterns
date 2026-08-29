import 'package:dio/dio.dart';
import 'package:find_my_patterns/core/diary/calendar_date.dart';
import 'package:find_my_patterns/core/diary/feelings_api.dart';
import 'package:find_my_patterns/core/diary/monthly_summary_api.dart';
import 'package:find_my_patterns/core/network/api_client.dart';
import 'package:find_my_patterns/core/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

void main() {
  final feelingsBody = {
    'feelings': [
      {
        'key': 'happy',
        'label': 'Happy',
        'valence': 'positive',
        'group_key': 'uplifted',
      },
    ],
  };

  test('reads the month, encoded as a YYYY-MM query parameter', () async {
    final adapter = FakeHttpAdapter([
      FakeReply(200, body: feelingsBody),
      FakeReply(
        200,
        body: {
          'month': '2026-08',
          'days': [
            {
              'date': '2026-08-01',
              'feelings': ['happy'],
            },
          ],
          'totals_by_feeling': {'happy': 3},
          'average_entries_per_day': 1.0,
        },
      ),
    ]);
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter)
      ..configure(const BackendAddress(host: '10.0.2.2'));
    final api = MonthlySummaryApi(client, FeelingsApi(client));

    final summary = await api.forMonth(const YearMonth(2026, 8));

    expect(summary.month, const YearMonth(2026, 8));
    expect(summary.days.single.feelings.single.key, 'happy');
    expect(summary.averageEntriesPerDay, 1.0);
    expect(adapter.requests.last.uri.path, '/monthly-summary');
    expect(adapter.requests.last.uri.queryParameters['month'], '2026-08');
  });
}

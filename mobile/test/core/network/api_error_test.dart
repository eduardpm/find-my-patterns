import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the call sites that switch over a failure.
String describe(ApiError error) => switch (error) {
  BackendNotConfigured() => 'configure',
  NetworkFailure() => 'network',
  Unauthorized() => 'signin',
  HttpFailure(:final statusCode) => 'http $statusCode',
};

void main() {
  test('every failure carries a message', () {
    const errors = <ApiError>[
      BackendNotConfigured(),
      NetworkFailure('boom'),
      Unauthorized(),
      HttpFailure('nope', 500),
    ];
    for (final error in errors) {
      expect(error.message, isNotEmpty);
    }
  });

  test('the hierarchy is exhaustively switchable', () {
    expect(describe(const BackendNotConfigured()), 'configure');
    expect(describe(const NetworkFailure('boom')), 'network');
    expect(describe(const Unauthorized()), 'signin');
    expect(describe(const HttpFailure('nope', 503)), 'http 503');
  });

  test('only HTTP failures carry a status', () {
    expect(const BackendNotConfigured().statusCode, isNull);
    expect(const NetworkFailure('boom').statusCode, isNull);
    expect(const Unauthorized().statusCode, 401);
    expect(const HttpFailure('nope', 500).statusCode, 500);
  });

  test('Unauthorized takes an optional message', () {
    expect(const Unauthorized().message, isNotEmpty);
    expect(const Unauthorized('bad password').message, 'bad password');
  });

  test('toString names the failure and its message', () {
    expect(const NetworkFailure('boom').toString(), contains('NetworkFailure'));
    expect(const NetworkFailure('boom').toString(), contains('boom'));
  });

  test('failures are exceptions', () {
    expect(const BackendNotConfigured(), isA<Exception>());
  });
}

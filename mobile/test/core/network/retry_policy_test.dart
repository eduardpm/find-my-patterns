import 'package:find_my_patterns/core/network/api_error.dart';
import 'package:find_my_patterns/core/network/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('apiRetryPolicy', () {
    test('retries a dropped connection, briefly', () {
      expect(apiRetryPolicy(0, const NetworkFailure('refused')), isNotNull);
      expect(apiRetryPolicy(1, const NetworkFailure('refused')), isNotNull);
    });

    test('backs off between the two attempts', () {
      final first = apiRetryPolicy(0, const NetworkFailure('refused'))!;
      final second = apiRetryPolicy(1, const NetworkFailure('refused'))!;
      expect(second, greaterThan(first));
    });

    test('gives up after two retries rather than the framework’s ten', () {
      expect(apiRetryPolicy(2, const NetworkFailure('refused')), isNull);
      expect(apiRetryPolicy(9, const NetworkFailure('refused')), isNull);
    });

    test('retries a server error, because servers recover', () {
      expect(apiRetryPolicy(0, const HttpFailure('boom', 500)), isNotNull);
      expect(apiRetryPolicy(0, const HttpFailure('gateway', 502)), isNotNull);
    });

    test('never retries a request that was itself wrong', () {
      expect(apiRetryPolicy(0, const HttpFailure('not found', 404)), isNull);
      expect(apiRetryPolicy(0, const HttpFailure('bad', 422)), isNull);
    });

    test('never retries a failure only the user can fix', () {
      // Asking again cannot conjure a server address or a session.
      expect(apiRetryPolicy(0, const BackendNotConfigured()), isNull);
      expect(apiRetryPolicy(0, const Unauthorized()), isNull);
    });

    test('the whole budget stays under a second', () {
      final total =
          apiRetryPolicy(0, const NetworkFailure('x'))! +
          apiRetryPolicy(1, const NetworkFailure('x'))!;
      expect(total, lessThan(const Duration(seconds: 1)));
    });
  });
}

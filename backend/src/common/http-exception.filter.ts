import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from '@nestjs/common';
import type { Response } from 'express';

/**
 * The error envelope: `{"error": {"code", "message"}}`. Both clients parse this shape, so the
 * codes are contract (contracts/api.md).
 *
 * Note what this filter must **not** touch: the 409 stale-entry response carries a `current` key
 * as a sibling of `error`, so it is returned directly by the controller rather than thrown. Routing
 * it through here would silently drop `current` and relabel the code (contracts/api.md).
 *
 * Also not touched: `RequiresPremiumGuard`'s `{"error": "premium_required"}` (`billing/
 * requires-premium.guard.ts`) — a bare string under `error`, not the nested `{code, message}` this
 * filter builds for everything else. That shape is the issue's (#47) literal acceptance criterion,
 * so `passesThroughAsIs` below recognises and forwards it verbatim instead of wrapping it into
 * `{error: {code: 'error', message: '[object Object]'}}`, which is what falling through to the
 * generic branch would otherwise silently produce for any payload that is not a string.
 */
function passesThroughAsIs(payload: unknown): payload is { error: string } {
  return (
    typeof payload === 'object' &&
    payload !== null &&
    !Array.isArray(payload) &&
    Object.keys(payload).length === 1 &&
    typeof (payload as { error?: unknown }).error === 'string'
  );
}

const ERROR_CODES: Record<number, string> = {
  400: 'bad_request',
  401: 'unauthorized',
  404: 'not_found',
  409: 'conflict',
  422: 'validation_error',
  429: 'rate_limited',
};

@Catch()
export class ErrorEnvelopeFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const payload = exception.getResponse();

      if (passesThroughAsIs(payload)) {
        response.status(status).json(payload);
        return;
      }

      const message =
        typeof payload === 'string'
          ? payload
          : ((payload as { message?: string | string[] }).message ?? exception.message);

      response.status(status).json({
        error: {
          code: ERROR_CODES[status] ?? 'error',
          message: Array.isArray(message) ? message.join('; ') : message,
        },
      });
      return;
    }

    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      error: {
        code: 'internal_error',
        message: exception instanceof Error ? exception.message : String(exception),
      },
    });
  }
}

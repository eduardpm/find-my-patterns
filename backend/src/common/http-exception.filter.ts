import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from '@nestjs/common';
import type { Response } from 'express';

/**
 * The error envelope: `{"error": {"code", "message"}}`. Both clients parse this shape, so the
 * codes are contract (contracts/api.md).
 *
 * Note what this filter must **not** touch: the 409 stale-entry response carries a `current` key
 * as a sibling of `error`, so it is returned directly by the controller rather than thrown. Routing
 * it through here would silently drop `current` and relabel the code (contracts/api.md).
 */

const ERROR_CODES: Record<number, string> = {
  400: 'bad_request',
  404: 'not_found',
  422: 'validation_error',
};

@Catch()
export class ErrorEnvelopeFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const payload = exception.getResponse();
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

import 'reflect-metadata';
import { PATH_METADATA, METHOD_METADATA } from '@nestjs/common/constants';
import { RequestMethod } from '@nestjs/common';
import { MetadataScanner } from '@nestjs/core';
import { AppModule } from '../../src/app.module';

/**
 * The controllers `AppModule.forRoot()` actually registers — the same `DynamicModule.controllers`
 * array `main.ts#createApp` hands to Nest to build the real, running server. Reading it from here
 * rather than re-listing the controller classes by hand is what keeps this guard itself from
 * becoming the hand-maintained list its own doc comment says it exists to replace: a controller
 * added to `AppModule` is automatically in scope the next time this runs, with nothing to remember
 * to update in a second place.
 */
export function registeredControllers(): Array<new (...args: never[]) => unknown> {
  const module = AppModule.forRoot();
  return (module.controllers ?? []) as Array<new (...args: never[]) => unknown>;
}

/**
 * The route-inventory guard (M-1b, #46, task 4): "a lightweight route-inventory check that fails
 * CI when a new controller route isn't covered by the isolation suite."
 *
 * This enumerates routes the same way Nest's own `RouterExplorer`/`PathsExplorer` do internally —
 * reading the `path`/`method` reflect-metadata Nest's `@Controller()`/`@Get()`/`@Post()`/etc.
 * decorators attach to a controller class and its methods — rather than a hand-maintained list of
 * endpoints. A hand-written list is exactly what goes stale: a new `@Post()` handler added to an
 * existing controller would need a human to remember to add it to a second file, and that second
 * file is precisely the kind of "keeps the code honest a year from now" this guard exists to
 * replace. Reading the same metadata Nest itself reads to build the real Express router means a
 * route this function misses is a route the running server would not answer either.
 */
export interface RouteDescriptor {
  /** `GET`, `POST`, etc. — `RequestMethod[value]`, the same enum Nest's decorators use. */
  method: string;
  /** The full path, controller prefix plus handler path, normalised with a leading slash and no
   *  trailing slash (except the bare root `/`). Still carries Express-style `:param` segments. */
  path: string;
  controllerName: string;
  handlerName: string;
}

function addLeadingSlash(path: string): string {
  if (!path) return '/';
  return path.startsWith('/') ? path : `/${path}`;
}

/** Joins a controller prefix and a handler sub-path into one normalised path, collapsing the
 *  doubled slash a bare `@Controller()` (prefix `/`) plus a bare `@Get()` (sub-path `/`) would
 *  otherwise produce, and dropping a trailing slash other than on the root path itself. */
function joinPaths(prefix: string, subPath: string): string {
  const combined =
    subPath === '/' ? prefix : `${prefix === '/' ? '' : prefix}${addLeadingSlash(subPath)}`;
  const collapsed = combined.replace(/\/{2,}/g, '/');
  if (collapsed.length > 1 && collapsed.endsWith('/')) return collapsed.slice(0, -1);
  return collapsed || '/';
}

/**
 * Every route `controllers` declares, read straight from the `@Controller()`/`@Get()` (etc.)
 * decorator metadata — the exact classes `AppModule.forRoot()` registers, so this inventory is
 * never out of sync with what the running app actually serves.
 */
export function enumerateRoutes(
  controllers: Array<new (...args: never[]) => unknown>,
): RouteDescriptor[] {
  const scanner = new MetadataScanner();
  const routes: RouteDescriptor[] = [];

  for (const controller of controllers) {
    const controllerPathMeta: string | string[] =
      Reflect.getMetadata(PATH_METADATA, controller) ?? '/';
    const prefixes = (
      Array.isArray(controllerPathMeta) ? controllerPathMeta : [controllerPathMeta]
    ).map(addLeadingSlash);

    const prototype = (controller as { prototype: object }).prototype;
    for (const handlerName of scanner.getAllMethodNames(prototype)) {
      const handler = (prototype as Record<string, unknown>)[handlerName];
      const routePathMeta: string | string[] | undefined = Reflect.getMetadata(
        PATH_METADATA,
        handler,
      );
      // Not every prototype method is a route handler — a private helper carries no PATH_METADATA
      // at all, exactly the check `PathsExplorer.exploreMethodMetadata` itself makes.
      if (routePathMeta === undefined) continue;
      const requestMethod: number = Reflect.getMetadata(METHOD_METADATA, handler);
      const subPaths = (Array.isArray(routePathMeta) ? routePathMeta : [routePathMeta]).map(
        addLeadingSlash,
      );

      for (const prefix of prefixes) {
        for (const subPath of subPaths) {
          routes.push({
            method: RequestMethod[requestMethod] ?? String(requestMethod),
            path: joinPaths(prefix, subPath),
            controllerName: controller.name,
            handlerName,
          });
        }
      }
    }
  }

  return routes;
}

/** Converts a route's Express-style `:param` template into a matcher against a real request path
 *  (e.g. `/entries/:entryId` matches `/entries/abc-123`). Deliberately minimal — this codebase's
 *  routes use only plain `:name` segments, never wildcards or optional segments, so a full path-
 *  matching library would be answering a question this project never asks. */
export function routeMatches(route: RouteDescriptor, requestPath: string): boolean {
  const pattern = route.path
    .split('/')
    .map((segment) =>
      segment.startsWith(':') ? '[^/]+' : segment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'),
    )
    .join('/');
  return new RegExp(`^${pattern}$`).test(requestPath);
}

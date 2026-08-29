import type {
  GooglePlayProductType,
  PlayPurchaseVerifier,
  PurchaseVerification,
} from './play-verifier';

/**
 * The test double `PlayPurchaseVerifier` exists for (issue task 2). Never imported by
 * `app.module.ts` or any other production wiring — only by tests, via `CreateAppOptions.playVerifier`
 * (`../main.ts`), which is how an e2e test swaps this in without a real Google service account or
 * any network access at all.
 *
 * Results are keyed by `purchaseToken` and set with `queue`/`always`, rather than being a single
 * fixed answer: a test needs to script a sequence — "this token verifies as a year-long premium
 * subscription, that one is invalid, this other one is a lifetime purchase" — to exercise
 * `EntitlementsController` and the expiry sweep without any of it depending on real time passing.
 */
export class FakePlayVerifier implements PlayPurchaseVerifier {
  private readonly responses = new Map<string, PurchaseVerification>();
  private fallback: PurchaseVerification = { valid: false, expiresAt: null };
  readonly calls: Array<{
    purchaseToken: string;
    productId: string;
    productType: GooglePlayProductType;
  }> = [];

  /** Programs the result for one specific `purchaseToken`, regardless of `productId`. */
  respondTo(purchaseToken: string, result: PurchaseVerification): this {
    this.responses.set(purchaseToken, result);
    return this;
  }

  /** Sets what any token not given its own `respondTo` answer resolves to. Defaults to
   * `{ valid: false, expiresAt: null }` — an unprogrammed token behaves like one Play has never
   * heard of, which is the safer default for a test that forgot to program it. */
  respondByDefault(result: PurchaseVerification): this {
    this.fallback = result;
    return this;
  }

  async verify(
    purchaseToken: string,
    productId: string,
    productType: GooglePlayProductType,
  ): Promise<PurchaseVerification> {
    this.calls.push({ purchaseToken, productId, productType });
    return this.responses.get(purchaseToken) ?? this.fallback;
  }
}

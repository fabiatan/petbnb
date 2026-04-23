// Pluggable signature verifier for the iPay88 webhook. Phase 2d ships with a
// MockVerifier that accepts any payload. Replace with real HMAC logic when
// iPay88 sandbox credentials arrive — the interface stays the same so the
// Edge Function handler doesn't change.

export interface Ipay88Payload {
  refNo: string;
  amount: number;
  status: string;       // "1" = success per iPay88 docs
  transId: string;
  signature: string;
  merchantCode: string;
}

export interface Verifier {
  /**
   * Parse + validate a webhook POST body.
   * Returns the normalised payload on success, or throws on verification failure.
   */
  verify(formBody: URLSearchParams): Promise<Ipay88Payload>;
}

/**
 * Dev verifier that does no real signature check — just parses the fields and
 * returns them. DO NOT use in production.
 */
export class MockVerifier implements Verifier {
  async verify(formBody: URLSearchParams): Promise<Ipay88Payload> {
    const refNo = formBody.get("RefNo");
    const amount = formBody.get("Amount");
    const status = formBody.get("Status");
    const transId = formBody.get("TransId") ?? "";
    const signature = formBody.get("Signature") ?? "";
    const merchantCode = formBody.get("MerchantCode") ?? "";

    if (!refNo) throw new Error("Missing RefNo");
    if (!amount) throw new Error("Missing Amount");
    if (!status) throw new Error("Missing Status");

    const parsedAmount = Number(amount);
    if (!Number.isFinite(parsedAmount) || parsedAmount < 0) {
      throw new Error(`Invalid Amount: ${amount}`);
    }

    return {
      refNo,
      amount: parsedAmount,
      status,
      transId,
      signature,
      merchantCode,
    };
  }
}

/**
 * Real iPay88 verifier. When sandbox credentials are provisioned:
 *   1. Read IPAY88_MERCHANT_KEY from Edge Function secrets.
 *   2. Compute HMAC-SHA256 over the canonical string:
 *      MerchantKey + MerchantCode + RefNo + Amount (no dots) + Currency
 *   3. Compare with the Signature field (base64).
 * See iPay88's "Signature generation" appendix in their integration guide.
 */
export class Ipay88Verifier implements Verifier {
  constructor(private readonly merchantKey: string) {}

  async verify(_formBody: URLSearchParams): Promise<Ipay88Payload> {
    // TODO: implement when sandbox creds arrive. Until then, instantiation of
    // this class itself throws so we never accidentally route production
    // traffic through an unverified path.
    throw new Error("Ipay88Verifier not implemented; use MockVerifier in dev");
  }
}

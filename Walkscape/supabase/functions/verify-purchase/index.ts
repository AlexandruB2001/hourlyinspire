// verify-purchase: the app sends each StoreKit 2 transaction it receives
// (the signed JWS, as is). We check Apple's signature and certificate chain
// with Apple's own library, check it belongs to the signed-in player, and
// record it in public.purchases. Clients can never write that table.
//
// Deploy with "Verify JWT" on: callers must be signed in.
// No secrets needed: Apple's root certificates are public.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@1";

const BUNDLE_ID = "com.alexandrub.walkscape";
const APP_APPLE_ID = 6827387213;
const ROOTS = [
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
];

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
let roots: Uint8Array[] | null = null;

async function appleRoots(): Promise<Uint8Array[]> {
  if (!roots) roots = await Promise.all(ROOTS.map(async (url) => new Uint8Array(await (await fetch(url)).arrayBuffer())));
  return roots;
}

// Tries production first, then the sandbox (TestFlight and Xcode purchases).
async function verifyTransaction(jws: string) {
  const certs = await appleRoots();
  for (const environment of [Environment.PRODUCTION, Environment.SANDBOX]) {
    try {
      const verifier = new SignedDataVerifier(certs, true, environment, BUNDLE_ID,
        environment === Environment.PRODUCTION ? APP_APPLE_ID : undefined);
      return await verifier.verifyAndDecodeTransaction(jws);
    } catch (_) {
      // Try the next environment.
    }
  }
  return null;
}

Deno.serve(async (request) => {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth } = await supabase.auth.getUser(token);
  const userID = auth.user?.id;
  if (!userID) return new Response("unauthorized", { status: 401 });

  const { signedTransaction } = await request.json().catch(() => ({}));
  if (typeof signedTransaction !== "string") return Response.json({ error: "missing transaction" }, { status: 400 });

  const transaction = await verifyTransaction(signedTransaction);
  if (!transaction?.originalTransactionId || !transaction.productId) {
    return Response.json({ error: "invalid transaction" }, { status: 400 });
  }
  // The app puts the player's account id in appAccountToken, so a purchase
  // can't be claimed by somebody else's account.
  if (transaction.appAccountToken && transaction.appAccountToken.toLowerCase() !== userID.toLowerCase()) {
    return Response.json({ error: "belongs to another account" }, { status: 403 });
  }

  const row = {
    original_transaction_id: transaction.originalTransactionId,
    user_id: userID,
    product_id: transaction.productId,
    environment: transaction.environment ?? "Sandbox",
    purchased_at: new Date(transaction.originalPurchaseDate ?? transaction.purchaseDate ?? Date.now()).toISOString(),
    expires_at: transaction.expiresDate ? new Date(transaction.expiresDate).toISOString() : null,
    revoked_at: transaction.revocationDate ? new Date(transaction.revocationDate).toISOString() : null,
    updated_at: new Date().toISOString(),
  };
  // A purchase already linked to another account stays with that account.
  const { data: existing } = await supabase.from("purchases").select("user_id")
    .eq("original_transaction_id", row.original_transaction_id).maybeSingle();
  if (existing && existing.user_id !== userID) {
    return Response.json({ error: "belongs to another account" }, { status: 403 });
  }
  const { error } = await supabase.from("purchases").upsert(row);
  if (error) return Response.json({ error: error.message }, { status: 500 });
  return Response.json({ ok: true, productId: row.product_id, expiresAt: row.expires_at });
});

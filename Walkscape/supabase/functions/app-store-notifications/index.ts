// app-store-notifications: Apple's App Store Server Notifications (V2).
// Apple calls this when a subscription renews, expires or is refunded, even
// if the player never opens the app. We verify Apple's signature and update
// public.purchases.
//
// Deploy with "Verify JWT" OFF (Apple doesn't send a Supabase token); every
// request is checked against Apple's certificate chain instead. Set this
// function's URL as the Production and Sandbox Server Notification URL in
// App Store Connect → App Information → App Store Server Notifications.

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

async function verifiers(): Promise<SignedDataVerifier[]> {
  if (!roots) roots = await Promise.all(ROOTS.map(async (url) => new Uint8Array(await (await fetch(url)).arrayBuffer())));
  return [
    new SignedDataVerifier(roots, true, Environment.PRODUCTION, BUNDLE_ID, APP_APPLE_ID),
    new SignedDataVerifier(roots, true, Environment.SANDBOX, BUNDLE_ID),
  ];
}

Deno.serve(async (request) => {
  const { signedPayload } = await request.json().catch(() => ({}));
  if (typeof signedPayload !== "string") return new Response("bad request", { status: 400 });

  for (const verifier of await verifiers()) {
    try {
      const notification = await verifier.verifyAndDecodeNotification(signedPayload);
      const signed = notification.data?.signedTransactionInfo;
      if (!signed) return Response.json({ ok: true, skipped: notification.notificationType });
      const transaction = await verifier.verifyAndDecodeTransaction(signed);
      if (!transaction.originalTransactionId) return Response.json({ ok: true });
      // Only purchases we already know (linked to an account by verify-purchase) are updated.
      await supabase.from("purchases").update({
        expires_at: transaction.expiresDate ? new Date(transaction.expiresDate).toISOString() : null,
        revoked_at: transaction.revocationDate ? new Date(transaction.revocationDate).toISOString() : null,
        updated_at: new Date().toISOString(),
      }).eq("original_transaction_id", transaction.originalTransactionId);
      return Response.json({ ok: true, type: notification.notificationType });
    } catch (_) {
      // Try the other environment.
    }
  }
  return new Response("invalid signature", { status: 401 });
});

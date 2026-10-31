// admob-ssv: AdMob server-side verification for rewarded ads. Google calls this
// URL (GET) after someone finishes a rewarded ad. We check Google's ECDSA
// signature over the query string and record the ad with record_ad_reward(),
// which pays the coins into the player's save (when verify_ad_rewards is on).
//
// The app sets the SSV user id to the player's Supabase user id and the custom
// data to the reward id it stores the coins under ("ad-<reward id>").
//
// Deploy with "Verify JWT" OFF: Google calls it without a Supabase token; the
// signature is the authentication. Then set this function's URL as the
// rewarded ad unit's server-side verification callback in AdMob.
// No secrets needed: Google's verifier keys are public.

import { createClient } from "jsr:@supabase/supabase-js@2";

const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const KEY_CACHE_MS = 6 * 60 * 60 * 1000;

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
let keys: Map<string, CryptoKey> | null = null;
let keysFetchedAt = 0;

function base64ToBytes(text: string): Uint8Array {
  const normal = text.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normal + "=".repeat((4 - (normal.length % 4)) % 4);
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
}

async function verifierKeys(refresh = false): Promise<Map<string, CryptoKey>> {
  if (keys && !refresh && Date.now() - keysFetchedAt < KEY_CACHE_MS) return keys;
  const body = await (await fetch(KEYS_URL)).json() as { keys: { keyId: number; base64: string }[] };
  const loaded = new Map<string, CryptoKey>();
  for (const key of body.keys) {
    loaded.set(String(key.keyId), await crypto.subtle.importKey(
      "spki", base64ToBytes(key.base64), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]));
  }
  keys = loaded;
  keysFetchedAt = Date.now();
  return loaded;
}

// Google signs with DER-encoded ECDSA; WebCrypto wants r || s (32 bytes each).
function derToRaw(der: Uint8Array): Uint8Array | null {
  if (der[0] !== 0x30) return null;
  let offset = der[1] & 0x80 ? 2 + (der[1] & 0x7f) : 2;
  const out = new Uint8Array(64);
  for (let part = 0; part < 2; part++) {
    if (der[offset] !== 0x02) return null;
    let length = der[offset + 1];
    let start = offset + 2;
    offset = start + length;
    while (length > 32 && der[start] === 0) {
      start++;
      length--;
    }
    if (length > 32) return null;
    out.set(der.subarray(start, start + length), part * 32 + (32 - length));
  }
  return out;
}

async function verify(query: string): Promise<boolean> {
  const at = query.indexOf("&signature=");
  if (at < 0) return false;
  const message = new TextEncoder().encode(query.slice(0, at));
  const params = new URLSearchParams(query.slice(at + 1));
  const signature = derToRaw(base64ToBytes(params.get("signature") ?? ""));
  const keyID = params.get("key_id") ?? "";
  if (!signature || !keyID) return false;
  let key = (await verifierKeys()).get(keyID);
  if (!key) key = (await verifierKeys(true)).get(keyID); // Google rotated its keys
  if (!key) return false;
  return await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, signature, message);
}

Deno.serve(async (request) => {
  if (request.method !== "GET") return new Response("method_not_allowed", { status: 405 });
  const query = new URL(request.url).search.replace(/^\?/, "");
  let valid = false;
  try {
    valid = await verify(query);
  } catch (_) {
    valid = false;
  }
  if (!valid) return new Response("invalid_signature", { status: 400 });

  const params = new URLSearchParams(query);
  const userID = params.get("user_id") ?? "";
  const rewardID = params.get("custom_data") ?? "";
  const transactionID = params.get("transaction_id") ?? "";
  // Google's "verify URL" test and ads shown before sign-in have no player:
  // accept them (so Google doesn't retry) but record nothing.
  if (!/^[0-9a-f-]{36}$/i.test(userID) || !rewardID) return new Response("ok", { status: 200 });

  const { data, error } = await supabase.rpc("record_ad_reward", {
    p_user: userID.toLowerCase(),
    p_transaction_id: transactionID,
    p_reward_id: rewardID,
    p_ad_unit: params.get("ad_unit") ?? "",
  });
  if (error) return new Response("error", { status: 500 }); // Google retries
  return new Response(String(data), { status: 200 });
});

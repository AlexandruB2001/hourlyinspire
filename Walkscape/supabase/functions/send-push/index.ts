// send-push: tells someone about a new friend request or team invite with an
// Apple push notification, so they hear about it with the app closed.
//
// Triggered by two Database Webhooks (Supabase dashboard → Database →
// Webhooks), both "INSERT" events pointing at this function:
//   * public.friendships   → notifies the addressee of a pending request
//   * public.team_invites  → notifies the invitee
// Each webhook sends the header `x-webhook-secret: <WEBHOOK_SECRET>`.
//
// Secrets (Edge Functions → Secrets):
//   WEBHOOK_SECRET     any long random string, also set on the webhooks
//   APNS_KEY_ID        Key ID of an Apple "Apple Push Notifications service" key
//   APNS_TEAM_ID       Apple Developer Team ID
//   APNS_PRIVATE_KEY   contents of that key's AuthKey_XXXX.p8
//   APNS_TOPIC         the app's bundle id (com.alexandrub.walkscape)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
//
// Only usernames and team names are sent; never walks, Health data or e-mail.

import { createClient } from "jsr:@supabase/supabase-js@2";

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: Record<string, unknown>;
};

type Push = { userID: string; title: string; body: string; destination: string; id: string };

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (request) => {
  if (request.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }
  const payload = (await request.json()) as WebhookPayload;
  if (payload.type !== "INSERT") return Response.json({ skipped: "not an insert" });

  const push = await describe(payload);
  if (!push) return Response.json({ skipped: "nothing to send" });

  const { data: tokens, error } = await supabase
    .from("push_tokens")
    .select("token, environment")
    .eq("user_id", push.userID)
    .eq("social", true);
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const jwt = await apnsToken();
  const results = await Promise.all((tokens ?? []).map((row) => send(row.token, row.environment, push, jwt)));
  return Response.json({ sent: results.filter((ok) => ok).length, of: results.length });
});

async function username(id: unknown): Promise<string> {
  const { data } = await supabase.from("profiles").select("username").eq("id", id).maybeSingle();
  return data?.username ?? "A friend";
}

async function describe({ table, record }: WebhookPayload): Promise<Push | null> {
  if (table === "friendships" && record.status === "pending") {
    return {
      userID: String(record.addressee_id),
      title: "New friend request",
      body: `@${await username(record.requester_id)} wants to walk with you.`,
      destination: "friends",
      id: `friend-request-${record.id}`,
    };
  }
  if (table === "team_invites") {
    const { data: team } = await supabase.from("teams").select("name").eq("id", record.team_id).maybeSingle();
    return {
      userID: String(record.invitee_id),
      title: "Team invite",
      body: `@${await username(record.inviter_id)} invited you to join ${team?.name ?? "their team"}.`,
      destination: "friends",
      id: `team-invite-${record.id}`,
    };
  }
  return null;
}

async function send(token: string, environment: string, push: Push, jwt: string): Promise<boolean> {
  const host = environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": Deno.env.get("APNS_TOPIC") ?? "com.alexandrub.walkscape",
      "apns-push-type": "alert",
      "apns-collapse-id": push.id.slice(0, 64),
    },
    body: JSON.stringify({
      aps: { alert: { title: push.title, body: push.body }, sound: "default", "thread-id": "social" },
      destination: push.destination,
      notificationID: push.id,
    }),
  });
  if (response.status === 410 || response.status === 400) {
    // The app was deleted or the token is stale: forget it.
    const reason = (await response.json().catch(() => ({}))).reason;
    if (response.status === 410 || reason === "BadDeviceToken") {
      await supabase.from("push_tokens").delete().eq("token", token);
    }
    return false;
  }
  return response.ok;
}

// APNs provider token: an ES256 JWT signed with the .p8 key, valid for an hour.
async function apnsToken(): Promise<string> {
  const pem = Deno.env.get("APNS_PRIVATE_KEY")!.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const encode = (value: object | Uint8Array) => {
    const bytes = value instanceof Uint8Array ? value : new TextEncoder().encode(JSON.stringify(value));
    return btoa(String.fromCharCode(...bytes)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  };
  const unsigned = `${encode({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") })}.${
    encode({ iss: Deno.env.get("APNS_TEAM_ID"), iat: Math.floor(Date.now() / 1000) })
  }`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${encode(new Uint8Array(signature))}`;
}

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Used by magic-link / OAuth flows. Not exercised by the Phase 1a email+password
// flow (which signs in synchronously), but required for future auth methods.
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = searchParams.get("next") ?? "/dashboard";

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(`${origin}${next}`);
  }
  return NextResponse.redirect(`${origin}/sign-in?error=auth_callback_failed`);
}

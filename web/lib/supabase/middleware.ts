import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Refresh the session. Cookies are updated on the response if refresh happens.
  // Do not remove this call — it's the only thing refreshing stale JWTs.
  const { data: { user } } = await supabase.auth.getUser();

  // Route-level auth gate: redirect unauthenticated users hitting a protected
  // route to /sign-in. Protected = anything that isn't public.
  const url = request.nextUrl.clone();
  const path = url.pathname;

  const publicRoutes = ["/", "/sign-in", "/sign-up", "/auth/callback"];
  const isPublic =
    publicRoutes.includes(path) ||
    path.startsWith("/_next") ||
    path.startsWith("/api/public");

  if (!user && !isPublic) {
    url.pathname = "/sign-in";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { BookingRequestCard, type BookingRequestView } from "@/components/booking-request-card";
import { InboxKpiStrip, type InboxKpis } from "@/components/inbox-kpi-strip";

export const dynamic = "force-dynamic";

export default async function InboxPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");

  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) redirect("/onboarding");

  const businessId = membership.business_id;

  // Pending requests with joined pets, owner, kennel, and cert presence
  const { data: requestsRaw, error: reqErr } = await supabase
    .from("bookings")
    .select(`
      id, check_in, check_out, nights, subtotal_myr, special_instructions, requested_at, owner_id,
      kennel_types!inner(name),
      booking_pets(pet_id),
      booking_cert_snapshots(id)
    `)
    .eq("business_id", businessId)
    .eq("status", "requested")
    .order("requested_at", { ascending: true });
  if (reqErr) throw new Error(reqErr.message);

  // Hydrate owner profiles + pets in batch
  const ownerIds = Array.from(new Set((requestsRaw ?? []).map((r) => r.owner_id)));
  const petIds = Array.from(
    new Set(
      (requestsRaw ?? []).flatMap((r) => (r.booking_pets as { pet_id: string }[]).map((bp) => bp.pet_id)),
    ),
  );

  const [{ data: profiles }, { data: pets }] = await Promise.all([
    ownerIds.length > 0
      ? supabase.from("user_profiles").select("id, display_name").in("id", ownerIds)
      : Promise.resolve({ data: [] as { id: string; display_name: string }[] }),
    petIds.length > 0
      ? supabase.from("pets").select("id, name, species, breed, weight_kg").in("id", petIds)
      : Promise.resolve({
          data: [] as {
            id: string; name: string; species: string; breed: string | null; weight_kg: string | null;
          }[],
        }),
  ]);

  const profileById = new Map((profiles ?? []).map((p) => [p.id, p.display_name]));
  const petById = new Map((pets ?? []).map((p) => [p.id, p]));

  const requests: BookingRequestView[] = (requestsRaw ?? []).map((r) => ({
    id: r.id,
    check_in: r.check_in,
    check_out: r.check_out,
    nights: r.nights,
    subtotal_myr: r.subtotal_myr,
    special_instructions: r.special_instructions,
    requested_at: r.requested_at,
    pets: (r.booking_pets as { pet_id: string }[]).flatMap((bp) => {
      const p = petById.get(bp.pet_id);
      return p ? [{ name: p.name, species: p.species, breed: p.breed, weight_kg: p.weight_kg }] : [];
    }),
    owner: { display_name: profileById.get(r.owner_id) ?? "Unknown" },
    kennel: { name: (r.kennel_types as unknown as { name: string }).name },
    cert_attached: (r.booking_cert_snapshots as unknown[]).length > 0,
  }));

  // KPIs
  const todayIso = new Date().toISOString().slice(0, 10);
  const weekStart = todayIso;
  const weekEnd = new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10);

  const [{ count: pendingCount }, { count: todayIn }, { count: todayOut }, { data: weekRows }] =
    await Promise.all([
      supabase
        .from("bookings")
        .select("id", { count: "exact", head: true })
        .eq("business_id", businessId)
        .eq("status", "requested"),
      supabase
        .from("bookings")
        .select("id", { count: "exact", head: true })
        .eq("business_id", businessId)
        .eq("status", "confirmed")
        .eq("check_in", todayIso),
      supabase
        .from("bookings")
        .select("id", { count: "exact", head: true })
        .eq("business_id", businessId)
        .eq("status", "confirmed")
        .eq("check_out", todayIso),
      supabase
        .from("bookings")
        .select("business_payout_myr, check_in")
        .eq("business_id", businessId)
        .in("status", ["confirmed", "completed"])
        .gte("check_in", weekStart)
        .lt("check_in", weekEnd),
    ]);

  const weekRevenue = (weekRows ?? []).reduce((sum, r) => sum + Number(r.business_payout_myr), 0);

  const kpis: InboxKpis = {
    pending: pendingCount ?? 0,
    todayCheckIn: todayIn ?? 0,
    todayCheckOut: todayOut ?? 0,
    weekRevenueMyr: weekRevenue,
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Inbox</h1>
        <p className="text-sm text-neutral-600 mt-1">
          Pending booking requests and today's activity.
        </p>
      </div>

      <InboxKpiStrip kpis={kpis} />

      <div className="space-y-4">
        <div className="text-[11px] uppercase tracking-wider text-neutral-500 font-semibold">
          Pending requests
        </div>
        {requests.length === 0 ? (
          <div className="rounded-md border border-dashed border-neutral-300 p-8 text-center text-sm text-neutral-500">
            No pending requests.
          </div>
        ) : (
          requests.map((r) => <BookingRequestCard key={r.id} req={r} />)
        )}
      </div>
    </div>
  );
}

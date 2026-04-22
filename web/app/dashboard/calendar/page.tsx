import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AvailabilityGrid, type CellMap, type KennelRow } from "@/components/availability-grid";

export const dynamic = "force-dynamic";

const WINDOW_DAYS = 14;

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}
function addDays(iso: string, n: number): string {
  const d = new Date(`${iso}T00:00:00`);
  d.setDate(d.getDate() + n);
  return isoDate(d);
}
function todayIso(): string {
  return isoDate(new Date());
}

export default async function CalendarPage({
  searchParams,
}: {
  searchParams: Promise<{ start?: string }>;
}) {
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

  const params = await searchParams;
  const startParam = params.start;
  const startDate = startParam && /^\d{4}-\d{2}-\d{2}$/.test(startParam) ? startParam : todayIso();
  const endDate = addDays(startDate, WINDOW_DAYS); // exclusive end

  const { data: listing } = await supabase
    .from("listings")
    .select("id")
    .eq("business_id", membership.business_id)
    .single();

  const { data: kennelsRaw } = await supabase
    .from("kennel_types")
    .select("id, name, capacity")
    .eq("listing_id", listing?.id ?? "")
    .eq("active", true)
    .order("created_at", { ascending: true });
  const kennels: KennelRow[] = (kennelsRaw ?? []) as KennelRow[];

  // Occupancy: count accepted/pending_payment/confirmed bookings overlapping each day.
  const kennelIds = kennels.map((k) => k.id);
  const [{ data: bookingsRaw }, { data: overridesRaw }] = await Promise.all([
    kennelIds.length > 0
      ? supabase
          .from("bookings")
          .select("kennel_type_id, check_in, check_out, status")
          .in("kennel_type_id", kennelIds)
          .in("status", ["accepted", "pending_payment", "confirmed"])
          .gte("check_out", startDate)
          .lte("check_in", endDate)
      : Promise.resolve({ data: [] as { kennel_type_id: string; check_in: string; check_out: string; status: string }[] }),
    kennelIds.length > 0
      ? supabase
          .from("availability_overrides")
          .select("kennel_type_id, date, manual_block")
          .in("kennel_type_id", kennelIds)
          .gte("date", startDate)
          .lt("date", endDate)
      : Promise.resolve({ data: [] as { kennel_type_id: string; date: string; manual_block: boolean }[] }),
  ]);

  // Build cells map
  const cells: CellMap = {};
  for (const b of bookingsRaw ?? []) {
    let cursor = b.check_in;
    while (cursor < b.check_out) {
      if (cursor >= startDate && cursor < endDate) {
        const key = `${b.kennel_type_id}|${cursor}`;
        const prev = cells[key] ?? { bookings: 0, manual_block: false };
        cells[key] = { ...prev, bookings: prev.bookings + 1 };
      }
      cursor = addDays(cursor, 1);
    }
  }
  for (const o of overridesRaw ?? []) {
    if (!o.manual_block) continue;
    const key = `${o.kennel_type_id}|${o.date}`;
    const prev = cells[key] ?? { bookings: 0, manual_block: false };
    cells[key] = { ...prev, manual_block: true };
  }

  const prevStart = addDays(startDate, -WINDOW_DAYS);
  const nextStart = addDays(startDate, WINDOW_DAYS);

  return (
    <div className="space-y-6 max-w-6xl">
      <div className="flex items-center justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Calendar</h1>
          <p className="text-sm text-neutral-600 mt-1">
            {startDate} → {addDays(endDate, -1)} · click an empty cell to block it
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href={`/dashboard/calendar?start=${prevStart}`}
            className="text-sm border border-neutral-200 rounded-md px-3 py-1.5 hover:bg-neutral-50"
          >
            ← Prev
          </Link>
          <Link
            href="/dashboard/calendar"
            className="text-sm border border-neutral-200 rounded-md px-3 py-1.5 hover:bg-neutral-50"
          >
            Today
          </Link>
          <Link
            href={`/dashboard/calendar?start=${nextStart}`}
            className="text-sm border border-neutral-200 rounded-md px-3 py-1.5 hover:bg-neutral-50"
          >
            Next →
          </Link>
        </div>
      </div>

      <div className="flex items-center gap-4 text-xs text-neutral-500 flex-wrap">
        <span className="inline-flex items-center gap-1">
          <span className="w-3 h-3 bg-white border border-neutral-200" /> Open
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="w-3 h-3 bg-amber-100 border border-amber-200" /> Some booked
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="w-3 h-3 bg-neutral-900 border border-neutral-900" /> Fully booked
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="w-3 h-3 bg-red-100 border border-red-200" /> Manual block
        </span>
      </div>

      {kennels.length === 0 ? (
        <div className="rounded-md border border-dashed border-neutral-300 p-8 text-center text-sm text-neutral-500">
          No active kennel types yet.{" "}
          <Link href="/dashboard/listing" className="underline">
            Add kennels
          </Link>
          .
        </div>
      ) : (
        <AvailabilityGrid kennels={kennels} startDate={startDate} days={WINDOW_DAYS} cells={cells} />
      )}
    </div>
  );
}

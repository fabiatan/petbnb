"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type CalendarActionState = { error?: string; ok?: true };

export async function toggleAvailabilityBlockAction(
  _prev: CalendarActionState,
  formData: FormData,
): Promise<CalendarActionState> {
  const kennelId = String(formData.get("kennel_type_id") ?? "");
  const date = String(formData.get("date") ?? "");

  if (!/^[0-9a-f-]{36}$/.test(kennelId)) return { error: "Invalid kennel id" };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return { error: "Invalid date" };

  const supabase = await createClient();

  // Guard: caller must belong to the kennel's business (RLS would catch this
  // but an explicit error is clearer than a silent 0-row response).
  const { data: kennel } = await supabase
    .from("kennel_types")
    .select("id, listings!inner(business_id)")
    .eq("id", kennelId)
    .maybeSingle();
  if (!kennel) return { error: "Kennel not found or not yours" };

  // Is there already a block row for this (kennel, date)?
  const { data: existing } = await supabase
    .from("availability_overrides")
    .select("id, manual_block")
    .eq("kennel_type_id", kennelId)
    .eq("date", date)
    .maybeSingle();

  if (existing) {
    const { error } = await supabase
      .from("availability_overrides")
      .delete()
      .eq("id", existing.id);
    if (error) return { error: error.message };
  } else {
    const { error } = await supabase.from("availability_overrides").insert({
      kennel_type_id: kennelId,
      date,
      manual_block: true,
    });
    if (error) return { error: error.message };
  }

  revalidatePath("/dashboard/calendar");
  return { ok: true };
}

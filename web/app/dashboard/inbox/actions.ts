"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export type InboxActionState = { error?: string; ok?: true };

export async function acceptBookingAction(
  _prev: InboxActionState,
  formData: FormData,
): Promise<InboxActionState> {
  const bookingId = String(formData.get("booking_id") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(bookingId)) return { error: "Invalid booking id" };

  const supabase = await createClient();
  const { error } = await supabase.rpc("accept_booking", { p_booking_id: bookingId });
  if (error) return { error: error.message };

  revalidatePath("/dashboard/inbox");
  revalidatePath("/dashboard", "layout");
  return { ok: true };
}

export async function declineBookingAction(
  _prev: InboxActionState,
  formData: FormData,
): Promise<InboxActionState> {
  const bookingId = String(formData.get("booking_id") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(bookingId)) return { error: "Invalid booking id" };
  const reason = (formData.get("reason") as string | null)?.trim() || null;

  const supabase = await createClient();
  const { error } = await supabase.rpc("decline_booking", {
    p_booking_id: bookingId,
    p_reason: reason,
  });
  if (error) return { error: error.message };

  revalidatePath("/dashboard/inbox");
  return { ok: true };
}

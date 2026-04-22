"use server";

import { revalidatePath } from "next/cache";
import { randomUUID } from "node:crypto";
import { createClient } from "@/lib/supabase/server";
import {
  ALLOWED_PHOTO_MIME,
  CANCELLATION_POLICIES,
  CancellationPolicy,
  listingPhotoPath,
  MAX_AMENITIES,
  MAX_AMENITY_LENGTH,
  MAX_PHOTO_BYTES,
  MAX_PHOTOS,
  validateKennelInput,
} from "@/lib/listing";

export type ActionState = { error?: string; ok?: true };

async function resolveContext(): Promise<
  | { kind: "ok"; businessId: string; listingId: string; userId: string }
  | { kind: "err"; error: string }
> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { kind: "err", error: "Not authenticated" };

  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) return { kind: "err", error: "No business membership" };

  const { data: listing } = await supabase
    .from("listings")
    .select("id")
    .eq("business_id", membership.business_id)
    .limit(1)
    .maybeSingle();
  if (!listing) return { kind: "err", error: "Listing not found for business" };

  return {
    kind: "ok",
    businessId: membership.business_id,
    listingId: listing.id,
    userId: user.id,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing info
// ─────────────────────────────────────────────────────────────────────────────

export async function updateListingInfoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const description = String(formData.get("description") ?? "").trim().slice(0, 2000) || null;
  const houseRules = String(formData.get("house_rules") ?? "").trim().slice(0, 2000) || null;
  const policyRaw = String(formData.get("cancellation_policy") ?? "moderate");
  if (!(CANCELLATION_POLICIES as readonly string[]).includes(policyRaw)) {
    return { error: "Invalid cancellation policy" };
  }
  const cancellationPolicy = policyRaw as CancellationPolicy;

  const amenitiesRaw = String(formData.get("amenities") ?? "").trim();
  const amenities = amenitiesRaw
    ? amenitiesRaw
        .split(",")
        .map((a) => a.trim())
        .filter((a) => a.length > 0 && a.length <= MAX_AMENITY_LENGTH)
        .slice(0, MAX_AMENITIES)
    : [];

  const supabase = await createClient();
  const { error } = await supabase
    .from("listings")
    .update({
      description,
      house_rules: houseRules,
      cancellation_policy: cancellationPolicy,
      amenities,
    })
    .eq("id", ctx.listingId);
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Photos
// ─────────────────────────────────────────────────────────────────────────────

async function readCurrentPhotos(listingId: string): Promise<string[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("listings")
    .select("photos")
    .eq("id", listingId)
    .single();
  return (data?.photos as string[] | null) ?? [];
}

export async function uploadListingPhotoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const files = formData.getAll("files").filter((f): f is File => f instanceof File && f.size > 0);
  if (files.length === 0) return { error: "Choose at least one photo" };

  const current = await readCurrentPhotos(ctx.listingId);
  if (current.length + files.length > MAX_PHOTOS) {
    return { error: `Max ${MAX_PHOTOS} photos (you have ${current.length})` };
  }

  for (const f of files) {
    if (f.size > MAX_PHOTO_BYTES) return { error: `${f.name} exceeds 5 MB` };
    if (!(ALLOWED_PHOTO_MIME as readonly string[]).includes(f.type)) {
      return { error: `${f.name}: only JPEG/PNG/WebP` };
    }
  }

  const supabase = await createClient();
  const newPaths: string[] = [];
  for (const f of files) {
    const path = listingPhotoPath(ctx.businessId, randomUUID(), f.name);
    const { error } = await supabase.storage
      .from("listing-photos")
      .upload(path, f, { contentType: f.type, upsert: false });
    if (error) return { error: `Upload failed: ${error.message}` };
    newPaths.push(path);
  }

  const nextPhotos = [...current, ...newPaths];
  const { error: updErr } = await supabase
    .from("listings")
    .update({ photos: nextPhotos })
    .eq("id", ctx.listingId);
  if (updErr) return { error: updErr.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

export async function removeListingPhotoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const path = String(formData.get("path") ?? "");
  if (!path) return { error: "path required" };

  const current = await readCurrentPhotos(ctx.listingId);
  if (!current.includes(path)) return { error: "Photo not found on this listing" };

  const supabase = await createClient();
  const { error: remErr } = await supabase.storage.from("listing-photos").remove([path]);
  if (remErr) return { error: `Storage remove failed: ${remErr.message}` };

  const nextPhotos = current.filter((p) => p !== path);
  const { error: updErr } = await supabase
    .from("listings")
    .update({ photos: nextPhotos })
    .eq("id", ctx.listingId);
  if (updErr) return { error: updErr.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

export async function reorderListingPhotoAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const path = String(formData.get("path") ?? "");
  const direction = String(formData.get("direction") ?? "");
  if (!path || (direction !== "up" && direction !== "down")) {
    return { error: "Invalid reorder request" };
  }

  const current = await readCurrentPhotos(ctx.listingId);
  const idx = current.indexOf(path);
  if (idx < 0) return { error: "Photo not found" };
  const targetIdx = direction === "up" ? idx - 1 : idx + 1;
  if (targetIdx < 0 || targetIdx >= current.length) return { ok: true }; // no-op at edge

  const next = [...current];
  [next[idx], next[targetIdx]] = [next[targetIdx], next[idx]];

  const supabase = await createClient();
  const { error } = await supabase
    .from("listings")
    .update({ photos: next })
    .eq("id", ctx.listingId);
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Kennels
// ─────────────────────────────────────────────────────────────────────────────

export async function createKennelAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const raw = Object.fromEntries(formData.entries());
  const parsed = validateKennelInput(raw);
  if (!parsed.ok) return { error: parsed.error };

  const supabase = await createClient();
  const { error } = await supabase.from("kennel_types").insert({
    listing_id: ctx.listingId,
    ...parsed.value,
  });
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

export async function updateKennelAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const id = String(formData.get("id") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(id)) return { error: "Invalid kennel id" };

  const raw = Object.fromEntries(formData.entries());
  const parsed = validateKennelInput(raw);
  if (!parsed.ok) return { error: parsed.error };

  const supabase = await createClient();

  // Guard: the kennel must belong to this business's listing
  const { data: kennel } = await supabase
    .from("kennel_types")
    .select("listing_id")
    .eq("id", id)
    .maybeSingle();
  if (!kennel || kennel.listing_id !== ctx.listingId) {
    return { error: "Kennel not found or not yours" };
  }

  const { error } = await supabase
    .from("kennel_types")
    .update(parsed.value)
    .eq("id", id);
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

export async function toggleKennelActiveAction(
  _prev: ActionState,
  formData: FormData,
): Promise<ActionState> {
  const ctx = await resolveContext();
  if (ctx.kind === "err") return { error: ctx.error };

  const id = String(formData.get("id") ?? "");
  if (!/^[0-9a-f-]{36}$/.test(id)) return { error: "Invalid kennel id" };

  const supabase = await createClient();
  const { data: kennel } = await supabase
    .from("kennel_types")
    .select("listing_id, active")
    .eq("id", id)
    .maybeSingle();
  if (!kennel || kennel.listing_id !== ctx.listingId) {
    return { error: "Kennel not found or not yours" };
  }

  const { error } = await supabase
    .from("kennel_types")
    .update({ active: !kennel.active })
    .eq("id", id);
  if (error) return { error: error.message };

  revalidatePath("/dashboard/listing");
  return { ok: true };
}

// Constants, types, and validators for listings and kennels.
// Framework-agnostic (no React, no Next imports).

export const CANCELLATION_POLICIES = ["flexible", "moderate", "strict"] as const;
export type CancellationPolicy = (typeof CANCELLATION_POLICIES)[number];
export const CANCELLATION_POLICY_LABELS: Record<CancellationPolicy, string> = {
  flexible: "Flexible — full refund up to 48h before check-in",
  moderate: "Moderate — full refund up to 7 days; then 50%",
  strict: "Strict — 50% up to 7 days; then 0%",
};

export const SPECIES_ACCEPTED = ["dog", "cat", "both"] as const;
export type SpeciesAccepted = (typeof SPECIES_ACCEPTED)[number];
export const SPECIES_ACCEPTED_LABELS: Record<SpeciesAccepted, string> = {
  dog: "Dogs only",
  cat: "Cats only",
  both: "Dogs and cats",
};

export const SIZE_RANGES = ["small", "medium", "large"] as const;
export type SizeRange = (typeof SIZE_RANGES)[number];
export const SIZE_RANGE_LABELS: Record<SizeRange, string> = {
  small: "Small (≤ 10 kg)",
  medium: "Medium (10–25 kg)",
  large: "Large (> 25 kg)",
};

export const MAX_PHOTOS = 12;
export const MAX_PHOTO_BYTES = 5 * 1024 * 1024; // 5 MiB
export const ALLOWED_PHOTO_MIME = ["image/jpeg", "image/png", "image/webp"] as const;

export const MAX_AMENITIES = 20;
export const MAX_AMENITY_LENGTH = 40;

// Server-side input validation for a kennel. Returns { ok: true, value } or
// { ok: false, error }. Used in server actions.
export type KennelFormInput = {
  name: string;
  species_accepted: SpeciesAccepted;
  size_range: SizeRange;
  capacity: number;
  base_price_myr: number;
  peak_price_myr: number;
  instant_book: boolean;
  description: string | null;
};

export function validateKennelInput(
  raw: Record<string, unknown>,
): { ok: true; value: KennelFormInput } | { ok: false; error: string } {
  const name = String(raw.name ?? "").trim();
  if (!name) return { ok: false, error: "Name is required" };
  if (name.length > 80) return { ok: false, error: "Name too long (max 80)" };

  const species = String(raw.species_accepted ?? "");
  if (!(SPECIES_ACCEPTED as readonly string[]).includes(species)) {
    return { ok: false, error: "Invalid species" };
  }

  const size = String(raw.size_range ?? "");
  if (!(SIZE_RANGES as readonly string[]).includes(size)) {
    return { ok: false, error: "Invalid size range" };
  }

  const capacity = Number(raw.capacity);
  if (!Number.isInteger(capacity) || capacity < 1 || capacity > 500) {
    return { ok: false, error: "Capacity must be an integer between 1 and 500" };
  }

  const base = Number(raw.base_price_myr);
  if (!Number.isFinite(base) || base < 0 || base > 99999) {
    return { ok: false, error: "Base price must be between 0 and 99999" };
  }
  const peak = Number(raw.peak_price_myr);
  if (!Number.isFinite(peak) || peak < 0 || peak > 99999) {
    return { ok: false, error: "Peak price must be between 0 and 99999" };
  }
  if (peak < base) {
    return { ok: false, error: "Peak price cannot be less than base price" };
  }

  const instant = raw.instant_book === "on" || raw.instant_book === true || raw.instant_book === "true";

  const description = raw.description ? String(raw.description).trim().slice(0, 500) : null;

  return {
    ok: true,
    value: {
      name,
      species_accepted: species as SpeciesAccepted,
      size_range: size as SizeRange,
      capacity,
      base_price_myr: base,
      peak_price_myr: peak,
      instant_book: instant,
      description,
    },
  };
}

export function listingPhotoPath(businessId: string, uniqueId: string, filename: string): string {
  const safeName = filename.replace(/[^A-Za-z0-9._-]+/g, "_").slice(0, 100);
  return `businesses/${businessId}/listing/${uniqueId}_${safeName}`;
}

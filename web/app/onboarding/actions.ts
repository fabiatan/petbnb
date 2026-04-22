"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type OnboardingFormState = { error?: string };

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60);
}

export async function createBusinessAction(
  _prev: OnboardingFormState,
  formData: FormData,
): Promise<OnboardingFormState> {
  const name = String(formData.get("name") ?? "").trim();
  const slugRaw = String(formData.get("slug") ?? "").trim();
  const address = String(formData.get("address") ?? "").trim();
  const city = String(formData.get("city") ?? "").trim();
  const state = String(formData.get("state") ?? "").trim();

  if (!name || !address || !city || !state) {
    return { error: "Name, address, city, and state are required." };
  }
  const slug = slugRaw || slugify(name);
  if (!/^[a-z0-9-]+$/.test(slug)) {
    return { error: "Slug must be lowercase letters, numbers, and hyphens only." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_business_onboarding", {
    p_name: name,
    p_slug: slug,
    p_address: address,
    p_city: city,
    p_state: state,
  });

  if (error) {
    if (error.code === "23505") {
      return { error: "That slug is already taken. Try another." };
    }
    return { error: error.message };
  }
  if (!data) return { error: "Onboarding did not return a business id." };

  revalidatePath("/", "layout");
  redirect("/dashboard");
}

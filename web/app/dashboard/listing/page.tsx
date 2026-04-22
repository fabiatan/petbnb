export const dynamic = "force-dynamic";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Separator } from "@/components/ui/separator";
import { ListingInfoForm } from "@/components/listing-info-form";
import { ListingPhotoGallery } from "@/components/listing-photo-gallery";
import { KennelList, type KennelRow } from "@/components/kennel-list";
import { CancellationPolicy } from "@/lib/listing";

export default async function ListingPage() {
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

  const { data: listing } = await supabase
    .from("listings")
    .select("id, description, amenities, house_rules, cancellation_policy, photos")
    .eq("business_id", membership.business_id)
    .single();

  const photoPaths: string[] = (listing?.photos as string[] | null) ?? [];
  const publicUrls: Record<string, string> = {};
  for (const p of photoPaths) {
    const { data } = supabase.storage.from("listing-photos").getPublicUrl(p);
    publicUrls[p] = data.publicUrl;
  }

  const { data: kennelsRaw } = await supabase
    .from("kennel_types")
    .select("id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book, description, active")
    .eq("listing_id", listing?.id ?? "")
    .order("created_at", { ascending: true });
  const kennels: KennelRow[] = (kennelsRaw ?? []) as KennelRow[];

  return (
    <div className="max-w-4xl space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Listing</h1>
        <p className="text-sm text-neutral-600 mt-1">
          Everything owners see when they view your business.
        </p>
      </div>

      <section>
        <h2 className="text-lg font-semibold">Info</h2>
        <p className="text-xs text-neutral-500 mt-0.5 mb-4">Description, amenities, house rules, cancellation policy.</p>
        <ListingInfoForm
          initialDescription={(listing?.description as string | null) ?? null}
          initialHouseRules={(listing?.house_rules as string | null) ?? null}
          initialAmenities={(listing?.amenities as string[] | null) ?? []}
          initialCancellationPolicy={
            (listing?.cancellation_policy as CancellationPolicy | null) ?? "moderate"
          }
        />
      </section>

      <Separator />

      <section>
        <h2 className="text-lg font-semibold">Photos</h2>
        <p className="text-xs text-neutral-500 mt-0.5 mb-4">Up to 12 photos. First photo is the hero image.</p>
        <ListingPhotoGallery photoPaths={photoPaths} publicUrls={publicUrls} />
      </section>

      <Separator />

      <section>
        <h2 className="text-lg font-semibold">Kennel types</h2>
        <p className="text-xs text-neutral-500 mt-0.5 mb-4">
          The bookable units inside your listing. Each kennel type has its own pricing, capacity, and acceptance rules.
        </p>
        <KennelList kennels={kennels} />
      </section>
    </div>
  );
}

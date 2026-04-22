import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { isKycComplete, KycDocuments } from "@/lib/kyc";

export async function KycBanner() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: membership } = await supabase
    .from("business_members")
    .select("businesses!inner(kyc_status, kyc_documents)")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) return null;

  const biz = membership.businesses as unknown as {
    kyc_status: "pending" | "verified" | "rejected";
    kyc_documents: KycDocuments | null;
  };
  if (biz.kyc_status === "verified") return null;

  const docs = biz.kyc_documents ?? {};
  const complete = isKycComplete(docs);

  if (biz.kyc_status === "rejected") {
    return (
      <div className="border-b border-red-200 bg-red-50 px-6 py-3 text-sm flex items-center justify-between gap-4">
        <span className="text-red-900">
          <strong>KYC rejected.</strong> Please review notes and re-upload documents.
        </span>
        <Link
          href="/dashboard/settings/kyc"
          className="text-red-900 underline font-medium whitespace-nowrap"
        >
          Update documents
        </Link>
      </div>
    );
  }

  if (complete) {
    return (
      <div className="border-b border-amber-200 bg-amber-50 px-6 py-3 text-sm flex items-center gap-4">
        <span className="text-amber-900">
          <strong>KYC under review.</strong> We'll email you within 48 hours.
        </span>
      </div>
    );
  }

  return (
    <div className="border-b border-neutral-900 bg-neutral-900 text-white px-6 py-3 text-sm flex items-center justify-between gap-4">
      <span>
        <strong>Upload KYC documents</strong> to activate your listing.
      </span>
      <Link
        href="/dashboard/settings/kyc"
        className="underline font-medium whitespace-nowrap"
      >
        Upload now
      </Link>
    </div>
  );
}

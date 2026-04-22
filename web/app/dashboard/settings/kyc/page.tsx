import { redirect } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { KYC_DOC_TYPES, KycDocuments, isKycComplete } from "@/lib/kyc";
import { KycDocumentCard } from "@/components/kyc-document-card";

export default async function KycPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in");

  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id, businesses!inner(kyc_status, kyc_documents)")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (!membership) redirect("/onboarding");

  const biz = membership.businesses as unknown as {
    kyc_status: "pending" | "verified" | "rejected";
    kyc_documents: KycDocuments | null;
  };
  const docs: KycDocuments = biz.kyc_documents ?? {};
  const complete = isKycComplete(docs);

  return (
    <div className="max-w-3xl">
      <div className="mb-2">
        <Link href="/dashboard/settings" className="text-xs text-neutral-500 hover:underline">
          ← Settings
        </Link>
      </div>
      <h1 className="text-2xl font-bold tracking-tight">KYC documents</h1>
      <p className="text-sm text-neutral-600 mt-1">
        Upload the four documents below so we can verify your business. You can replace a file at any time.
      </p>

      <div className="mt-6 space-y-4">
        {KYC_DOC_TYPES.map((docType) => (
          <KycDocumentCard key={docType} docType={docType} entry={docs[docType]} />
        ))}
      </div>

      <div className="mt-8 text-xs text-neutral-500">
        Status: <strong className="text-neutral-900">{biz.kyc_status}</strong>
        {complete && biz.kyc_status === "pending"
          ? " — all documents uploaded. Our team will review within 48 hours."
          : null}
      </div>
    </div>
  );
}

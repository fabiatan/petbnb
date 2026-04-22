// Shared KYC constants used by server actions, UI, and validation.
// Keep this file framework-agnostic — no React, no Next imports — so it can
// be pulled into Edge Functions or workers later without pulling in a renderer.

export const KYC_DOC_TYPES = [
  "ssm_cert",
  "business_license",
  "proof_of_premises",
  "owner_ic",
] as const;

export type KycDocType = (typeof KYC_DOC_TYPES)[number];

export const KYC_DOC_LABELS: Record<KycDocType, string> = {
  ssm_cert: "SSM registration certificate",
  business_license: "Business operating license",
  proof_of_premises: "Proof of premises (tenancy / ownership)",
  owner_ic: "Owner / director MyKad (IC)",
};

export const KYC_DOC_DESCRIPTIONS: Record<KycDocType, string> = {
  ssm_cert: "Form D/E from SSM, or Super Form for Sdn Bhd.",
  business_license:
    "Local council license authorising your pet boarding operation.",
  proof_of_premises:
    "Tenancy agreement, utility bill, or title deed showing your registered address.",
  owner_ic:
    "Front + back photo of the owner's MyKad, merged into a single PDF or image.",
};

export const KYC_MAX_FILE_BYTES = 10 * 1024 * 1024; // 10 MiB

export const KYC_ALLOWED_MIME = [
  "application/pdf",
  "image/jpeg",
  "image/png",
] as const;

// Shape of businesses.kyc_documents jsonb.
// Each doc, when uploaded, carries: storage path, upload timestamp,
// original filename, content type, and byte size.
export type KycDocEntry = {
  path: string;          // e.g. "businesses/<uuid>/ssm_cert/cert.pdf"
  uploaded_at: string;   // ISO 8601
  filename: string;      // original (client-supplied) filename
  content_type: string;  // verified MIME
  size_bytes: number;
};

export type KycDocuments = Partial<Record<KycDocType, KycDocEntry>>;

export function isKycComplete(docs: KycDocuments): boolean {
  return KYC_DOC_TYPES.every((t) => Boolean(docs[t]?.path));
}

export function storagePath(businessId: string, docType: KycDocType, filename: string): string {
  // Normalise filename to avoid path traversal / weird chars.
  const safeName = filename.replace(/[^A-Za-z0-9._-]+/g, "_").slice(0, 120);
  return `businesses/${businessId}/${docType}/${safeName}`;
}

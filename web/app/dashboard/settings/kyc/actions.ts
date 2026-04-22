"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import {
  KYC_ALLOWED_MIME,
  KYC_DOC_TYPES,
  KYC_MAX_FILE_BYTES,
  KycDocEntry,
  KycDocType,
  KycDocuments,
  storagePath,
} from "@/lib/kyc";

export type KycActionState = { error?: string; uploadedDocType?: KycDocType };

async function resolveBusinessId(): Promise<
  | { kind: "ok"; businessId: string; userId: string }
  | { kind: "err"; error: string }
> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { kind: "err", error: "Not authenticated" };

  const { data: membership, error } = await supabase
    .from("business_members")
    .select("business_id")
    .eq("user_id", user.id)
    .limit(1)
    .maybeSingle();
  if (error) return { kind: "err", error: error.message };
  if (!membership) return { kind: "err", error: "No business membership" };

  return { kind: "ok", businessId: membership.business_id, userId: user.id };
}

export async function uploadKycDocumentAction(
  _prev: KycActionState,
  formData: FormData,
): Promise<KycActionState> {
  const docTypeRaw = String(formData.get("docType") ?? "");
  const file = formData.get("file");

  if (!KYC_DOC_TYPES.includes(docTypeRaw as KycDocType)) {
    return { error: `Invalid document type: ${docTypeRaw}` };
  }
  const docType = docTypeRaw as KycDocType;

  if (!(file instanceof File) || file.size === 0) {
    return { error: "Please choose a file." };
  }
  if (file.size > KYC_MAX_FILE_BYTES) {
    return { error: "File exceeds 10 MB." };
  }
  if (!(KYC_ALLOWED_MIME as readonly string[]).includes(file.type)) {
    return { error: "Only PDF, JPEG, or PNG files are accepted." };
  }

  const ctx = await resolveBusinessId();
  if (ctx.kind === "err") return { error: ctx.error };

  const supabase = await createClient();
  const path = storagePath(ctx.businessId, docType, file.name);

  // Remove any existing file at the same docType (replace semantics)
  const { data: biz, error: bizReadError } = await supabase
    .from("businesses")
    .select("kyc_documents")
    .eq("id", ctx.businessId)
    .single();
  if (bizReadError) return { error: bizReadError.message };

  const docs = (biz?.kyc_documents ?? {}) as KycDocuments;
  const prior = docs[docType];
  if (prior?.path && prior.path !== path) {
    const { error: removeErr } = await supabase.storage
      .from("kyc-documents")
      .remove([prior.path]);
    if (removeErr) return { error: `Failed to remove prior file: ${removeErr.message}` };
  }

  const { error: uploadErr } = await supabase.storage
    .from("kyc-documents")
    .upload(path, file, { upsert: true, contentType: file.type });
  if (uploadErr) return { error: `Upload failed: ${uploadErr.message}` };

  const entry: KycDocEntry = {
    path,
    uploaded_at: new Date().toISOString(),
    filename: file.name,
    content_type: file.type,
    size_bytes: file.size,
  };
  const nextDocs: KycDocuments = { ...docs, [docType]: entry };

  const { error: updateErr } = await supabase
    .from("businesses")
    .update({ kyc_documents: nextDocs })
    .eq("id", ctx.businessId);
  if (updateErr) return { error: `Metadata update failed: ${updateErr.message}` };

  revalidatePath("/dashboard/settings/kyc");
  revalidatePath("/dashboard", "layout");
  return { uploadedDocType: docType };
}

export async function removeKycDocumentAction(
  _prev: KycActionState,
  formData: FormData,
): Promise<KycActionState> {
  const docTypeRaw = String(formData.get("docType") ?? "");
  if (!KYC_DOC_TYPES.includes(docTypeRaw as KycDocType)) {
    return { error: `Invalid document type: ${docTypeRaw}` };
  }
  const docType = docTypeRaw as KycDocType;

  const ctx = await resolveBusinessId();
  if (ctx.kind === "err") return { error: ctx.error };

  const supabase = await createClient();

  const { data: biz, error: bizReadError } = await supabase
    .from("businesses")
    .select("kyc_documents")
    .eq("id", ctx.businessId)
    .single();
  if (bizReadError) return { error: bizReadError.message };

  const docs = (biz?.kyc_documents ?? {}) as KycDocuments;
  const prior = docs[docType];
  if (!prior) return {}; // nothing to remove; silent no-op

  const { error: removeErr } = await supabase.storage
    .from("kyc-documents")
    .remove([prior.path]);
  if (removeErr) return { error: `Storage remove failed: ${removeErr.message}` };

  const nextDocs: KycDocuments = { ...docs };
  delete nextDocs[docType];

  const { error: updateErr } = await supabase
    .from("businesses")
    .update({ kyc_documents: nextDocs })
    .eq("id", ctx.businessId);
  if (updateErr) return { error: `Metadata update failed: ${updateErr.message}` };

  revalidatePath("/dashboard/settings/kyc");
  revalidatePath("/dashboard", "layout");
  return {};
}

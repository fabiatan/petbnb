"use client";

import { useActionState, useRef } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  KYC_ALLOWED_MIME,
  KYC_DOC_DESCRIPTIONS,
  KYC_DOC_LABELS,
  KycDocEntry,
  KycDocType,
} from "@/lib/kyc";
import {
  removeKycDocumentAction,
  uploadKycDocumentAction,
  type KycActionState,
} from "@/app/dashboard/settings/kyc/actions";

function formatBytes(b: number): string {
  if (b < 1024) return `${b} B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(0)} KB`;
  return `${(b / 1024 / 1024).toFixed(1)} MB`;
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleString("en-MY", { dateStyle: "medium", timeStyle: "short" });
}

export function KycDocumentCard({
  docType,
  entry,
}: {
  docType: KycDocType;
  entry: KycDocEntry | undefined;
}) {
  const formRef = useRef<HTMLFormElement>(null);
  const [uploadState, uploadAction, uploadPending] = useActionState<KycActionState, FormData>(
    uploadKycDocumentAction,
    {},
  );
  const [removeState, removeAction, removePending] = useActionState<KycActionState, FormData>(
    removeKycDocumentAction,
    {},
  );

  const hasFile = !!entry;

  return (
    <Card className="border-neutral-200">
      <CardContent className="p-5 space-y-3">
        <div>
          <h3 className="font-semibold text-base">{KYC_DOC_LABELS[docType]}</h3>
          <p className="text-xs text-neutral-500 mt-1">{KYC_DOC_DESCRIPTIONS[docType]}</p>
        </div>

        {hasFile ? (
          <div className="rounded-md bg-emerald-50 border border-emerald-200 px-3 py-2 text-xs">
            <div className="font-medium text-emerald-900">{entry.filename}</div>
            <div className="text-emerald-700 mt-0.5">
              {formatBytes(entry.size_bytes)} · uploaded {formatDate(entry.uploaded_at)}
            </div>
          </div>
        ) : (
          <div className="rounded-md border border-dashed border-neutral-300 px-3 py-2 text-xs text-neutral-500">
            No file uploaded yet.
          </div>
        )}

        <form
          ref={formRef}
          action={uploadAction}
          className="flex items-center gap-2 flex-wrap"
          encType="multipart/form-data"
        >
          <input type="hidden" name="docType" value={docType} />
          <input
            type="file"
            name="file"
            accept={KYC_ALLOWED_MIME.join(",")}
            required
            className="text-xs file:mr-3 file:rounded-md file:border-0 file:bg-neutral-900 file:text-white file:px-3 file:py-1.5 file:text-xs file:cursor-pointer"
          />
          <Button type="submit" size="sm" disabled={uploadPending}>
            {uploadPending ? "Uploading…" : hasFile ? "Replace" : "Upload"}
          </Button>
          {hasFile ? (
            <Button
              type="button"
              size="sm"
              variant="outline"
              disabled={removePending}
              onClick={() => {
                const fd = new FormData();
                fd.append("docType", docType);
                removeAction(fd);
              }}
            >
              {removePending ? "Removing…" : "Remove"}
            </Button>
          ) : null}
        </form>

        {uploadState.error ? (
          <p className="text-xs text-red-600">{uploadState.error}</p>
        ) : null}
        {removeState.error ? (
          <p className="text-xs text-red-600">{removeState.error}</p>
        ) : null}
      </CardContent>
    </Card>
  );
}

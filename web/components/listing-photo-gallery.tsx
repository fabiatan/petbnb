"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useActionState } from "react";
import Image from "next/image";
import { Button } from "@/components/ui/button";
import { ALLOWED_PHOTO_MIME, MAX_PHOTOS } from "@/lib/listing";
import {
  removeListingPhotoAction,
  reorderListingPhotoAction,
  uploadListingPhotoAction,
  type ActionState,
} from "@/app/dashboard/listing/actions";

export function ListingPhotoGallery({
  photoPaths,
  publicUrls,
}: {
  photoPaths: string[];
  publicUrls: Record<string, string>; // path -> publicUrl
}) {
  const router = useRouter();
  const [uploadState, uploadAction, uploadPending] = useActionState<ActionState, FormData>(
    uploadListingPhotoAction,
    {},
  );
  const [removeState, removeAction, removePending] = useActionState<ActionState, FormData>(
    removeListingPhotoAction,
    {},
  );
  const [reorderState, reorderAction, reorderPending] = useActionState<ActionState, FormData>(
    reorderListingPhotoAction,
    {},
  );

  // After any mutating action succeeds, force a full server re-fetch so the
  // page shows the latest photoPaths (revalidatePath alone is insufficient
  // when the re-render happens inside the same server-action request context).
  useEffect(() => {
    if (uploadState.ok || removeState.ok || reorderState.ok) {
      router.refresh();
    }
  }, [uploadState.ok, removeState.ok, reorderState.ok, router]);

  const errorMsg = uploadState.error ?? removeState.error ?? reorderState.error;
  const canUpload = photoPaths.length < MAX_PHOTOS;

  return (
    <div className="space-y-4">
      {canUpload ? (
        <form action={uploadAction} className="flex items-center gap-2">
          <input
            type="file"
            name="files"
            multiple
            accept={ALLOWED_PHOTO_MIME.join(",")}
            required
            className="text-xs file:mr-3 file:rounded-md file:border-0 file:bg-neutral-900 file:text-white file:px-3 file:py-1.5 file:text-xs file:cursor-pointer"
          />
          <Button type="submit" size="sm" disabled={uploadPending}>
            {uploadPending ? "Uploading…" : "Upload"}
          </Button>
          <span className="text-xs text-neutral-500">
            {photoPaths.length}/{MAX_PHOTOS} · JPEG/PNG/WebP, ≤ 5 MB each
          </span>
        </form>
      ) : (
        <p className="text-xs text-neutral-500">Maximum {MAX_PHOTOS} photos reached. Remove one to upload more.</p>
      )}

      {errorMsg ? <p className="text-sm text-red-600">{errorMsg}</p> : null}

      {photoPaths.length === 0 ? (
        <div className="rounded-md border border-dashed border-neutral-300 px-4 py-8 text-center text-sm text-neutral-500">
          No photos yet.
        </div>
      ) : (
        <ul className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          {photoPaths.map((path, idx) => {
            const url = publicUrls[path] ?? "";
            return (
              <li key={path} className="relative group border border-neutral-200 rounded-md overflow-hidden bg-neutral-50">
                <div className="relative aspect-video">
                  {url ? (
                    <Image
                      src={url}
                      alt={`Listing photo ${idx + 1}`}
                      fill
                      className="object-cover"
                      sizes="(max-width: 768px) 50vw, 33vw"
                      unoptimized
                    />
                  ) : null}
                </div>
                <div className="flex items-center gap-1 p-2 bg-white border-t border-neutral-200">
                  <form action={reorderAction}>
                    <input type="hidden" name="path" value={path} />
                    <input type="hidden" name="direction" value="up" />
                    <Button size="sm" variant="outline" type="submit" disabled={reorderPending || idx === 0}>
                      ↑
                    </Button>
                  </form>
                  <form action={reorderAction}>
                    <input type="hidden" name="path" value={path} />
                    <input type="hidden" name="direction" value="down" />
                    <Button
                      size="sm"
                      variant="outline"
                      type="submit"
                      disabled={reorderPending || idx === photoPaths.length - 1}
                    >
                      ↓
                    </Button>
                  </form>
                  <form action={removeAction} className="ml-auto">
                    <input type="hidden" name="path" value={path} />
                    <Button size="sm" variant="outline" type="submit" disabled={removePending}>
                      Remove
                    </Button>
                  </form>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

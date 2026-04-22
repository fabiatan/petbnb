"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  acceptBookingAction,
  declineBookingAction,
  type InboxActionState,
} from "@/app/dashboard/inbox/actions";

export type BookingRequestView = {
  id: string;
  check_in: string;
  check_out: string;
  nights: number;
  subtotal_myr: string;
  special_instructions: string | null;
  requested_at: string;
  pets: { name: string; species: string; breed: string | null; weight_kg: string | null }[];
  owner: { display_name: string };
  kennel: { name: string };
  cert_attached: boolean;
};

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString("en-MY", { day: "numeric", month: "short" });
}

function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-MY", { dateStyle: "medium", timeStyle: "short" });
}

export function BookingRequestCard({ req }: { req: BookingRequestView }) {
  const router = useRouter();
  const [acceptState, acceptAction, acceptPending] = useActionState<InboxActionState, FormData>(
    acceptBookingAction,
    {},
  );
  const [declineState, declineAction, declinePending] = useActionState<InboxActionState, FormData>(
    declineBookingAction,
    {},
  );

  useEffect(() => {
    if (acceptState.ok || declineState.ok) router.refresh();
  }, [acceptState.ok, declineState.ok, router]);

  const error = acceptState.error ?? declineState.error;
  const pending = acceptPending || declinePending;

  return (
    <Card className="border-neutral-200">
      <CardContent className="p-5 space-y-3">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h3 className="font-semibold">{req.kennel.name}</h3>
            <p className="text-xs text-neutral-500">
              {formatDate(req.check_in)} → {formatDate(req.check_out)} · {req.nights} night{req.nights === 1 ? "" : "s"} · RM{Number(req.subtotal_myr).toFixed(2)}
            </p>
            <p className="text-xs text-neutral-500 mt-0.5">
              Owner: <strong className="text-neutral-900">{req.owner.display_name}</strong> · requested {formatDateTime(req.requested_at)}
            </p>
          </div>
          {req.cert_attached ? (
            <span className="text-xs text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-md px-2 py-1">
              Vaccination cert attached
            </span>
          ) : (
            <span className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-md px-2 py-1">
              No cert on file
            </span>
          )}
        </div>

        <div className="rounded-md bg-neutral-50 border border-neutral-200 px-3 py-2 text-xs">
          <div className="font-medium text-neutral-900 mb-1">Pets</div>
          <ul className="space-y-0.5">
            {req.pets.map((p, i) => (
              <li key={i} className="text-neutral-700">
                {p.name}
                {p.breed ? ` · ${p.breed}` : ""}
                {p.weight_kg ? ` · ${Number(p.weight_kg).toFixed(1)} kg` : ""}
              </li>
            ))}
          </ul>
        </div>

        {req.special_instructions ? (
          <div className="rounded-md bg-neutral-50 border border-neutral-200 px-3 py-2 text-xs">
            <div className="font-medium text-neutral-900 mb-1">Notes from owner</div>
            <p className="text-neutral-700 whitespace-pre-wrap">{req.special_instructions}</p>
          </div>
        ) : null}

        {error ? <p className="text-sm text-red-600">{error}</p> : null}

        <div className="flex gap-2 justify-end pt-2">
          <form action={declineAction}>
            <input type="hidden" name="booking_id" value={req.id} />
            <Button type="submit" variant="outline" size="sm" disabled={pending}>
              {declinePending ? "Declining…" : "Decline"}
            </Button>
          </form>
          <form action={acceptAction}>
            <input type="hidden" name="booking_id" value={req.id} />
            <Button type="submit" size="sm" disabled={pending}>
              {acceptPending ? "Accepting…" : "Accept"}
            </Button>
          </form>
        </div>
      </CardContent>
    </Card>
  );
}

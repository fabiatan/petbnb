"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  CANCELLATION_POLICIES,
  CANCELLATION_POLICY_LABELS,
  CancellationPolicy,
} from "@/lib/listing";
import { updateListingInfoAction, type ActionState } from "@/app/dashboard/listing/actions";

export function ListingInfoForm({
  initialDescription,
  initialHouseRules,
  initialAmenities,
  initialCancellationPolicy,
}: {
  initialDescription: string | null;
  initialHouseRules: string | null;
  initialAmenities: string[];
  initialCancellationPolicy: CancellationPolicy;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(
    updateListingInfoAction,
    {},
  );

  return (
    <form action={action} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="description">Description</Label>
        <Textarea
          id="description"
          name="description"
          rows={5}
          defaultValue={initialDescription ?? ""}
          placeholder="Air-conditioned kennels, daily walks, live CCTV for owners…"
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor="amenities">Amenities (comma-separated)</Label>
        <Input
          id="amenities"
          name="amenities"
          defaultValue={initialAmenities.join(", ")}
          placeholder="air_con, daily_walks, cctv"
        />
        <p className="text-xs text-neutral-500">Up to 20 items, 40 characters each.</p>
      </div>

      <div className="space-y-2">
        <Label htmlFor="house_rules">House rules</Label>
        <Textarea
          id="house_rules"
          name="house_rules"
          rows={3}
          defaultValue={initialHouseRules ?? ""}
          placeholder="No aggressive dogs. Vaccination required."
        />
      </div>

      <div className="space-y-2">
        <Label>Cancellation policy</Label>
        <Select name="cancellation_policy" defaultValue={initialCancellationPolicy}>
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {CANCELLATION_POLICIES.map((p) => (
              <SelectItem key={p} value={p}>
                {CANCELLATION_POLICY_LABELS[p]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
      {state.ok ? <p className="text-sm text-emerald-600">Saved.</p> : null}

      <Button type="submit" disabled={pending}>
        {pending ? "Saving…" : "Save listing info"}
      </Button>
    </form>
  );
}

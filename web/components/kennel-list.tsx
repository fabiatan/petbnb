"use client";

import { useActionState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  KennelEditorDialog,
  type KennelInitial,
} from "@/components/kennel-editor-dialog";
import { SIZE_RANGE_LABELS, SPECIES_ACCEPTED_LABELS, SizeRange, SpeciesAccepted } from "@/lib/listing";
import { toggleKennelActiveAction, type ActionState } from "@/app/dashboard/listing/actions";

export type KennelRow = {
  id: string;
  name: string;
  species_accepted: SpeciesAccepted;
  size_range: SizeRange;
  capacity: number;
  base_price_myr: string;
  peak_price_myr: string;
  instant_book: boolean;
  description: string | null;
  active: boolean;
};

function toInitial(row: KennelRow): KennelInitial {
  return {
    id: row.id,
    name: row.name,
    species_accepted: row.species_accepted,
    size_range: row.size_range,
    capacity: row.capacity,
    base_price_myr: row.base_price_myr,
    peak_price_myr: row.peak_price_myr,
    instant_book: row.instant_book,
    description: row.description ?? "",
  };
}

export function KennelList({ kennels }: { kennels: KennelRow[] }) {
  const blankInitial: KennelInitial = {
    name: "",
    species_accepted: "dog",
    size_range: "small",
    capacity: 1,
    base_price_myr: "0",
    peak_price_myr: "0",
    instant_book: false,
    description: "",
  };
  const [toggleState, toggleAction, togglePending] = useActionState<ActionState, FormData>(
    toggleKennelActiveAction,
    {},
  );

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-neutral-600">
          {kennels.length === 0 ? "No kennels yet." : `${kennels.length} kennel type${kennels.length === 1 ? "" : "s"}`}
        </p>
        <KennelEditorDialog
          trigger={<Button size="sm">Add kennel</Button>}
          title="Add kennel"
          initial={blankInitial}
          mode="create"
        />
      </div>

      {toggleState.error ? <p className="text-sm text-red-600">{toggleState.error}</p> : null}

      {kennels.map((k) => (
        <Card key={k.id} className={k.active ? "border-neutral-200" : "border-neutral-200 opacity-60"}>
          <CardContent className="p-4 flex items-start gap-4 flex-wrap">
            <div className="flex-1 min-w-[240px]">
              <div className="flex items-center gap-2 flex-wrap">
                <h3 className="font-semibold">{k.name}</h3>
                {k.instant_book ? <Badge className="bg-emerald-600">Instant book</Badge> : null}
                {!k.active ? <Badge variant="outline">Inactive</Badge> : null}
              </div>
              <p className="text-xs text-neutral-500 mt-1">
                {SPECIES_ACCEPTED_LABELS[k.species_accepted]} · {SIZE_RANGE_LABELS[k.size_range]} · capacity {k.capacity}
              </p>
              <p className="text-xs text-neutral-500 mt-0.5">
                Base RM{Number(k.base_price_myr).toFixed(2)} · Peak RM{Number(k.peak_price_myr).toFixed(2)}
              </p>
              {k.description ? (
                <p className="text-xs text-neutral-600 mt-2">{k.description}</p>
              ) : null}
            </div>
            <div className="flex gap-2">
              <KennelEditorDialog
                trigger={<Button size="sm" variant="outline">Edit</Button>}
                title={`Edit ${k.name}`}
                initial={toInitial(k)}
                mode="edit"
              />
              <form action={toggleAction}>
                <input type="hidden" name="id" value={k.id} />
                <Button size="sm" variant="outline" type="submit" disabled={togglePending}>
                  {k.active ? "Deactivate" : "Activate"}
                </Button>
              </form>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

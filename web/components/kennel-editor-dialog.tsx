"use client";

import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  SIZE_RANGES,
  SIZE_RANGE_LABELS,
  SPECIES_ACCEPTED,
  SPECIES_ACCEPTED_LABELS,
  SizeRange,
  SpeciesAccepted,
} from "@/lib/listing";
import {
  createKennelAction,
  updateKennelAction,
  type ActionState,
} from "@/app/dashboard/listing/actions";

export type KennelInitial = {
  id?: string;
  name: string;
  species_accepted: SpeciesAccepted;
  size_range: SizeRange;
  capacity: number;
  base_price_myr: string;
  peak_price_myr: string;
  instant_book: boolean;
  description: string;
};

export function KennelEditorDialog({
  trigger,
  title,
  initial,
  mode,
}: {
  trigger: React.ReactElement;
  title: string;
  initial: KennelInitial;
  mode: "create" | "edit";
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const action = mode === "create" ? createKennelAction : updateKennelAction;
  const [state, submit, pending] = useActionState<ActionState, FormData>(action, {});

  // Close the dialog when the action succeeds
  if (state.ok && open) {
    queueMicrotask(() => setOpen(false));
  }

  // Force a full server re-fetch after create/edit so the kennel list shows
  // the latest data (revalidatePath alone is insufficient in the same request context).
  useEffect(() => {
    if (state.ok) {
      router.refresh();
    }
  }, [state.ok, router]);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={trigger} />
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            {mode === "create"
              ? "Add a new kennel type to your listing."
              : "Edit this kennel's details. Changes apply to future bookings only."}
          </DialogDescription>
        </DialogHeader>

        <form action={submit} className="space-y-4">
          {mode === "edit" && initial.id ? (
            <input type="hidden" name="id" value={initial.id} />
          ) : null}

          <div className="space-y-2">
            <Label htmlFor="name">Name</Label>
            <Input id="name" name="name" required defaultValue={initial.name} placeholder="Small Dog Suite" />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Species accepted</Label>
              <Select name="species_accepted" defaultValue={initial.species_accepted}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {SPECIES_ACCEPTED.map((s) => (
                    <SelectItem key={s} value={s}>{SPECIES_ACCEPTED_LABELS[s]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Size range</Label>
              <Select name="size_range" defaultValue={initial.size_range}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {SIZE_RANGES.map((s) => (
                    <SelectItem key={s} value={s}>{SIZE_RANGE_LABELS[s]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-2">
              <Label htmlFor="capacity">Capacity</Label>
              <Input id="capacity" name="capacity" type="number" min={1} max={500} required defaultValue={initial.capacity} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="base_price_myr">Base / night (MYR)</Label>
              <Input id="base_price_myr" name="base_price_myr" type="number" step="0.01" min={0} required defaultValue={initial.base_price_myr} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="peak_price_myr">Peak / night (MYR)</Label>
              <Input id="peak_price_myr" name="peak_price_myr" type="number" step="0.01" min={0} required defaultValue={initial.peak_price_myr} />
            </div>
          </div>

          <div className="flex items-center justify-between rounded-md border border-neutral-200 px-3 py-2">
            <div>
              <Label htmlFor="instant_book" className="font-medium">Instant book</Label>
              <p className="text-xs text-neutral-500">Owners can book and pay immediately without manual approval.</p>
            </div>
            <Switch id="instant_book" name="instant_book" defaultChecked={initial.instant_book} />
          </div>

          <div className="space-y-2">
            <Label htmlFor="description">Description</Label>
            <Textarea id="description" name="description" rows={3} defaultValue={initial.description} maxLength={500} />
          </div>

          {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={pending}>
              {pending ? "Saving…" : mode === "create" ? "Create kennel" : "Save"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

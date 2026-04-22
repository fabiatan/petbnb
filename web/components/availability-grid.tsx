"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import {
  toggleAvailabilityBlockAction,
  type CalendarActionState,
} from "@/app/dashboard/calendar/actions";

export type KennelRow = { id: string; name: string; capacity: number };

/** For each (kennel_type_id, date) pair, how many bookings occupy the cell
 *  and whether a manual block is present. */
export type CellState = {
  bookings: number; // count of accepted+confirmed+pending_payment bookings covering this date
  manual_block: boolean;
};

export type CellMap = Record<string, CellState>; // key = `${kennel_type_id}|${date}`

function formatShort(d: Date) {
  return d.toLocaleDateString("en-MY", { day: "2-digit", month: "short" });
}

function formatWeekday(d: Date) {
  return d.toLocaleDateString("en-MY", { weekday: "short" });
}

function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

function addDays(d: Date, n: number) {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

export function AvailabilityGrid({
  kennels,
  startDate,
  days,
  cells,
}: {
  kennels: KennelRow[];
  startDate: string; // YYYY-MM-DD (the first column)
  days: number;
  cells: CellMap;
}) {
  const router = useRouter();
  const [state, toggleAction, pending] = useActionState<CalendarActionState, FormData>(
    toggleAvailabilityBlockAction,
    {},
  );

  useEffect(() => {
    if (state.ok) router.refresh();
  }, [state.ok, router]);

  const start = new Date(`${startDate}T00:00:00`);
  const dayList = Array.from({ length: days }, (_, i) => addDays(start, i));

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-xs border-collapse">
        <thead>
          <tr>
            <th className="text-left font-semibold text-neutral-500 px-3 py-2 border-b border-neutral-200">
              Kennel
            </th>
            {dayList.map((d) => (
              <th
                key={isoDate(d)}
                className="text-center font-semibold text-neutral-500 px-1 py-2 border-b border-neutral-200 min-w-[56px]"
              >
                <div>{formatWeekday(d)}</div>
                <div className="text-neutral-900">{formatShort(d)}</div>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {kennels.map((k) => (
            <tr key={k.id}>
              <th className="text-left font-medium text-neutral-900 px-3 py-2 border-b border-neutral-100">
                {k.name}
                <div className="text-[10px] text-neutral-500 font-normal">cap {k.capacity}</div>
              </th>
              {dayList.map((d) => {
                const date = isoDate(d);
                const key = `${k.id}|${date}`;
                const cell = cells[key] ?? { bookings: 0, manual_block: false };
                const isFull = cell.bookings >= k.capacity;
                const className = cell.manual_block
                  ? "bg-red-100 border-red-200"
                  : isFull
                  ? "bg-neutral-900 border-neutral-900"
                  : cell.bookings > 0
                  ? "bg-amber-100 border-amber-200"
                  : "bg-white border-neutral-200";

                return (
                  <td
                    key={key}
                    className="p-0 border-b border-neutral-100"
                  >
                    <form action={toggleAction}>
                      <input type="hidden" name="kennel_type_id" value={k.id} />
                      <input type="hidden" name="date" value={date} />
                      <button
                        type="submit"
                        disabled={pending || cell.bookings > 0}
                        title={
                          cell.bookings > 0
                            ? `${cell.bookings} booking(s)`
                            : cell.manual_block
                            ? "Manual block — click to unblock"
                            : "Click to block"
                        }
                        className={`w-full h-10 border ${className} transition cursor-pointer disabled:cursor-not-allowed`}
                      >
                        <span
                          className={
                            cell.manual_block
                              ? "text-red-900 font-semibold"
                              : isFull
                              ? "text-white"
                              : cell.bookings > 0
                              ? "text-amber-900"
                              : "text-neutral-400"
                          }
                        >
                          {cell.manual_block ? "✕" : cell.bookings > 0 ? `${cell.bookings}/${k.capacity}` : "·"}
                        </span>
                      </button>
                    </form>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
      {state.error ? <p className="text-sm text-red-600 mt-2">{state.error}</p> : null}
    </div>
  );
}

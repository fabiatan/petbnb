import { Card, CardContent } from "@/components/ui/card";

export type InboxKpis = {
  pending: number;
  todayCheckIn: number;
  todayCheckOut: number;
  weekRevenueMyr: number;
};

export function InboxKpiStrip({ kpis }: { kpis: InboxKpis }) {
  const items: { label: string; value: string }[] = [
    { label: "Pending", value: String(kpis.pending) },
    { label: "Today check-in", value: String(kpis.todayCheckIn) },
    { label: "Today check-out", value: String(kpis.todayCheckOut) },
    { label: "This week", value: `RM${kpis.weekRevenueMyr.toFixed(0)}` },
  ];
  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
      {items.map((i) => (
        <Card key={i.label} className="border-neutral-200">
          <CardContent className="p-3">
            <div className="text-[10px] uppercase tracking-wide text-neutral-500 font-semibold">
              {i.label}
            </div>
            <div className="text-xl font-bold mt-0.5">{i.value}</div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Separator } from "@/components/ui/separator";
import { signOutAction } from "@/app/(auth)/actions";

type Route = { href: string; label: string };

const routes: Route[] = [
  { href: "/dashboard/inbox", label: "Inbox" },
  { href: "/dashboard/calendar", label: "Calendar" },
  { href: "/dashboard/listing", label: "Listing" },
  { href: "/dashboard/reviews", label: "Reviews" },
  { href: "/dashboard/payouts", label: "Payouts" },
  { href: "/dashboard/settings", label: "Settings" },
];

export function DashboardSidebar({ businessName }: { businessName: string }) {
  const pathname = usePathname();

  return (
    <aside className="w-52 bg-neutral-50 border-r border-neutral-200 flex flex-col">
      <div className="p-4">
        <div className="h-9 w-9 rounded-lg bg-gradient-to-br from-yellow-200 to-orange-400" />
        <div className="mt-2 text-sm font-bold">{businessName}</div>
        <div className="text-xs text-neutral-500">Business admin</div>
      </div>
      <Separator />
      <nav className="py-3 px-2 space-y-1">
        {routes.map((r) => {
          const active = pathname === r.href;
          return (
            <Link
              key={r.href}
              href={r.href}
              className={
                active
                  ? "block rounded-md bg-neutral-900 text-white px-3 py-2 text-xs font-medium"
                  : "block rounded-md text-neutral-700 hover:bg-neutral-100 px-3 py-2 text-xs"
              }
            >
              {r.label}
            </Link>
          );
        })}
      </nav>
      <div className="mt-auto p-3">
        <form action={signOutAction}>
          <button className="w-full text-left text-xs text-neutral-500 hover:text-neutral-900" type="submit">
            Sign out
          </button>
        </form>
      </div>
    </aside>
  );
}

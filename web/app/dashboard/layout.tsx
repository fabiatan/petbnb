import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { DashboardSidebar } from "@/components/dashboard-sidebar";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/sign-in");

  // Load the business this admin belongs to. If none, bounce to onboarding.
  const { data: membership } = await supabase
    .from("business_members")
    .select("business_id, businesses!inner(id, name)")
    .eq("user_id", user.id)
    .limit(1)
    .single();

  if (!membership) redirect("/onboarding");

  const businessName =
    (membership.businesses as unknown as { name: string } | null)?.name ??
    "Unknown business";

  return (
    <div className="min-h-screen flex">
      <DashboardSidebar businessName={businessName} />
      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}

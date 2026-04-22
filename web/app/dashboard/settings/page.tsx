import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";

export default function SettingsPage() {
  return (
    <div className="max-w-3xl">
      <h1 className="text-2xl font-bold tracking-tight">Settings</h1>
      <p className="text-sm text-neutral-600 mt-1">Manage your business profile and verification documents.</p>

      <div className="mt-6 grid gap-4 sm:grid-cols-2">
        <Link href="/dashboard/settings/kyc" className="group">
          <Card className="border-neutral-200 transition group-hover:border-neutral-900">
            <CardContent className="p-5">
              <h2 className="font-semibold">KYC documents</h2>
              <p className="text-xs text-neutral-500 mt-1">
                Upload SSM cert, business license, proof of premises, and owner MyKad.
              </p>
            </CardContent>
          </Card>
        </Link>

        <Card className="border-neutral-200 opacity-60">
          <CardContent className="p-5">
            <h2 className="font-semibold">Business profile</h2>
            <p className="text-xs text-neutral-500 mt-1">Coming later — edit address, description, photos.</p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}

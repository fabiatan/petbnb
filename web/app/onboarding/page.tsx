"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { createBusinessAction, type OnboardingFormState } from "./actions";

export default function OnboardingPage() {
  const [state, action, pending] = useActionState<OnboardingFormState, FormData>(
    createBusinessAction,
    {},
  );

  return (
    <main className="min-h-screen flex items-center justify-center bg-neutral-50 p-4">
      <Card className="w-full max-w-lg">
        <CardHeader>
          <CardTitle className="text-2xl">Register your business</CardTitle>
          <p className="text-sm text-neutral-600">
            Tell us about your boarding facility. You can edit everything later.
          </p>
        </CardHeader>
        <CardContent>
          <form action={action} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="name">Business name</Label>
              <Input id="name" name="name" required placeholder="Happy Paws KL" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="slug">URL slug (optional)</Label>
              <Input id="slug" name="slug" placeholder="happy-paws-kl" pattern="[a-z0-9-]+" />
              <p className="text-xs text-neutral-500">
                Lowercase letters, numbers, and hyphens. Leave blank to auto-generate from the name.
              </p>
            </div>
            <div className="space-y-2">
              <Label htmlFor="address">Street address</Label>
              <Input id="address" name="address" required placeholder="1 Jalan Mont Kiara" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label htmlFor="city">City</Label>
                <Input id="city" name="city" required placeholder="Kuala Lumpur" />
              </div>
              <div className="space-y-2">
                <Label htmlFor="state">State</Label>
                <Input id="state" name="state" required placeholder="WP Kuala Lumpur" />
              </div>
            </div>
            {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
            <Button type="submit" className="w-full" disabled={pending}>
              {pending ? "Creating…" : "Create business"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </main>
  );
}

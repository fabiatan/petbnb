import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "PetBnB — Business Dashboard",
  description:
    "Manage bookings, listings, and payouts for your pet boarding business.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="min-h-screen antialiased bg-white text-neutral-900">
        {children}
      </body>
    </html>
  );
}

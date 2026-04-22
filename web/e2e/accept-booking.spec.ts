import { test, expect } from "@playwright/test";
import { execSync } from "node:child_process";

function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 10);
}

// Use full path because psql is not on the default PATH on this machine.
// Deviation from plan: ownerId obtained via gen_random_uuid() to avoid UUID
// validation failures when the random suffix contains non-hex chars (g-z).
const PSQL_BIN = "/opt/homebrew/Cellar/libpq/18.3/bin/psql";
const PSQL_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

function psql(sql: string): string {
  // Collapse whitespace so multi-line SQL doesn't produce literal \n in the shell arg.
  // -A: unaligned; -t: tuples only; -c: command
  // psql prints "INSERT 0 1" after an INSERT RETURNING even in tuples-only mode,
  // so we take only the first non-empty line (the actual returned value).
  const oneline = sql.replace(/\s+/g, " ").trim();
  const raw = execSync(`${PSQL_BIN} "${PSQL_URL}" -A -t -c ${JSON.stringify(oneline)}`, { encoding: "utf8" });
  const firstLine = raw.split("\n").map((l) => l.trim()).find((l) => l.length > 0) ?? "";
  return firstLine;
}

test("business admin accepts a seeded booking request", async ({ page }) => {
  const suffix = uniqueSuffix();
  const email = `accept-${suffix}@petbnb.test`;
  const password = "correct-horse-battery-staple";
  const businessName = `Accept E2E ${suffix}`;
  const slug = `accept-e2e-${suffix}`;

  // 1. Sign up + onboard via the UI (so we get a real auth.users row + business)
  await page.goto("/sign-up");
  await page.getByLabel("Your name").fill(`Accept E2E ${suffix}`);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: /create account/i }).click();
  await expect(page).toHaveURL(/\/onboarding$/);

  await page.getByLabel("Business name").fill(businessName);
  await page.getByLabel("URL slug (optional)").fill(slug);
  await page.getByLabel("Street address").fill("1 Accept St");
  await page.getByLabel("City").fill("KL");
  await page.getByLabel("State").fill("WP");
  await page.getByRole("button", { name: /create business/i }).click();
  await expect(page).toHaveURL(/\/dashboard\/inbox$/);

  // 2. Seed a kennel + owner + booking via psql (bypass RLS as postgres)
  const businessId = psql(`SELECT id FROM businesses WHERE slug = '${slug}';`);
  const listingId = psql(`SELECT id FROM listings WHERE business_id = '${businessId}';`);

  const ownerEmail = `owner-accept-${suffix}@petbnb.test`;
  // Use gen_random_uuid() to avoid UUID validation failures from non-hex suffix chars.
  const ownerId = psql(`SELECT gen_random_uuid();`);

  const kennelId = psql(`
    INSERT INTO kennel_types (listing_id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr)
    VALUES ('${listingId}', 'E2E Suite', 'dog', 'small', 4, 80, 100)
    RETURNING id;
  `);

  psql(`
    INSERT INTO auth.users (id, email) VALUES ('${ownerId}', '${ownerEmail}');
    INSERT INTO user_profiles (id, display_name, primary_role) VALUES ('${ownerId}', 'Test Owner ${suffix}', 'owner');
  `);

  const petId = psql(`
    INSERT INTO pets (owner_id, name, species, breed, weight_kg)
    VALUES ('${ownerId}', 'TestPet-${suffix}', 'dog', 'Poodle', 8)
    RETURNING id;
  `);

  const bookingId = psql(`
    INSERT INTO bookings (
      owner_id, business_id, listing_id, kennel_type_id,
      check_in, check_out, nights, subtotal_myr, status, payment_deadline
    ) VALUES (
      '${ownerId}', '${businessId}', '${listingId}', '${kennelId}',
      '2027-05-10', '2027-05-12', 2, 160, 'requested', now() + interval '24 hours'
    ) RETURNING id;
  `);
  psql(`INSERT INTO booking_pets (booking_id, pet_id) VALUES ('${bookingId}', '${petId}');`);

  // 3. Reload inbox — the seeded request should appear
  await page.reload();
  await expect(page.getByText(`TestPet-${suffix}`)).toBeVisible();
  await expect(page.getByText(`Test Owner ${suffix}`)).toBeVisible();

  // 4. Accept it
  await page.getByRole("button", { name: /^Accept$/ }).click();

  // 5. Verify DB transitioned to accepted
  await expect.poll(
    () => psql(`SELECT status FROM bookings WHERE id = '${bookingId}';`),
    { timeout: 10_000, intervals: [500] },
  ).toBe("accepted");

  // 6. The card should be gone (no longer in pending list)
  await expect(page.getByText(`TestPet-${suffix}`)).not.toBeVisible();
});

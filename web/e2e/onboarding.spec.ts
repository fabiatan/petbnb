import { test, expect } from "@playwright/test";

// Helper: generate a unique slug/email so the test doesn't collide with itself
function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 10);
}

test("sign-up → onboarding → dashboard", async ({ page }) => {
  const suffix = uniqueSuffix();
  const email = `e2e-${suffix}@petbnb.test`;
  const password = "correct-horse-battery-staple";
  const displayName = `E2E Admin ${suffix}`;
  const businessName = `E2E Boarding ${suffix}`;
  const slug = `e2e-boarding-${suffix}`;

  // Root redirects unauthenticated → /sign-in
  await page.goto("/");
  await expect(page).toHaveURL(/\/sign-in$/);

  // Go to sign-up
  await page.getByRole("link", { name: /create an account/i }).click();
  await expect(page).toHaveURL(/\/sign-up$/);

  await page.getByLabel("Your name").fill(displayName);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: /create account/i }).click();

  // Should land on /onboarding
  await expect(page).toHaveURL(/\/onboarding$/);

  await page.getByLabel("Business name").fill(businessName);
  await page.getByLabel("URL slug (optional)").fill(slug);
  await page.getByLabel("Street address").fill("1 Test Street");
  await page.getByLabel("City").fill("Kuala Lumpur");
  await page.getByLabel("State").fill("WP");
  await page.getByRole("button", { name: /create business/i }).click();

  // Should end up on dashboard inbox with the business name visible
  await expect(page).toHaveURL(/\/dashboard\/inbox$/);
  await expect(page.getByText(businessName)).toBeVisible();
  await expect(page.getByRole("heading", { name: /inbox/i })).toBeVisible();
});

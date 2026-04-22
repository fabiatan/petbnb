import { test, expect } from "@playwright/test";
import path from "node:path";

function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 10);
}

test("upload KYC document appears in settings", async ({ page }) => {
  const suffix = uniqueSuffix();
  const email = `kyc-e2e-${suffix}@petbnb.test`;
  const password = "correct-horse-battery-staple";
  const displayName = `KYC E2E ${suffix}`;
  const businessName = `KYC E2E Biz ${suffix}`;
  const slug = `kyc-e2e-${suffix}`;

  // Sign up + onboard
  await page.goto("/sign-up");
  await page.getByLabel("Your name").fill(displayName);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: /create account/i }).click();
  await expect(page).toHaveURL(/\/onboarding$/);

  await page.getByLabel("Business name").fill(businessName);
  await page.getByLabel("URL slug (optional)").fill(slug);
  await page.getByLabel("Street address").fill("1 Test Street");
  await page.getByLabel("City").fill("Kuala Lumpur");
  await page.getByLabel("State").fill("WP");
  await page.getByRole("button", { name: /create business/i }).click();
  await expect(page).toHaveURL(/\/dashboard\/inbox$/);

  // Banner should prompt for KYC upload
  await expect(page.getByText(/Upload KYC documents/i)).toBeVisible();

  // Navigate to the KYC page
  await page.getByRole("link", { name: /Upload now/i }).click();
  await expect(page).toHaveURL(/\/dashboard\/settings\/kyc$/);
  await expect(page.getByRole("heading", { name: /KYC documents/i })).toBeVisible();

  // Upload the sample PDF into the SSM cert card (first card)
  const fixturePath = path.join(__dirname, "fixtures", "sample.pdf");
  const fileInput = page.locator("input[type=file]").first();
  await fileInput.setInputFiles(fixturePath);
  await page.getByRole("button", { name: /^Upload$/ }).first().click();

  // Wait for the "Replace" button to appear (indicates successful upload)
  await expect(page.getByRole("button", { name: /^Replace$/ }).first()).toBeVisible({
    timeout: 15_000,
  });
  await expect(page.getByText("sample.pdf").first()).toBeVisible();
});

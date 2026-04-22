import { test, expect } from "@playwright/test";
import path from "node:path";

function uniqueSuffix() {
  return Math.random().toString(36).slice(2, 10);
}

test("listing editor: photo upload + kennel CRUD", async ({ page }) => {
  const suffix = uniqueSuffix();
  const email = `listing-e2e-${suffix}@petbnb.test`;
  const password = "correct-horse-battery-staple";
  const businessName = `Listing E2E ${suffix}`;
  const slug = `listing-e2e-${suffix}`;

  // Sign up + onboard
  await page.goto("/sign-up");
  await page.getByLabel("Your name").fill(`Listing E2E ${suffix}`);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.getByRole("button", { name: /create account/i }).click();
  await expect(page).toHaveURL(/\/onboarding$/);

  await page.getByLabel("Business name").fill(businessName);
  await page.getByLabel("URL slug (optional)").fill(slug);
  await page.getByLabel("Street address").fill("1 Listing St");
  await page.getByLabel("City").fill("KL");
  await page.getByLabel("State").fill("WP");
  await page.getByRole("button", { name: /create business/i }).click();
  await expect(page).toHaveURL(/\/dashboard\/inbox$/);

  // Navigate to listing editor
  await page.getByRole("link", { name: "Listing", exact: true }).click();
  await expect(page).toHaveURL(/\/dashboard\/listing$/);
  await expect(page.getByRole("heading", { name: "Listing", exact: true })).toBeVisible();

  // Upload 2 photos
  const fixturePath = path.join(__dirname, "fixtures", "photo.jpg");
  const fileInput = page.locator('input[type=file][name="files"]');
  await fileInput.setInputFiles([fixturePath, fixturePath]);
  await page.getByRole("button", { name: /^Upload$/ }).click();
  await expect(page.locator("ul li")).toHaveCount(2, { timeout: 15_000 });

  // Create a kennel
  await page.getByRole("button", { name: /Add kennel/i }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await dialog.getByLabel("Name").fill("E2E Suite");
  await dialog.getByLabel("Capacity").fill("3");
  await dialog.getByLabel("Base / night (MYR)").fill("80");
  await dialog.getByLabel("Peak / night (MYR)").fill("100");
  await dialog.getByRole("button", { name: /Create kennel/i }).click();
  await expect(page.getByText("E2E Suite")).toBeVisible({ timeout: 10_000 });

  // Edit the kennel price
  await page.getByRole("button", { name: /^Edit$/ }).first().click();
  const editDialog = page.getByRole("dialog");
  await expect(editDialog).toBeVisible();
  const baseInput = editDialog.getByLabel("Base / night (MYR)");
  await baseInput.fill("90");
  await editDialog.getByRole("button", { name: /^Save$/ }).click();
  await expect(page.getByText(/RM90\.00/)).toBeVisible({ timeout: 10_000 });
});

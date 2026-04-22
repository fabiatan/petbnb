import {
  pgTable,
  pgEnum,
  uuid,
  text,
  integer,
  numeric,
  boolean,
  date,
  timestamp,
  jsonb,
  primaryKey,
  unique,
  check,
} from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

// ──────────────────────────────────────────────────────────────────────────────
// Enums — mirror supabase/migrations/001_enums.sql
// ──────────────────────────────────────────────────────────────────────────────

export const userRoleEnum = pgEnum("user_role", [
  "owner",
  "business_admin",
  "platform_admin",
]);

export const kycStatusEnum = pgEnum("kyc_status", [
  "pending",
  "verified",
  "rejected",
]);

export const businessStatusEnum = pgEnum("business_status", [
  "active",
  "paused",
  "banned",
]);

export const speciesAcceptedEnum = pgEnum("species_accepted", [
  "dog",
  "cat",
  "both",
]);

export const speciesEnum = pgEnum("species", ["dog", "cat"]);

export const sizeRangeEnum = pgEnum("size_range", [
  "small",
  "medium",
  "large",
]);

export const cancellationPolicyEnum = pgEnum("cancellation_policy", [
  "flexible",
  "moderate",
  "strict",
]);

export const bookingStatusEnum = pgEnum("booking_status", [
  "requested",
  "accepted",
  "declined",
  "pending_payment",
  "expired",
  "confirmed",
  "completed",
  "cancelled_by_owner",
  "cancelled_by_business",
]);

export const bookingTerminalReasonEnum = pgEnum("booking_terminal_reason", [
  "no_response_24h",
  "no_payment_24h",
  "no_payment_15min_instant",
  "owner_cancelled",
  "business_cancelled",
  "payment_failed",
]);

export const notificationKindEnum = pgEnum("notification_kind", [
  "request_submitted",
  "request_accepted",
  "request_declined",
  "payment_confirmed",
  "acceptance_expiring",
  "payment_expiring",
  "booking_cancelled",
  "review_prompt",
  "review_received",
]);

// ──────────────────────────────────────────────────────────────────────────────
// Identity tables — mirror 002_identity_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const userProfiles = pgTable("user_profiles", {
  id: uuid("id").primaryKey(), // FK → auth.users(id); no Drizzle reference because auth schema is Supabase-managed
  displayName: text("display_name").notNull(),
  avatarUrl: text("avatar_url"),
  phone: text("phone"),
  preferredLang: text("preferred_lang").notNull().default("en"),
  primaryRole: userRoleEnum("primary_role").notNull().default("owner"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const pets = pgTable("pets", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  ownerId: uuid("owner_id")
    .notNull()
    .references(() => userProfiles.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  species: speciesEnum("species").notNull(),
  breed: text("breed"),
  ageMonths: integer("age_months"),
  weightKg: numeric("weight_kg", { precision: 5, scale: 2 }),
  medicalNotes: text("medical_notes"),
  avatarUrl: text("avatar_url"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const vaccinationCerts = pgTable("vaccination_certs", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  petId: uuid("pet_id")
    .notNull()
    .references(() => pets.id, { onDelete: "cascade" }),
  fileUrl: text("file_url").notNull(),
  vaccinesCovered: text("vaccines_covered").array().notNull().default(sql`ARRAY[]::text[]`),
  issuedOn: date("issued_on").notNull(),
  expiresOn: date("expires_on").notNull(),
  verifiedByBusinessId: uuid("verified_by_business_id"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// ──────────────────────────────────────────────────────────────────────────────
// Business tables — mirror 003_business_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const businesses = pgTable("businesses", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  name: text("name").notNull(),
  slug: text("slug").notNull().unique(),
  address: text("address").notNull(),
  city: text("city").notNull(),
  state: text("state").notNull(),
  // geo_point point -- point not commonly used via Drizzle; skip for typed access
  description: text("description"),
  coverPhotoUrl: text("cover_photo_url"),
  logoUrl: text("logo_url"),
  kycStatus: kycStatusEnum("kyc_status").notNull().default("pending"),
  kycDocuments: jsonb("kyc_documents").notNull().default({}),
  commissionRateBps: integer("commission_rate_bps").notNull().default(1200),
  payoutBankInfo: jsonb("payout_bank_info").notNull().default({}),
  status: businessStatusEnum("status").notNull().default("active"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const businessMembers = pgTable(
  "business_members",
  {
    businessId: uuid("business_id")
      .notNull()
      .references(() => businesses.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => userProfiles.id, { onDelete: "cascade" }),
    role: text("role").notNull().default("admin"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.businessId, t.userId] }),
  }),
);

export const listings = pgTable("listings", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  businessId: uuid("business_id")
    .notNull()
    .unique()
    .references(() => businesses.id, { onDelete: "cascade" }),
  photos: text("photos").array().notNull().default(sql`ARRAY[]::text[]`),
  amenities: text("amenities").array().notNull().default(sql`ARRAY[]::text[]`),
  houseRules: text("house_rules"),
  cancellationPolicy: cancellationPolicyEnum("cancellation_policy")
    .notNull()
    .default("moderate"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const kennelTypes = pgTable("kennel_types", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  listingId: uuid("listing_id")
    .notNull()
    .references(() => listings.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  speciesAccepted: speciesAcceptedEnum("species_accepted").notNull(),
  sizeRange: sizeRangeEnum("size_range").notNull(),
  capacity: integer("capacity").notNull(),
  basePriceMyr: numeric("base_price_myr", { precision: 10, scale: 2 }).notNull(),
  peakPriceMyr: numeric("peak_price_myr", { precision: 10, scale: 2 }).notNull(),
  instantBook: boolean("instant_book").notNull().default(false),
  description: text("description"),
  active: boolean("active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

// ──────────────────────────────────────────────────────────────────────────────
// Availability — mirror 004_availability_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const peakCalendar = pgTable("peak_calendar", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  businessId: uuid("business_id").references(() => businesses.id, { onDelete: "cascade" }),
  date: date("date").notNull(),
  label: text("label"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const availabilityOverrides = pgTable(
  "availability_overrides",
  {
    id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
    kennelTypeId: uuid("kennel_type_id")
      .notNull()
      .references(() => kennelTypes.id, { onDelete: "cascade" }),
    date: date("date").notNull(),
    manualBlock: boolean("manual_block").notNull().default(true),
    note: text("note"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    uniq: unique().on(t.kennelTypeId, t.date),
  }),
);

// ──────────────────────────────────────────────────────────────────────────────
// Bookings — mirror 005_booking_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const bookings = pgTable("bookings", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  ownerId: uuid("owner_id")
    .notNull()
    .references(() => userProfiles.id),
  businessId: uuid("business_id")
    .notNull()
    .references(() => businesses.id),
  listingId: uuid("listing_id")
    .notNull()
    .references(() => listings.id),
  kennelTypeId: uuid("kennel_type_id")
    .notNull()
    .references(() => kennelTypes.id),
  checkIn: date("check_in").notNull(),
  checkOut: date("check_out").notNull(),
  nights: integer("nights").notNull(),
  subtotalMyr: numeric("subtotal_myr", { precision: 10, scale: 2 }).notNull(),
  platformFeeMyr: numeric("platform_fee_myr", { precision: 10, scale: 2 }).notNull().default("0"),
  businessPayoutMyr: numeric("business_payout_myr", { precision: 10, scale: 2 }).notNull().default("0"),
  status: bookingStatusEnum("status").notNull(),
  requestedAt: timestamp("requested_at", { withTimezone: true }).notNull().defaultNow(),
  actedAt: timestamp("acted_at", { withTimezone: true }),
  paymentDeadline: timestamp("payment_deadline", { withTimezone: true }),
  specialInstructions: text("special_instructions"),
  cancellationReason: text("cancellation_reason"),
  terminalReason: bookingTerminalReasonEnum("terminal_reason"),
  ipay88Reference: text("ipay88_reference").unique(),
  isInstantBook: boolean("is_instant_book").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const bookingPets = pgTable(
  "booking_pets",
  {
    bookingId: uuid("booking_id")
      .notNull()
      .references(() => bookings.id, { onDelete: "cascade" }),
    petId: uuid("pet_id")
      .notNull()
      .references(() => pets.id),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.bookingId, t.petId] }),
  }),
);

export const bookingCertSnapshots = pgTable("booking_cert_snapshots", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  bookingId: uuid("booking_id")
    .notNull()
    .references(() => bookings.id, { onDelete: "cascade" }),
  petId: uuid("pet_id")
    .notNull()
    .references(() => pets.id),
  vaccinationCertId: uuid("vaccination_cert_id")
    .notNull()
    .references(() => vaccinationCerts.id),
  fileUrl: text("file_url").notNull(),
  expiresOn: date("expires_on").notNull(),
  snapshottedAt: timestamp("snapshotted_at", { withTimezone: true }).notNull().defaultNow(),
});

// ──────────────────────────────────────────────────────────────────────────────
// Post-stay + ops — mirror 006_post_stay_tables.sql
// ──────────────────────────────────────────────────────────────────────────────

export const reviews = pgTable("reviews", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  bookingId: uuid("booking_id")
    .notNull()
    .unique()
    .references(() => bookings.id, { onDelete: "cascade" }),
  businessId: uuid("business_id")
    .notNull()
    .references(() => businesses.id),
  ownerId: uuid("owner_id")
    .notNull()
    .references(() => userProfiles.id),
  serviceRating: integer("service_rating").notNull(),
  responseRating: integer("response_rating").notNull(),
  text: text("text"),
  postedAt: timestamp("posted_at", { withTimezone: true }).notNull().defaultNow(),
});

export const reviewResponses = pgTable("review_responses", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  reviewId: uuid("review_id")
    .notNull()
    .unique()
    .references(() => reviews.id, { onDelete: "cascade" }),
  businessId: uuid("business_id")
    .notNull()
    .references(() => businesses.id),
  text: text("text").notNull(),
  postedAt: timestamp("posted_at", { withTimezone: true }).notNull().defaultNow(),
});

export const notifications = pgTable("notifications", {
  id: uuid("id").primaryKey().default(sql`gen_random_uuid()`),
  userId: uuid("user_id")
    .notNull()
    .references(() => userProfiles.id, { onDelete: "cascade" }),
  kind: notificationKindEnum("kind").notNull(),
  payload: jsonb("payload").notNull().default({}),
  readAt: timestamp("read_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

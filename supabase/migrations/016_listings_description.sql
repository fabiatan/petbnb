-- Phase 1c: add free-text description field to listings.
-- The listings table was created in 003_business_tables.sql without description;
-- the listing-editor UI needs it for the info form.
ALTER TABLE listings ADD COLUMN IF NOT EXISTS description text;

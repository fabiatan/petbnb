-- MY public holidays (federal) + school holidays — platform-wide peak rows.
-- Re-runnable: ON CONFLICT skips existing.
INSERT INTO peak_calendar (date, label) VALUES
  -- 2026 public holidays
  ('2026-01-01','New Year'),
  ('2026-01-28','Thaipusam'),
  ('2026-02-17','Chinese New Year'),
  ('2026-02-18','Chinese New Year'),
  ('2026-03-21','Hari Raya Aidilfitri'),
  ('2026-03-22','Hari Raya Aidilfitri'),
  ('2026-05-01','Labour Day'),
  ('2026-05-21','Wesak'),
  ('2026-05-28','Hari Raya Haji'),
  ('2026-06-06','Agong Birthday'),
  ('2026-06-17','Awal Muharram'),
  ('2026-08-26','Maulidur Rasul'),
  ('2026-08-31','National Day'),
  ('2026-09-16','Malaysia Day'),
  ('2026-11-09','Deepavali'),
  ('2026-12-25','Christmas'),
  -- 2027 public holidays
  ('2027-01-01','New Year'),
  ('2027-02-06','Chinese New Year'),
  ('2027-02-07','Chinese New Year'),
  ('2027-02-16','Thaipusam'),
  ('2027-03-11','Hari Raya Aidilfitri'),
  ('2027-03-12','Hari Raya Aidilfitri'),
  ('2027-05-01','Labour Day'),
  ('2027-05-11','Wesak'),
  ('2027-05-17','Hari Raya Haji'),
  ('2027-06-06','Awal Muharram'),
  ('2027-06-07','Agong Birthday'),
  ('2027-08-16','Maulidur Rasul'),
  ('2027-08-31','National Day'),
  ('2027-09-16','Malaysia Day'),
  ('2027-10-29','Deepavali'),
  ('2027-12-25','Christmas')
ON CONFLICT DO NOTHING;

-- School holiday windows (cuti sekolah). Insert every date in each range as its own row.
-- 2026 windows
DO $$
DECLARE
  v_ranges daterange[] := ARRAY[
    daterange('2026-03-21', '2026-03-30'),   -- Term 1 break (approx)
    daterange('2026-05-23', '2026-05-31'),   -- Mid-term
    daterange('2026-08-22', '2026-08-30'),   -- Term 2 break
    daterange('2026-12-05', '2027-01-04'),   -- Year-end
    daterange('2027-03-13', '2027-03-22'),
    daterange('2027-05-22', '2027-05-30'),
    daterange('2027-08-21', '2027-08-29'),
    daterange('2027-12-04', '2028-01-03')
  ];
  r daterange;
  d date;
BEGIN
  FOREACH r IN ARRAY v_ranges LOOP
    d := lower(r);
    WHILE d < upper(r) LOOP
      INSERT INTO peak_calendar (date, label) VALUES (d, 'School holiday')
      ON CONFLICT DO NOTHING;
      d := d + 1;
    END LOOP;
  END LOOP;
END $$;

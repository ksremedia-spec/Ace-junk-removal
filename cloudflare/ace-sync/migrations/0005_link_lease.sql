-- One sheet check at a time (audit fix-now 26), and the sheet's layout as
-- first seen, so renamed headings pause instead of changing every job (30).
ALTER TABLE google_link ADD COLUMN running_until REAL NOT NULL DEFAULT 0;
ALTER TABLE google_link ADD COLUMN layout TEXT NOT NULL DEFAULT '';

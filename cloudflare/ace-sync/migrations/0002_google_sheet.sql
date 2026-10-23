-- The link to Ashley's Google Sheet (docs/google-sheet-sync.md). One row.
CREATE TABLE google_link (
  id            INTEGER PRIMARY KEY CHECK (id = 1),
  refresh_token TEXT    NOT NULL,
  sheet_id      TEXT    NOT NULL,
  sheet_name    TEXT    NOT NULL DEFAULT '',
  connected_at  REAL    NOT NULL,
  last_version  TEXT    NOT NULL DEFAULT '',
  -- Records up to this running number have been written to the sheet.
  last_seq      INTEGER NOT NULL DEFAULT 0,
  next_tag      INTEGER NOT NULL DEFAULT 1,
  paused        TEXT    NOT NULL DEFAULT '',
  last_run      REAL    NOT NULL DEFAULT 0,
  last_error    TEXT    NOT NULL DEFAULT ''
);

-- A sign-in that was started and has not come back yet.
CREATE TABLE google_pending (
  state   TEXT PRIMARY KEY,
  created REAL NOT NULL
);

-- Each tagged sheet row as last seen: which job it is, and a fingerprint
-- of its cells, so an edit in the sheet can be noticed.
CREATE TABLE sheet_rows (
  tag    INTEGER PRIMARY KEY,
  job_id TEXT    NOT NULL UNIQUE,
  hash   TEXT    NOT NULL
);

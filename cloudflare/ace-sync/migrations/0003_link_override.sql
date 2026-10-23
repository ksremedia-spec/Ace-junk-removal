-- Resume after a pause lets the next check through its safety limits once.
ALTER TABLE google_link ADD COLUMN override INTEGER NOT NULL DEFAULT 0;

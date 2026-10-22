-- Every synced record, one row each. `seq` goes up by one on every
-- accepted change, so a device asks for "everything after seq N".
CREATE TABLE records (
  type       TEXT    NOT NULL,
  id         TEXT    NOT NULL,
  updated_at REAL    NOT NULL,  -- milliseconds since 1970, from the device
  deleted    INTEGER NOT NULL DEFAULT 0,
  data       TEXT    NOT NULL DEFAULT '{}',
  seq        INTEGER NOT NULL,
  device     TEXT    NOT NULL DEFAULT '',
  PRIMARY KEY (type, id)
);
CREATE UNIQUE INDEX records_seq ON records (seq);

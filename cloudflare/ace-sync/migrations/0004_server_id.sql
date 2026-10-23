-- This server's own ID, so a device can tell it is talking to a different
-- (or reset) server and start its sync memory afresh (audit fix-now 1).
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO meta (key, value) VALUES ('server_id', lower(hex(randomblob(16))));

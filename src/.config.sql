CREATE TABLE "config" ("param" TEXT PRIMARY KEY  NOT NULL  UNIQUE , "value" TEXT NOT NULL );
INSERT INTO "config" VALUES('port','10050');
INSERT INTO "config" VALUES('jd_port','8765');
INSERT INTO "config" VALUES('jd_address','JD:JD@127.0.0.1');
INSERT INTO "config" VALUES('version','0.1.2');
INSERT INTO "config" VALUES('check_update','TRUE');
INSERT INTO "config" VALUES('open_browser','TRUE');
CREATE TABLE "feeds" ("url" TEXT PRIMARY KEY  NOT NULL  UNIQUE , "interval" INTEGER, "follow_links" BOOL NOT NULL  DEFAULT FALSE, "last_processed" INTEGER, "enabled" BOOL NOT NULL  DEFAULT TRUE);
CREATE TABLE "filters" ("title" TEXT PRIMARY KEY  NOT NULL  UNIQUE , "filter1" TEXT NOT NULL , "regex1" BOOL NOT NULL  DEFAULT FALSE, "filter2" TEXT NOT NULL , "regex2" BOOL NOT NULL  DEFAULT FALSE,"feeds" TEXT NOT NULL, "link_types" TEXT NOT NULL, "tv" BOOL NOT NULL  DEFAULT FALSE, "tv_last" TEXT, "autostart" BOOL NOT NULL  DEFAULT TRUE, "enabled" BOOL NOT NULL  DEFAULT TRUE, "stop_found" BOOL NOT NULL  DEFAULT TRUE);
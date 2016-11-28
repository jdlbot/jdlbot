CREATE TABLE "config" ("param" TEXT PRIMARY KEY  NOT NULL  UNIQUE , "value" TEXT NOT NULL );
INSERT INTO "config" VALUES('port','10050');
INSERT INTO "config" VALUES('jd_port','8765');
INSERT INTO "config" VALUES('jd_address','JD:JD@127.0.0.1');
INSERT INTO "config" VALUES('version','0.1.3');
INSERT INTO "config" VALUES('check_update','TRUE');
INSERT INTO "config" VALUES('open_browser','TRUE');

CREATE TABLE "feeds" ("url" TEXT PRIMARY KEY  NOT NULL  UNIQUE , "interval" INTEGER, "follow_links" BOOL NOT NULL  DEFAULT FALSE, "last_processed" INTEGER, "enabled" BOOL NOT NULL  DEFAULT TRUE);

CREATE TABLE "filters" ("title" TEXT PRIMARY KEY  NOT NULL  UNIQUE , "filter1" TEXT NOT NULL , "regex1" BOOL NOT NULL  DEFAULT FALSE, "filter2" TEXT NOT NULL , "regex2" BOOL NOT NULL  DEFAULT FALSE,"feeds" TEXT NOT NULL, "link_types" TEXT NOT NULL, "tv" BOOL NOT NULL  DEFAULT FALSE, "tv_last" TEXT, "autostart" BOOL NOT NULL  DEFAULT TRUE, "enabled" BOOL NOT NULL  DEFAULT TRUE, "stop_found" BOOL NOT NULL  DEFAULT TRUE);

CREATE TABLE "linktypes" ("linkhost" TEXT PRIMARY KEY  NOT NULL  UNIQUE , "priority" INTEGER NOT NULL  DEFAULT 1, "enabled" BOOL NOT NULL  DEFAULT TRUE);
INSERT INTO "linktypes" VALUES ('fileserve.com', 40, 'FALSE');
INSERT INTO "linktypes" VALUES ('filesonic.com', 40, 'FALSE');
INSERT INTO "linktypes" VALUES ('wupload.com', 40, 'FALSE');

INSERT INTO "linktypes" VALUES ('netload.in', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('depositfiles.com', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('duckload.com', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('jumbofiles.com', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('letitbit.net', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('megashare.com', 50, 'TRUE');


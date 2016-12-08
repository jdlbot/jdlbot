package JdlBot::DbUpdate;

use strict;
use warnings;

my $updates = {
				 '0.1.1' => <<'END',
UPDATE "config" SET value='0.1.1' WHERE param='version';
INSERT INTO "config" VALUES('check_update','TRUE');
END
				 '0.1.2' => <<'END',
UPDATE "config" SET value='0.1.2' WHERE param='version';
INSERT INTO "config" VALUES('open_browser','TRUE');
END
				 '0.1.3' => <<'END',
UPDATE "config" SET value='0.1.3' WHERE param='version';
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
END
				 '0.1.4' => <<'END'
UPDATE "config" SET value='0.1.4' WHERE param='version';
INSERT INTO config VALUES ('host', '127.0.0.1');
CREATE TABLE "filter_conf" ("conf" TEXT PRIMARY KEY  NOT NULL  UNIQUE , "movies" TEXT , "movie_regex" BOOL NOT NULL  DEFAULT TRUE , "movie_enabled" BOOL NOT NULL  DEFAULT TRUE , "tv" TEXT , "tv_regex" BOOL NOT NULL  DEFAULT TRUE , "tv_enabled" BOOL NOT NULL  DEFAULT TRUE );
INSERT INTO "filter_conf" VALUES ('default', '.*%t.*(720|1080).*(BluRay|BRRip|BDRip|WEB).*(AC3|DTS|DD5|DD7).*', 'TRUE', 'TRUE', '.*%t.*(720|1080).*', 'TRUE', 'TRUE');
END
				 };

sub update {
	my ($dbVersion, $dbh) = @_;

	foreach my $u ( sort keys %{$updates} ){
		if ( Perl::Version->new($u)->numify > $dbVersion->numify ){
			my $batch = DBIx::MultiStatementDo->new( dbh => $dbh );
			$batch->do($updates->{$u})
				or die "Can't update config file.\n\tError: " . $batch->dbh->errstr . "\n";
		}
	}

	return 1;
}

1;

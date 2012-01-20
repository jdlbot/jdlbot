
my $dbUpdates = {
				 '0.1.1' => <<END,
UPDATE "config" SET value='0.1.1' WHERE param='version';
INSERT INTO "config" VALUES('check_update','TRUE');
END
				 '0.1.2' => <<END,
UPDATE "config" SET value='0.1.2' WHERE param='version';
INSERT INTO "config" VALUES('open_browser','TRUE');
END
				 '0.1.3' => <<END
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
				 };

sub dbUpdate {
	my ($dbVersion) = @_;
	
	foreach my $u ( sort keys %$dbUpdates ){
		if ( Perl::Version->new($u)->numify > $dbVersion->numify ){
			my $batch = DBIx::MultiStatementDo->new( dbh => $dbh );
			$batch->do($dbUpdates->{$u})
				or die "Can't update config file.\n\tError: " . $batch->dbh->errstr . "\n";
		}
	}
}

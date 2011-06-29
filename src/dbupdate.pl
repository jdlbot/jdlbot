
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

INSERT INTO "linktypes" VALUES ('megaupload.com', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('netload.in', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('depositfiles.com', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('duckload.com', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('jumbofiles.com', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('letitbit.net', 50, 'TRUE');
INSERT INTO "linktypes" VALUES ('megashare.com', 50, 'TRUE');

INSERT INTO "linktypes" VALUES('2shared.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('4ppl.ru', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('4share.ws', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('Badongo.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('Ifolder.ru', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('bigupload.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('cobrashare.sk', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('creafile.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('czshare.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('dataup.to', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('demo.ovh.net', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('edisk.cz', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('egoshare.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('extabit.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('filebase.to', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('filebox.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('filedropper.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('filelobster.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('filer.cx', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('files.to', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('files.youmama.ru', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('filesavr.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('fileshare.in.ua', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('filestore.com.ua', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('filesurf.ru', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('freefolder.net', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('funfile.info', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('gigapeta.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('gigaup.fr', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('hellshare.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('hostuje.net', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('ifile.it', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('letitfile.ru', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('linkfile.de', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('mega.1280.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('midupload.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('mooshare.net', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('netgull.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('only4files.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('openfile.ru', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('pixelhit.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('quickshare.cz', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('savefile.ro', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('share-online.biz', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('sharearound.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('shareflare.net', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('sharehoster.de', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('tab.net.ua', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('teradepot.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('turbobit.net', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('ultraupload.info', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('up.4share.vn', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('upload.com.ua', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('upload.xradio.ru', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('uptal.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('web-share.net', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('xshareware.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('xun6.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('youload.to', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('yourfilehost.com', 100, 'TRUE');
INSERT INTO "linktypes" VALUES('ziddu.com', 100, 'TRUE');
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

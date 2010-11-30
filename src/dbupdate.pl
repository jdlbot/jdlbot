
my $dbUpdates = {
				 '0.1.1' => <<END,
UPDATE "config" SET value='0.1.1' WHERE param='version';
INSERT INTO "config" VALUES('check_update','TRUE');
END
				 '0.1.2' => <<END
UPDATE "config" SET value='0.1.2' WHERE param='version';
INSERT INTO "config" VALUES('open_browser','TRUE');
END
				 };

sub dbUpdate {
	my ($dbVersion) = @_;
	
	foreach my $u ( sort keys %$dbUpdates ){
		if ( Perl::Version->new($u)->numify > $dbVersion->numify ){
			my $batch = DBIx::MultiStatementDo->new( dbh => $dbh );
			$batch->do($dbUpdates->{$u});
			if ( $batch->dbh->errstr ){
				die "Can't update config file.\n";
			}
		}
	}
}

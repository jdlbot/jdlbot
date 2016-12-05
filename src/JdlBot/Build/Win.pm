
package JdlBot::Build::Win;

use strict;
use warnings;

use File::Copy;
use File::Find;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(loadTemplates loadStatic loadAssets checkConfigFile openBrowser);

sub loadFile {
 	my $path = $_[0];
 	my $content = PAR::read_file($path);
 	return $content;
}

sub loadTemplates {
	our %templates = ();
	$templates{'base'} = Text::Template->new(TYPE => 'STRING',  SOURCE => PAR::read_file('base.html'));
	$templates{'config'} = Text::Template->new(TYPE => 'STRING',  SOURCE => PAR::read_file('config.html'));
	$templates{'status'} = Text::Template->new(TYPE => 'STRING',  SOURCE => PAR::read_file('status.html'));
	
	return %templates;
}

sub loadAssets {
	my %assets = ();
	find(sub {
		my $content = loadFile($_) if -f;
		my $mime;
		if ( $_ =~ /.js$/ ) {
			$mime = 'text/javascript';
		} elsif ( $_ =~ /.css$/ ) {
			$mime = 'text/css';
		} else {
			$mime = '';
		}
		$assets{"/".$File::Find::name} = sub {
		my ($httpd, $req) = @_;

		$req->respond({ content => [$mime, $content] });
		}
	}, 'assets/');
	
	
	return %assets;
}

sub loadStatic {
	my $static = {};
	my @staticFiles = (
		'filters.html',
		'feeds.html',
		'linktypes.html'
	);
	foreach my $file (@staticFiles) {
		$static->{$file} = loadFile($file);
	}

	return $static;
}

sub checkConfigFile {
	my $configdir = (dir($ENV{'APPDATA'} , 'jdlbot'))->stringify;
	if ( ! -d $configdir ){
		make_path($configdir);
	}

	my $configfile = (file($configdir, 'config.sqlite'))->stringify;
	if(! -f $configfile){
		my $cfgToCopy = (file($ENV{'PAR_TEMP'}, 'inc', 'config.sqlite'))->stringify;
		copy($cfgToCopy, $configfile);
	}

	return $configfile;
}

sub openBrowser {
	`start http://127.0.0.1:$main::config{'port'}/`;
	return 1;
}

1;

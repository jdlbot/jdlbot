
package JdlBot::Build::Perl;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(%templates $static loadSupportFiles checkConfigFile openBrowser);

sub loadSupportFiles {
	our %templates = ();
	$templates{'base'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'base.html');
	$templates{'config'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'config.html');
	$templates{'status'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'status.html');

	our $static = {};
	my $file;
	open($file, '<', 'filters.html');
	$static->{'filters'} = join("", <$file>);
	close($file);

	open($file, '<', 'feeds.html');
	$static->{'feeds'} = join("", <$file>);
	close($file);

	open($file, '<', 'linktypes.html');
	$static->{'linktypes'} = join("", <$file>);
	close($file);

	open($file, '<', 'main.css');
	$static->{'css'} = join("", <$file>);
	close($file);

	open($file, '<', 'jquery.bt.js');
	$static->{'bt.js'} = join("", <$file>);
	close($file);

	open($file, '<', 'jdlbot_logo.png');
	binmode($file);
	$static->{'logo'} = join("", <$file>);
	close($file);

	open($file, '<', 'favicon.ico');
	binmode($file);
	$static->{'favicon'} = join("", <$file>);
	close($file);

	return 1;
}

sub checkConfigFile {
	if ( -f 'config.sqlite' ){
		return 'config.sqlite';
	} else {
		return 0;
	}
}

sub openBrowser {
	#Do nothing
	return 1;
}

1;

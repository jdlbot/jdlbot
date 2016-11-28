
package JdlBot::Build::Perl;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(loadTemplates loadStatic checkConfigFile openBrowser);

sub loadTemplates {
	my %templates = ();
	$templates{'base'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'base.html');
	$templates{'config'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'config.html');
	$templates{'status'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'status.html');
	
	return %templates;
}

sub loadStatic {
	my $static = {};
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

	return $static;
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

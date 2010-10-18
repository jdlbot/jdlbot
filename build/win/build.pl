#!perl

use File::Copy;

sub loadSupportFiles {
	%templates = ();
	$templates{'base'} = Text::Template->new(TYPE => 'STRING',  SOURCE => PAR::read_file('base.html'));
	$templates{'config'} = Text::Template->new(TYPE => 'STRING',  SOURCE => PAR::read_file('config.html'));
	
	$static = {};
	$static->{'filters'} = PAR::read_file('filters.html');
	$static->{'feeds'} = PAR::read_file('feeds.html');
	$static->{'css'} = PAR::read_file('main.css');
	$static->{'bt.js'} = PAR::read_file('jquery.bt.js');
	$static->{'logo'} = PAR::read_file('jdlbot_logo.png');
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

return 1;
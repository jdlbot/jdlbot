#!perl

sub loadSupportFiles {
	%templates = ();
	$templates{'base'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'base.html');
	$templates{'config'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'config.html');
	$templates{'status'} = Text::Template->new(TYPE => 'FILE',  SOURCE => 'status.html');
	
	$static = {};
	open(FILTERSFILE, '<filters.html');
	$static->{'filters'} = join("", <FILTERSFILE>);
	close(FILTERSFILE);
	
	open(FEEDSFILE, '<feeds.html');
	$static->{'feeds'} = join("", <FEEDSFILE>);
	close(FEEDSFILE);
	
	open(CSSFILE, '<main.css');
	$static->{'css'} = join("", <CSSFILE>);
	close(CSSFILE);

	open(BTJSFILE, '<jquery.bt.js');
	$static->{'bt.js'} = join("", <BTJSFILE>);
	close(BTJSFILE);
	
	open(LOGOFILE, '<jdlbot_logo.png');
	binmode(LOGOFILE);
	$static->{'logo'} = join("", <LOGOFILE>);
	close(LOGOFILE);

	open(FAVICONFILE, '<favicon.ico');
	binmode(FAVICONFILE);
	$static->{'favicon'} = join("", <FAVICONFILE>);
	close(FAVICONFILE);
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
}

return 1;
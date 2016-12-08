
package JdlBot::Build::Perl;

use strict;
use warnings;

use File::Find;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(loadTemplates loadStatic loadAssets checkConfigFile openBrowser);

sub loadFile {
 	my $path = $_[0];
 	my $file;
 	open( $file, '<', $path);
 	my $content = join( "", <$file> );
 	close($file);
 	return $content;
}

sub loadTemplates {
	my %templates = ();
	$templates{'base'} =
	  Text::Template->new( TYPE => 'FILE', SOURCE => 'base.html' );
	$templates{'config'} =
	  Text::Template->new( TYPE => 'FILE', SOURCE => 'config.html' );
	$templates{'status'} =
	  Text::Template->new( TYPE => 'FILE', SOURCE => 'status.html' );

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
	if ( -f 'config.sqlite' ) {
		return 'config.sqlite';
	}
	else {
		return 0;
	}
}

sub openBrowser {

	#Do nothing
	return 1;
}

1;


package JdlBot::LinkHandler::JD2;

use strict;
use warnings;

use LWP::Simple qw($ua get);
use URI::Escape;
use Data::Dumper;

use JdlBot::UA;

$ua->timeout(5);
$ua->agent(JdlBot::UA::getAgent() );

#  Returns 1 for success, 0 for failure.
sub processLinks {
	my ( $links, $filter, $dbh, $config ) = @_;

	if ( $filter->{'enabled'} eq 'FALSE' ) { return 0; }

	my $jdInfo =
	  $config->{'jd_address'} . ":" . $config->{'jd_port'} . "/flash";
	my $jdStart = $filter->{'autostart'} eq 'TRUE' ? 1 : 0;

	my $c = get("http://$jdInfo/");
	if ( !$c ) { return 0; }

	my $newlinks = join( "\r\n", @$links );
	my $response;
	$newlinks = uri_escape($newlinks);
	if ($jdStart) {
		$response = $ua->post(
			"http://$jdInfo/add",
			[
				'source'    => 'http://localhost/',
				'urls'      => $newlinks,
				'autostart' => 1
			]
		);
		
	}
	else {
		$response = $ua->post( "http://$jdInfo/add",
			[ 'source' => 'http://localhost/', 'urls' => $newlinks ] );
	}
	if ( $response->is_success  ){
		print STDERR " success.\n";
		if ( $filter->{'stop_found'} eq 'TRUE' ) {
			$filter->{'enabled'} = 'FALSE';
			my $qh =
			  $dbh->prepare(q( UPDATE filters SET enabled='FALSE' WHERE title=? ));
			$qh->execute( $filter->{'title'} );
		}
		return 1;
	} else {
		print STDERR " failed.\n";
		return 0;
	}
}


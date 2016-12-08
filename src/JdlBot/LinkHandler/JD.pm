
package JdlBot::LinkHandler::JD;

use strict;
use warnings;

use Web::Scraper;
use LWP::Simple qw($ua get);
use URI::Escape;

use JdlBot::UA;

$ua->timeout(5);
$ua->agent(JdlBot::UA::getAgent());

#  Returns 1 for success, 0 for failure.
sub processLinks {
	my ( $links, $filter, $dbh, $config ) = @_;
	
	if ( $filter->{'enabled'} eq 'FALSE' ){ return 0; }
	
	my $jdInfo = $config->{'jd_address'} . ":" . $config->{'jd_port'};
	my $jdStart = $filter->{'autostart'} eq 'TRUE' ? 1 : 0;

	my $c = get("http://$jdInfo/link_adder.tmpl");
	if (! $c ){ return 0; }

	my $s = scraper {
		process "tr.package", "packages[]" => scraper {
			process 'input[name="package_all_add"]', num => '@value';
			process 'input[type="text"]', name => '@value';
		};
		process "tr.downloadoffline", "offline[]" => scraper {
			process 'input[name="package_single_add"]', onum => '@value';
		};
		process "tr.downloadoffline, tr.downloadonline", "files[]" => scraper {
			process 'input[name="package_single_add"]', fnum => '@value';
			process 'td[style="padding-left: 30px;"]', name => 'TEXT';
		};
	};
	
	my $res = $s->scrape($c);
	
	my $highest = -1;
	if ( $res->{packages} ){
		$highest = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{num};
	}
	my $newlinks = join("\r\n", @$links);
	$newlinks = uri_escape($newlinks);
	my $response = $ua->post("http://$jdInfo/link_adder.tmpl", Content => 'do=Add&addlinks=' . $newlinks);
	
	if ($response->is_success){
		$res = $s->scrape($response->decoded_content);
		#  Sometimes the web interface doesn't return right away with an updated linkgrabber queue
		my $count = 0;
		my $nexthighest = $highest;
		while ( $nexthighest == $highest ){
			if( $count > 10 ){
				print STDERR "Failed to parse jDownloader Web Interface output.\n" .
							  "\tLinks might already be in linkgrabber queue\n" ;
				return 0;
			}
			$res = $s->scrape(get("http://$jdInfo/link_adder.tmpl"));
			
			sleep(1);
			if( $res->{packages} ){
				if( $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{num} > $highest ){
					$nexthighest = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{num};
				}
			}
			$count++;
		}
		#if ( ! keys %$res ){ return; }
		
		my $nexthighestName = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{name};
		
		# Wait for JDownloader to scrape the sent links
		#  This can result in changes to the number of packages added as JD does its magic
		while ($nexthighestName eq 'Unchecked'){
			$c = get("http://$jdInfo/link_adder.tmpl");
			$res = $s->scrape($c);
		
			$nexthighest = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{num};
			$nexthighestName = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{name};
		}
		my $singleFiles = '';
		my @high_range = ($highest + 1)..$nexthighest;
		foreach my $file (@{$res->{files}}){
			foreach(@high_range){
				if ( index($file->{fnum}, $_) == 0 ){
					$file->{fnum} =~ s/ /+/g;
					$singleFiles .= 'package_single_add=' . $file->{fnum} . '&';
				}
			}
		}
		
		my $contentString = 'do=Submit&package_all_add=' . join('&package_all_add=',@high_range) .
							'&' . $singleFiles . 'selected_dowhat_link_adder=';
		
		if ( $res->{offline} ){
			foreach my $link (@{$res->{offline}}){
				foreach(@high_range){
					if( index($link->{onum}, $_) == 0 ){
						$ua->post("http://$jdInfo/link_adder.tmpl", Content => $contentString . 'remove');
						
						print STDERR "Links offline for : " . $filter->{'title'} . " removing.\n";
						
						return 0;
					}
				}
			}
		}

		# This looks convoluted, but it checks to see if there are missing part* files or r* files for the links added
		{
			my $test_name = sub {
				if ( $_->{name} =~ /\.part(\d+)\.rar/i ){
					return $1;
				} else {
					return "";
				}
			};
			
			my $test_package = sub {
				my $package = shift;
				if ( scalar(grep {$package->{num} == $_} @high_range) > 0 ) {
					return 1;
				} else {
					return 0;
				}
			};
			
			my @packages = grep {$test_package->($_)} @{$res->{packages}};
			
			if (scalar(@packages) == 1){
				if ( $packages[0]->{name} =~ m/sample\.(avi|mkv)$/i ){
					$ua->post("http://$jdInfo/link_adder.tmpl", Content => $contentString . 'remove');
						
					print STDERR "Only sample file matched filter : " . $filter->{'title'} . " removing.\n";
					
					return 0;
				}
			}
			
			PACKAGES: foreach my $package (@packages){
				my @matches = grep {index($_->{name}, $package->{name}) == 0} @{$res->{files}};
				my @results = sort {$a <=> $b} grep {$_ ne ""} map {$test_name->($_)} @matches;
				
				if ( ! @results ){ next PACKAGES; }
				my @result_range = 1..($results[scalar(@results) - 1 >= 0 ? scalar(@results) - 1 : 0]);
				
				# Checks to see if the guessed number of parts are present or if a single "part" is present
				#  Why a fail on a single "part#" ?  Because things are split into parts when there are MULTIPLE.
				#  If a ".part1" is returned, then we need to detect and fail on this condition.
				if ( scalar(@results) != scalar(@result_range) || scalar(@results) == 1 ){
					$ua->post("http://$jdInfo/link_adder.tmpl", Content => $contentString . 'remove');
						
					print STDERR "Links missing parts for : " . $filter->{'title'} . " removing.\n";
					
					return 0;
				}
			}
		}
		
		if ( $jdStart ) {
			$ua->post("http://$jdInfo/link_adder.tmpl", Content => $contentString . 'add');
			$ua->post("http://$jdInfo/index.tmpl", Content => 'do=start');
		}
		if ( $filter->{'stop_found'} eq 'TRUE' ){
			$filter->{'enabled'} = 'FALSE';
			my $qh = $dbh->prepare(q( UPDATE filters SET enabled='FALSE' WHERE title=? ));
			$qh->execute($filter->{'title'});
		}
		
		return 1;
		
	} else {
		print STDERR "Failed to connect to JD : " . $response->status_line . "\n";
		return 0;
	}

	print "Got to the end of JD::process\n";
	return 0;
}

1;

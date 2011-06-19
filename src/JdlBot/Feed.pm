
package JdlBot::Feed;

use XML::FeedPP;
use Error qw(:try);
use AnyEvent::HTTP;

use JdlBot::UA;
use JdlBot::TV;
use JdlBot::LinkHandler::JD;

$AnyEvent::HTTP::USERAGENT = JdlBot::UA::getAgent();

sub scrape {
	my ($url, $feedData, $filters, $follow_links, $dbh, $config) = @_;
	my $rss;
	my $parseError = 0;
	try {
		$rss = XML::FeedPP->new($feedData);
	} catch Error with {
		$parseError = 1;
	};
	
	if ( $parseError ){ print STDERR "Error parsing Feed: " . $url . "\n"; return; }
	
	foreach my $item ( $rss->get_item() ){
		
		foreach my $filter ( keys %{ $filters } ){
			my $match = 0;
			if ( $filters->{$filter}->{'regex1'} eq 'TRUE' ){
				my $reFilter = $filters->{$filter}->{'filter1'};
				if ( $item->title() =~ /$reFilter/ ){
					$match = 1;
				}
			} else {
				if ( index( $item->title() , $filters->{$filter}->{'filter1'} ) >= 0 ){
					$match = 1;
				}
			}
			
			if ($match){
				if ( $filters->{$filter}->{'tv'} eq 'TRUE' ){
					if ( JdlBot::TV::checkTvMatch($item->title(), $filters->{$filter}, $dbh)  ){
						# continue
					} else {
						next;
					}
				}
				if ( ! $filters->{$filter}->{'matches'} ){ $filters->{$filter}->{'matches'} = []; }
				push(@{$filters->{$filter}->{'matches'}}, $item->description());
				
				if ( $follow_links eq 'TRUE' ){
					$filters->{$filter}->{'outstanding'} += 1;
					
					my $return_outstanding = sub {
						if ( $filters->{$filter}->{'outstanding'} == 0 ){
							findLinks($filters->{$filter}, $dbh, $config);
						}
					};
					
					http_get( $item->link() , sub {
							my ($body, $hdr) = @_;
					
							if ($hdr->{Status} =~ /^2/) {
								if ( $filters->{$filter}->{'filter2'} ){
									my $match = 0;
									if ( $filters->{$filter}->{'regex2'} eq 'TRUE' ){
										my $reFilter = $filters->{$filter}->{'filter2'};
										if ( $body =~ /$reFilter/ ){
											$match = 1;
										}
									} else {
										if ( index( $body , $filters->{$filter}->{'filter2'} ) >= 0 ){
											$match = 1;
										}
									}
									
									if ($match){
										push(@{$filters->{$filter}->{'matches'}}, $body);
									}
								} else {
									push(@{$filters->{$filter}->{'matches'}}, $body);
								}
							} else {
							   print STDERR "HTTP error, $hdr->{Status} $hdr->{Reason}\n" .
											"\tFailed to follow link: " . $item->link() . " for feed: $url\n";
							}
							$filters->{$filter}->{'outstanding'} -= 1;
							$return_outstanding->();
						});
				}
			}
		}
	}
	
	if ( $follow_links eq 'TRUE' ){ return; }
	
	foreach my $filter ( keys %{ $filters } ){
		findLinks($filters->{$filter}, $dbh, $config);
	}
}

sub findLinks {
	my ($filter, $dbh, $config) = @_;
	
	my $regex;
	if ( $filter->{'link_types'} ){
		$regex = $filter->{'link_types'};
		$regex = qr/$regex/;
	} else {
		$regex = qr/megaupload|netload.in|depositfiles.com/;
	}
	
	my $count = 0;
	CONTENT: foreach my $content ( @{$filter->{'matches'}} ){
		
		# This little bit of ugliness pulls out all the links in a document
		my @links = ( $content =~ /\b(([\w-]+:\/\/?|www[.])[^\s()<>]+(?:\([\w\d]+\)|([^[:punct:]\s]|\/)))/g );
		my $prevLink;
		my $linksToProcess = [];
		foreach my $link (@links){
			my ($linkType) = ( $link =~ /^http:\/\/([^\/]+)\// );
			if ( ! $linkType ){ next; }
			
			# If the link type is appropriate;
			#   This needs to be replaced by a function that checks against a list of domains
			if ( $linkType =~ $regex ){
				if ($filter->{'proc_all'} eq 'TRUE'){ push(@$linksToProcess, $link); next; }
				
				if ( ! $prevLink ){ $prevLink = $linkType; }
				
				if ( $linkType eq $prevLink ){
					push(@$linksToProcess, $link);
				} else {
					last;
				}
			}
			if ( $prevLink ){ $prevLink = $linkType; }
		}
		
		if ( scalar @$linksToProcess > 0 ){
			if ( $filter->{'tv'} eq 'TRUE' ){
				unless ( $filter->{'new_tv_last_has'} ){
					$filter->{'new_tv_last_has'} = [];
				}
				foreach my $tvhas ( @{$filter->{'new_tv_last_has'}}){
					if ( $filter->{'new_tv_last'}->[$count] eq $tvhas ){
						next CONTENT;
					}
				}
				# Status message?
				print STDERR "Sending links for filter: " . $filter->{'title'} . "\n";
				if (JdlBot::LinkHandler::JD::processLinks($linksToProcess, $filter, $dbh, $config)){
					my $qh = $dbh->prepare('UPDATE filters SET tv_last=? WHERE title=?');
					$qh->execute($filter->{'new_tv_last'}->[0], $filter->{'title'});
					push(@{$filter->{'new_tv_last_has'}}, $filter->{'new_tv_last'}->[$count]);
				}
				#sendToJd($linksToProcess, $filter);
			} else {
				print STDERR "Sending links for filter: " . $filter->{'title'} . "\n";
				if(JdlBot::LinkHandler::JD::processLinks($linksToProcess, $filter, $dbh, $config)){
					return;
				}
			}
		}
		
		$count++;
	}
}

# sendToJd is to remain synchronous for the time being.

1;


package JdlBot::Feed;

use strict;
use warnings;

use Data::Dumper;

use XML::FeedPP;
use Error qw(:try);
use AnyEvent::HTTP;
use List::MoreUtils qw(uniq);

use JdlBot::UA;
use JdlBot::TV;
use JdlBot::LinkHandler::JD2;

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
				push(@{$filters->{$filter}->{'matches'}}, $item->link());
				
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

	return 0;
}

sub findLinks {
	my ($filter, $dbh, $config) = @_;
	
	my $linkhosts = [];
	if ( $filter->{'link_types'} ){
		my $regex = $filter->{'link_types'};
		$linkhosts->[0] = $regex;
	} else {
		$linkhosts = $dbh->selectall_arrayref("SELECT linkhost FROM linktypes WHERE enabled='TRUE' ORDER BY priority");
	}
	
	my $count = 0;
	CONTENT: foreach my $content ( @{$filter->{'matches'}} ){
		
		# This little bit of ugliness pulls out all the links in a document
		my @links = ( $content =~ /\b(([\w-]+:\/\/?|www[.])[^\s()<>]+(?:\([\w\d]+\)|([^[:punct:]\s]|\/)))/g );
		my $prevLink;
		my $linksToProcess = [];
		foreach my $linkhost ( @{$linkhosts} ){

			my $regex = $linkhost->[0];
			$regex = qr/$regex/;
			foreach my $link (@links){
				my ($linkType) = ( $link =~ /^http:\/\/([^\/]+)\// );
				if ( ! $linkType ){ next; }
				
				# If the link type is appropriate;
				#   This needs to be replaced by a function that checks against a list of domains
				if ( $linkType =~ $regex ){
					push(@$linksToProcess, $link);
				}
			}

			if ( scalar @$linksToProcess > 0 ){
				@$linksToProcess = uniq(@$linksToProcess);
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
					print STDERR "Sending links for filter: " . $filter->{'title'} . " ...";
					if (JdlBot::LinkHandler::JD2::processLinks($linksToProcess, $filter, $dbh, $config)){
						my $qh = $dbh->prepare('UPDATE filters SET tv_last=? WHERE title=?');
						$qh->execute($filter->{'new_tv_last'}->[0], $filter->{'title'});
						push(@{$filter->{'new_tv_last_has'}}, $filter->{'new_tv_last'}->[$count]);
						next CONTENT;
					} else {
						$linksToProcess = [];
					}
					#sendToJd($linksToProcess, $filter);
				} else {
					print STDERR "Sending links for filter: " . $filter->{'title'} . " ...";
					if(JdlBot::LinkHandler::JD2::processLinks($linksToProcess, $filter, $dbh, $config)){
						return;
					} else {
						$linksToProcess = [];
					}
				}
			}
		}
		
		$count++;
	
	}

	return 0;
}

# sendToJd is to remain synchronous for the time being.

1;

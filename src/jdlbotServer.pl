use EV;
use AnyEvent::Impl::EV;
use AnyEvent::HTTPD;
use AnyEvent::HTTP;
$AnyEvent::HTTP::USERAGENT = 'Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US; rv:1.9.2.10) Gecko/20100914 Firefox/3.6.10 ( .NET CLR 3.5.30729)';

use PAR;

use Data::Dumper;
use Error qw(:try);

use Path::Class;
use File::Path qw(make_path remove_tree);
use Text::Template;
use XML::FeedPP;
use Web::Scraper;
use LWP::Simple qw($ua get);
use JSON::XS;
use URI::Escape;
use Getopt::Long;
use Perl::Version;
use DBI;
use DBIx::MultiStatementDo;
use Moose::Meta::Object::Trait;

require('build.pl');

$ua->timeout(5);

# Encapsulate configuration code
{
	my $port;
	my $directory = "";
	my $configdir = "";
	my $configfile = "";
	my $versionFlag;
	
	my $version = Perl::Version->new("0.1.1");
	
	GetOptions("port=i" => \$port,
			   "directory=s" => \$directory,
			   "configdir=s" => \$configdir,
			   "version" => \$versionFlag);
	
	if( $versionFlag ){
		print STDERR "jDlBot! version $version\n";
		exit(0);
	}
	
	if( $directory ){
		chdir($directory);
	}
	
	my $configFile = checkConfigFile();
	unless ( $configFile ){
		die "Could not find config file.\n";
	}
	
	$dbh = DBI->connect("dbi:SQLite:dbname=$configFile","","") or
		die "Could not open config file.\n";
	%config = fetchConfig();
	
	#if (! $config{'version'}){ $config{'version'} = "0.1.0"; }
	my $dbVersion = Perl::Version->new($config{'version'});
	if ( $version->numify > $dbVersion->numify ){
		print STDERR "Updating config...\n";
		
		require 'dbupdate.pl';
		dbUpdate($dbVersion);
		
		print STDERR "Update successful.\n";
	}

	if( $port ){
		$config{'port'} = $port;
	}
}

loadSupportFiles();

sub fetchConfig {
	my $configArrayRef = $dbh->selectall_arrayref( q( SELECT param, value FROM config ) )
		or die "Can't fetch configuration\n";
	
	my %tempConfig = ();
	foreach my $cfgParam (@$configArrayRef){
		$tempConfig{$$cfgParam[0]} = $$cfgParam[1];
	}
	
	return %tempConfig;
}

$watchers = {};
sub addWatcher {
	my ($url, $interval, $follow_links) = @_;
	
	$watchers->{$url} = AnyEvent->timer(
										after		=>	5,
										interval	=>	$interval * 60,
										cb			=>	sub {
											print STDERR "Running watcher: " . $url . "\n";
											
											my $qh = $dbh->prepare(q( SELECT * FROM filters WHERE enabled='TRUE' AND feeds LIKE ? ));
											$qh->execute('%"' . $url . '"%');
											my $filters = $qh->fetchall_hashref('title');
											
											if ( $qh->errstr || scalar keys %{ $filters } < 1 ){ return; }
											http_get( "http://$url" , sub {
													my ($body, $hdr) = @_;
											
													if ($hdr->{Status} =~ /^2/) {
														scrapeRss($url, $body, $filters, $follow_links);
													} else {
														print STDERR "HTTP error, $hdr->{Status} $hdr->{Reason}\n" .
																	"\tFailed to retrieve feed: $url\n";
													}
												});
										});
}

{
	my $feeds = $dbh->selectall_arrayref(q( SELECT url, interval, follow_links FROM feeds WHERE enabled='TRUE' ));
	foreach my $feed (@{$feeds}){
		addWatcher($feed->[0], $feed->[1], $feed->[2]);
	}
}

sub removeWatcher {
	my $url = shift;
	
	delete($watchers->{$url});
}


sub scrapeRss {
	my ($url, $feedData, $filters, $follow_links) = @_;
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
					if ( checkTvMatch($item->title(), $filters->{$filter}) ){
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
							findLinks($filters->{$filter});
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
		findLinks($filters->{$filter});
	}
}

sub checkTvMatch {
	my ( $title , $filter ) = @_;
	my $tv_type;
	my $tv_last;
	
	if ( $filter->{'tv_last'} ){
		$tv_last = determineTvType( $filter->{'tv_last'} );
		if ( ! $filter->{'new_tv_last'} ){ $filter->{'new_tv_last'} = []; }
	}
	$tv_type = determineTvType( $title );
	unless( $tv_type ){ return 0; }
	
	if ( $tv_last ){
		if ( $tv_last->{'type'} eq 's' && $tv_type->{'type'} eq 's' ){
			if ( $tv_type->{'info'}->{'s'} . $tv_type->{'info'}->{'e'} > $tv_last->{'info'}->{'s'} . $tv_last->{'info'}->{'e'} ){
				push(@{$filter->{'new_tv_last'}}, "S" . $tv_type->{'info'}->{'s'} . "E" . $tv_type->{'info'}->{'e'});
				return 1;
			} else {
				return 0;
			}
		} elsif ( $tv_last->{'type'} eq 'd' && $tv_type->{'type'} eq 'd' ){
			if (  $tv_type->{'info'}->{'d'} - $tv_last->{'info'}->{'d'} > 0 ) {
				push(@{$filter->{'new_tv_last'}}, $tv_type->{'info'}->{'s'});
				return 1;
			} else {
				return 0;
			}
		} else {
			return 0;
		}
	} else {
		if ( $tv_type->{'type'} eq 's' ){
			push(@{$filter->{'new_tv_last'}}, "S" . $tv_type->{'info'}->{'s'} . "E" . $tv_type->{'info'}->{'e'});
			return 1;
		} elsif ( $tv_type->{'type'} eq 'd' ) {
			push(@{$filter->{'new_tv_last'}}, $tv_type->{'info'}->{'s'});
			return 1;
		}
	}
}

sub determineTvType {
	my ( $s ) = @_;
	my $tv_info = {};
	
	if ( $s =~ /s(\d{2})e(\d{2})/i ){
		$tv_info->{'type'} = 's';
		$tv_info->{'info'} = { 's' => $1, 'e' => $2 };
	} elsif ( $s =~ /(\d{4}).?(\d{2}).?(\d{2})/ ){
		$tv_info->{'type'} = 'd';
		$tv_info->{'info'} = { 'd' => "$1$2$3", 's' => "$1.$2.$3" };
	} else {
		$tv_info = undef;
	}
	
	return $tv_info;
}

sub findLinks {
	my ($filter) = @_;
	
	my $regex;
	if ( $filter->{'link_types'} ){
		$regex = $filter->{'link_types'};
		$regex = qr/$regex/;
	} else {
		$regex = qr/megaupload|netload.in|depositfiles.com/;
	}
	
	my $count = 0;
	CONTENT: foreach my $content ( @{$filter->{'matches'}} ){
		
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
				my $qh = $dbh->prepare('UPDATE filters SET tv_last=? WHERE title=?');
				$qh->execute($filter->{'new_tv_last'}->[0], $filter->{'title'});
				push(@{$filter->{'new_tv_last_has'}}, $filter->{'new_tv_last'}->[$count]);
				
				# Status message?
				print STDERR "Sending links for filter: " . $filter->{'title'} . "\n";
				sendToJd($linksToProcess, $filter);
			} else {
				print STDERR "Sending links for filter: " . $filter->{'title'} . "\n";
				sendToJd($linksToProcess, $filter);
				return;
			}
		}
		
		$count++;
	}
}

#  Old link adding code using the remote control jDownloader interface.
#
#sub sendToJd {
#	my ( $links, $filter ) = @_;
#	
#	if ( $filter->{'enabled'} eq 'FALSE' ){ return; }
#	
#	my $jdInfo = $config{'jd_address'} . ":" . $config{'jd_port'};
#	my $jdStart = $filter->{'autostart'} eq 'TRUE' ? 1 : 0;
#	my $jdGrab = $filter->{'show_linkgrab'} eq 'TRUE' ? 1 : 0;
#	
#	@$links = map { uri_escape($_, "?&"); } @$links;
#	
#	#my $url = "http://$jdInfo/action/add/links/grabber$jdGrab/start$jdStart/" . join(' ', @$links);
#	#print "$url\n\n";
#
#	my $sendLink = sub {
#		my $sendLink = shift;
#		
#		my $link = shift(@$links);
#		my $url = "http://$jdInfo/action/add/links/grabber$jdGrab/start$jdStart/$link";
#		print $url . "\n";
#		http_get( $url , sub {
#				my ($body, $hdr) = @_;
#		  
#				if ($hdr->{Status} =~ /^2/) {
#					if (scalar @$links > 0){
#						$sendLink->($sendLink);
#					} else {
#					
#						if ( $filter->{'stop_found'} eq 'TRUE' ){
#							$filter->{'enabled'} = 'FALSE';
#							my $qh = $dbh->prepare(q( UPDATE filters SET enabled='FALSE' WHERE title=? ));
#							$qh->execute($filter->{'title'});
#							
#							print $qh->errstr . "\n"
#						}
#					}
#					
#					print "$body\n";
#				   #scrapeRss($url, $body, $filters);
#				} else {
#				   print "error, $hdr->{Status} $hdr->{Reason}\n";
#				}
#			});
#	};
#	$sendLink->($sendLink);
#}

sub sendToJd {
	my ( $links, $filter ) = @_;
	
	if ( $filter->{'enabled'} eq 'FALSE' ){ return; }
	
	my $jdInfo = $config{'jd_address'} . ":" . $config{'jd_port'};
	my $jdStart = $filter->{'autostart'} eq 'TRUE' ? 1 : 0;

	my $c = get("http://$jdInfo/link_adder.tmpl");
	if (! $c ){ return; }

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
				return;
			}
			$res = $s->scrape(get("http://$jdInfo/link_adder.tmpl"));
			
			if( $res->{packages} ){
				if( $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{num} > $highest ){
					$nexthighest = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{num};
				}
			}
			$count++;
		}
		#if ( ! keys %$res ){ return; }
		
		my $nexthighestName = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{name};
		
		while ($nexthighestName eq 'Unchecked'){
			$c = get("http://$jdInfo/link_adder.tmpl");
			$res = $s->scrape($c);
		
			$nexthighest = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{num};
			$nexthighestName = $res->{packages}->[(scalar @{$res->{packages}}) - 1]->{name};
		}
		my $singleFiles = '';
		foreach my $file (@{$res->{files}}){
			foreach(($highest + 1)..$nexthighest){
				if ( index($file->{fnum}, $_) == 0 ){
					$file->{fnum} =~ s/ /+/g;
					$singleFiles .= 'package_single_add=' . $file->{fnum} . '&';
				}
			}
		}
		
		my $contentString = 'do=Submit&package_all_add=' . join('&package_all_add=',(($highest + 1)..$nexthighest) ) .
							'&' . $singleFiles . 'selected_dowhat_link_adder=';
		
		my $isOffline = 0;
		if ( $res->{offline} ){
			LINKS: foreach my $link (@{$res->{offline}}){
				foreach(($highest + 1)..$nexthighest ){
					if( index($link->{onum}, $_) == 0 ){
						$isOffline = 1;
						$ua->post("http://$jdInfo/link_adder.tmpl", Content => $contentString . 'remove');
						
						print STDERR "Links offline for : " . $filter->{'title'} . " removing.\n";
						
						last LINKS;
					}
				}
			}
		}

		# This looks convoluted, but it checks to see if there are missing part* files or r* files for the links added
		if ( ! $isOffline ){
			my @high_range = ($highest + 1)..$nexthighest;
			my $test_name = sub {
				if ( $_->{name} =~ /\.part(\d+)/i ){
					return $1;
				} else {
					return undef;
				}
			};
			
			my $test_package = sub {
				my $package = shift;
				if ( scalar(grep($package->{num} == $_, @high_range)) > 0 ) {
					return 1;
				} else {
					return 0;
				}
			};
			
			my @packages = grep($test_package->($_), @{$res->{packages}});
			
			PACKAGES: foreach my $package (@packages){
				my @matches = grep(index($_->{name}, $package->{name}) == 0, @{$res->{files}});
				my @results = sort {$a <=> $b} grep($_ ne undef, map($test_name->($_), @matches));
				
				if ( ! @results ){ next PACKAGES; }
				my @result_range = 1..($results[scalar(@results) - 1 >= 0 ? scalar(@results) - 1 : 0]);
				
				if ( scalar(@results) != scalar(@result_range) ){
					$isOffline = 1;
					$ua->post("http://$jdInfo/link_adder.tmpl", Content => $contentString . 'remove');
						
					print STDERR "Links missing parts for : " . $filter->{'title'} . " removing.\n";
					last PACKAGES;
				}
			}
		}
		
		if ( ! $isOffline && $jdStart ) {
			$ua->post("http://$jdInfo/link_adder.tmpl", Content => $contentString . 'add');
			$ua->post("http://$jdInfo/index.tmpl", Content => 'do=start');
		}
		if ( ! $isOffline && $filter->{'stop_found'} eq 'TRUE' ){
			$filter->{'enabled'} = 'FALSE';
			my $qh = $dbh->prepare(q( UPDATE filters SET enabled='FALSE' WHERE title=? ));
			$qh->execute($filter->{'title'});
		}
		
	} else {
		print STDERR "Failed to connect to JD : " . $response->status_line . "\n";
	}
}


my $httpd = AnyEvent::HTTPD->new (host => '127.0.0.1', port => $config{'port'});
	print STDERR "Server running on port: $config{'port'}\n" .
	"Open http://127.0.0.1:$config{'port'}/ in your favorite web browser to continue.\n\n";
	
	openBrowser();

$httpd->reg_cb (
	'/' => sub {
		my ($httpd, $req) = @_;

		my $status;

		if ( get("http://$config{'jd_address'}:$config{'jd_port'}/") ){
			$status = 1
		} else {
			$status = 0;
		}

		my $statusHtml = $templates{'status'}->fill_in(HASH => {'port' => $config{'port'},
																'jd_address' => $config{'jd_address'},
																'jd_port' => $config{'jd_port'},
																'version' => $config{'version'},
																'check_update' => $config{'check_update'} eq 'TRUE' ? 'true' : 'false',
																'status' => $status
																});

		$req->respond ({ content => ['text/html', $templates{'base'}->fill_in(HASH => {'title' => 'Status', 'content' => $statusHtml}) ]});
	},
	'/config' => sub {
		my ($httpd, $req) = @_;
		if( $req->method() eq 'GET' ){
		
		
		my $configHtml = $templates{'config'}->fill_in(HASH => {'port' => $config{'port'},
																'jd_address' => $config{'jd_address'},
																'jd_port' => $config{'jd_port'},
																'check_update' => $config{'check_update'} eq 'TRUE' ? 'checked="checked"' : ''
																});
		$req->respond ({ content => ['text/html', $templates{'base'}->fill_in(HASH => {'title' => 'Configuration', 'content' => $configHtml}) ]});
		} elsif ( $req->method() eq 'POST' ){
			if( $req->parm('action') eq 'update' ){
				my $configParams = decode_json(uri_unescape($req->parm('data')));
				my $qh = $dbh->prepare('UPDATE config SET value=? WHERE param=?');
				foreach my $param (%$configParams){
					$qh->execute($configParams->{$param}, $param);
					if ( $qh->errstr ){ last; }
				}
				
				my $status;
				if ( ! $qh->errstr ){
					%config = fetchConfig();
					$status = 'success';
				} else {
					$status = 'Could not update config.  Try reloading jdlbot.';
				}
				
				$req->respond ({ content => ['application/json',  '{ "status" : "' . $status  . '" }' ]});
			}
		}
	},
	'/feeds' => sub {
		my ($httpd, $req) = @_;
		if( $req->method() eq 'GET' ){
		
		$req->respond ({ content => ['text/html', $templates{'base'}->fill_in(HASH => {'title' => 'Feeds', 'content' => $static->{'feeds'}}) ]});
		} elsif ( $req->method() eq 'POST' ){
			my $return = {'status' => 'failure'};
			if( $req->parm('action') =~ /add|update|enable/){
				my $feedParams = decode_json(uri_unescape($req->parm('data')));
				$feedParams->{'url'} =~ s/^http:\/\///;
				my $feedData = get('http://' . $feedParams->{'url'});
				
				if( $feedData ){
					my $rssFeed;
					my $parseError = 0;
					try {
						$rssFeed = XML::FeedPP->new($feedData);
					} catch Error with{
						$parseError = 1;
					};
					
					if( $rssFeed->title() && $parseError != 1){
						my $qh;
						if ( $req->parm('action') eq 'add' ){
							$qh = $dbh->prepare(q(INSERT INTO feeds VALUES ( ? , ? , ? , NULL, 'TRUE' )));
							$qh->execute($feedParams->{'url'}, $feedParams->{'interval'}, $feedParams->{'follow_links'});
							
							if ( !$qh->errstr ){
								my $qh = $dbh->prepare('SELECT * FROM feeds WHERE url=?');
								$qh->execute($feedParams->{'url'});
								$feedParams = $qh->fetchrow_hashref();
							}
							
						} elsif ( $req->parm('action') =~ /update|enable/ ){
							my $old_url = $feedParams->{'old_url'};
							delete($feedParams->{'old_url'});
							my @fields = sort keys %$feedParams;
							my @values = @{$feedParams}{@fields};
							$qh = $dbh->prepare(sprintf('UPDATE feeds SET %s=? WHERE url=?', join("=?, ", @fields)));
							push(@values, $old_url);
							$feedParams->{'old_url'} = $old_url;
							$qh->execute(@values);
							
							if ( !$qh->errstr ){
								removeWatcher($feedParams->{'old_url'});
								
								$qh = $dbh->prepare('SELECT title, feeds FROM filters WHERE feeds LIKE ? ');
								$qh->execute('%"' . $feedParams->{'old_url'} . '"%');
								my $filters = $qh->fetchall_hashref('title');
									
								if ( !$qh->errstr ){
									$qh = $dbh->prepare('UPDATE filters SET feeds=? WHERE title=?');
									foreach my $filter ( keys %{$filters} ){
										my $feeds = decode_json($filters->{$filter}->{'feeds'});
										my $new_feeds = [];
										foreach my $feed ( @{$feeds} ){
											if ( $feed ne $feedParams->{'old_url'} ){
												push(@$new_feeds, $feed);
											} else {
												push(@$new_feeds, $feedParams->{'url'});
											}
										}
										$qh->execute(encode_json($new_feeds), $filter);
									}
								}
							}
							
							if ( $req->parm('action') eq 'enable' ){
								my $qh = $dbh->prepare('SELECT * FROM feeds WHERE url=?');
								$qh->execute($feedParams->{'old_url'});
								$feedParams = $qh->fetchrow_hashref();
							}
	
						}
							
						if(!$qh->errstr){
							unless ( $feedParams->{'enabled'} eq 'FALSE' ){
								addWatcher($feedParams->{'url'}, $feedParams->{'interval'}, $feedParams->{'follow_links'});
							}
							$feedParams->{'status'} = 'success';
							$return = $feedParams;						
						} else {
							$return->{'status'} = "Could not save feed data, possibly a duplicate feed?";
						}
						
					} else {
						$return->{'status'} = "Did not parse properly as an RSS feed, check the url";
					}
				} else {
					$return->{'status'} = "Could not fetch RSS feed, check the url";
				}
			} elsif ( $req->parm('action') eq 'delete' ) {
				my $feedParams = decode_json(uri_unescape($req->parm('data')));
				$feedParams->{'url'} =~ s/^http:\/\///;
				
				$return->{'status'} = "Could not delete feed.  Incorrect url?";
				my $qh = $dbh->prepare('DELETE FROM feeds WHERE url=?');
				$qh->execute($feedParams->{'url'});
				$qh = $dbh->prepare('SELECT title, feeds FROM filters WHERE feeds LIKE ? ');
				$qh->execute('%' . $feedParams->{'url'} . '%');
				my $filters = $qh->fetchall_hashref('title');
					
				if ( !$qh->errstr ){
					$qh = $dbh->prepare('UPDATE filters SET feeds=? WHERE title=?');
					foreach my $filter ( keys %{$filters} ){
						my $feeds = decode_json($filters->{$filter}->{'feeds'});
						my $new_feeds = [];
						foreach my $feed ( @{$feeds} ){
							if ( $feed ne $feedParams->{'url'} ){
								push(@$new_feeds, $feed);
							}
						}
						$qh->execute(encode_json($new_feeds), $filter);
					}
				}
					
				if(!$qh->errstr){
					removeWatcher($feedParams->{'url'});
					$feedParams->{'status'} = 'success';
					$return = $feedParams;						
				}
			} elsif ( $req->parm('action') eq 'list' ) {
				$return->{'status'} = "Could not get list of feeds, possible database error.";
				my $feeds = $dbh->selectall_hashref(q( SELECT * FROM feeds ORDER BY url ), 'url');
				# Hashref fucks up the sorting
				my $count = 0;
				foreach my $key ( sort keys %{$feeds} ){
					$return->{'feeds'}[$count] = $feeds->{$key};
					$count++;
				}
				
				if ( !$dbh->errstr ){
					$return->{'status'} = "success";
				}
			}
			$return = encode_json($return);
			$req->respond ({ content => ['application/json',  $return ]});
		}
	},
	'/filters' => sub{
		my ($httpd, $req) = @_;
		if( $req->method() eq 'GET' ){
		
		$req->respond ({ content => ['text/html', $templates{'base'}->fill_in(HASH => {'title' => 'Filters', 'content' => $static->{'filters'}}) ]});
		
		} elsif ( $req->method() eq 'POST' ){
			my $return = {'status' => 'failure'};
			if( $req->parm('action') =~ /^(add|update|delete|list)$/ ){
				my $filterParams = decode_json($req->parm('data'));
				
				my $qh;
				if ( $req->parm('action') eq 'add' ){
					$return->{'status'} = "Could not save filter data, either a duplicate title or missing options";
					my @fields = sort keys %$filterParams;
					my @values = @{$filterParams}{@fields};
					$qh = $dbh->prepare(sprintf('INSERT INTO filters (%s) VALUES (%s)', join(",", @fields), join(",", ("?")x@fields)));
					$qh->execute(@values);
					if ( ! $qh->errstr ){
						$qh = $dbh->prepare('SELECT * FROM filters WHERE title=?');
						$qh->execute($filterParams->{'title'});
						$return->{'filter'} = $qh->fetchrow_hashref();
					}
					
				} elsif ( $req->parm('action') eq 'update' ){
					$return->{'status'} = "Could not save filter data, either a duplicate title or missing options";
					my $old_title = $filterParams->{'old_title'};
					delete($filterParams->{'old_title'});
					my @fields = sort keys %$filterParams;
					my @values = @{$filterParams}{@fields};
					$qh = $dbh->prepare(sprintf('UPDATE filters SET %s=? WHERE title=?', join("=?, ", @fields)));
					push(@values, $old_title);
					$filterParams->{'old_title'} = $old_title;
					$qh->execute(@values);
					$return->{'filter'} = $filterParams;						
					
				} elsif ( $req->parm('action') eq 'delete' ){
					$return->{'status'} = "Could not delete filter.  Incorrect title?";
					$qh = $dbh->prepare('DELETE FROM filters WHERE title=?');
					$qh->execute($filterParams->{'title'});
					$return->{'filter'} = $filterParams;						
					
				} elsif ( $req->parm('action') eq 'list' ){
					$return->{'status'} = "Could not fetch list of filters.";
	
					my $myFilters = $dbh->selectall_hashref(q( SELECT * FROM filters ORDER BY title ), 'title');
					
					# God... why doesn't it return the hash in the proper order??!?!
					my $count = 0;
					foreach my $key ( sort keys %{$myFilters} ){
						$return->{'filters'}[$count] = $myFilters->{$key};
						$count++;
					}
				}
					
				if(!$dbh->errstr){
					$return->{'status'} = 'success';
				}
				
	
			}
			$return = encode_json($return);
			$req->respond ({ content => ['application/json',  $return ]});
		}
	},
	'/main.css' => sub {
		my ($httpd, $req) = @_;
		
		$req->respond({ content => ['text/css', $static->{'css'}] });
	},
	'/bt.js' => sub {
		my ($httpd, $req) = @_;
		
		$req->respond({ content => ['text/javascript', $static->{'bt.js'}] });
	},
	'/logo.png' => sub {
		my ($httpd, $req) = @_;
		
		$req->respond({ content => ['', $static->{'logo'}] });
	},
);

$httpd->run; # making a AnyEvent condition variable would also work
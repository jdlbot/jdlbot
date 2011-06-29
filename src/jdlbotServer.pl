use EV;
use AnyEvent::Impl::EV;
use AnyEvent::HTTPD;
use AnyEvent::HTTP;

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

use JdlBot::Feed;
use JdlBot::UA;

# Set the UserAgent for external async requests.  Don't want to get flagged, do we?
$AnyEvent::HTTP::USERAGENT = JdlBot::UA::getAgent();


# Timeout for synchronous web requests
#  Usually this is only used to talk to the JD web interface
$ua->timeout(5);
# Set the useragent to the same string as the Async HTTP module
$ua->agent(JdlBot::UA::getAgent());


# Encapsulate configuration code
{
	my $port;
	my $directory = "";
	my $configdir = "";
	my $configfile = "";
	my $versionFlag;
	
	my $version = Perl::Version->new("0.1.3");
	
	# Command line startup options
	#  Usage: jdlbotServer(.exe) [-d|--directory=dir] [-p|--port=port#] [-c|--configdir=dir] [-v|--version]
	GetOptions("port=i" => \$port, # Port for the local web server to run on
			   "directory=s" => \$directory, # Directory to change to after starting (for dev mostly)
			   "configdir=s" => \$configdir, # Where your config files are located
			   "version" => \$versionFlag); # Get the version number
	
	if( $versionFlag ){
		print STDERR "jDlBot! version $version\n";
		exit(0);
	}
	
	if( $directory ){
		chdir($directory);
	}

	if( PAR::read_file('build.txt') ){
		if( $^O eq 'darwin' ) {
			require JdlBot::Build::Mac; 
		} elsif( $^O =~ /MSWin/ ){
			require JdlBot::Build::Win;
		}
	} else {
		require JdlBot::Build::Perl;
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
		%config = fetchConfig();
	}

	# Port setting from the command line is temporary
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

# Feed watchers
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
														JdlBot::Feed::scrape($url, $body, $filters, $follow_links, $dbh, \%config);
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

my $httpd = AnyEvent::HTTPD->new (host => '127.0.0.1', port => $config{'port'});
	print STDERR "Server running on port: $config{'port'}\n" .
	"Open http://127.0.0.1:$config{'port'}/ in your favorite web browser to continue.\n\n";
	
	if( $config{'open_browser'} eq 'TRUE' ){openBrowser();}

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
																'check_update' => $config{'check_update'} eq 'TRUE' ? 'checked="checked"' : '',
																'open_browser' => $config{'open_browser'} eq 'TRUE' ? 'checked="checked"' : ''
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
					
					if( defined($rssFeed) && $parseError != 1){
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
	'/linktypes' => sub{
		my ($httpd, $req) = @_;
		if( $req->method() eq 'GET' ){
		
		$req->respond ({ content => ['text/html', $templates{'base'}->fill_in(HASH => {'title' => 'Link Types', 'content' => $static->{'linktypes'}}) ]});
		
		} elsif ( $req->method() eq 'POST' ){
			my $return = {'status' => 'failure'};
			if( $req->parm('action') =~ /^(add|update|delete|list)$/ ){

				my $qh;
				if ( $req->parm('action') eq 'list' ){
					$return->{'status'} = "Could not fetch list of Link Types.";
	
					$return->{'linktypes'} = $dbh->selectall_arrayref(q( SELECT * FROM linktypes ORDER BY priority ), { Slice => {} });
				} elsif ( $req->parm('action') eq 'update' ){
					my $linktypeParams = decode_json(uri_unescape($req->parm('data')));
					$return->{'status'} = "Could not update list of Link Types.";

					my @fields = sort keys %{$linktypeParams->[0]};
					$qh = $dbh->prepare(sprintf('UPDATE linktypes SET %s=? WHERE linkhost=?', join("=?, ", @fields)));

					foreach my $linktype (@{$linktypeParams}){
						my @values = @{$linktype}{@fields};
						push(@values, $linktype->{linkhost});
						$qh->execute(@values);
					}
					
				} elsif ( $req->parm('action') eq 'delete' ){
					my $linktypeParams = decode_json(uri_unescape($req->parm('data')));
					$return->{'status'} = "Could not delete Link Type.";
					
					$qh = $dbh->prepare('DELETE FROM linktypes WHERE linkhost=?');
					$qh->execute($linktypeParams->{'linkhost'});

				} elsif ( $req->parm('action') eq 'add' ){
					my $linktypeParams = decode_json(uri_unescape($req->parm('data')));
					$return->{'status'} = "Could not add Link Type.";
					
					my @fields = sort keys %$linktypeParams;
					my @values = @{$linktypeParams}{@fields};
					$qh = $dbh->prepare(sprintf('INSERT INTO linktypes (%s) VALUES (%s)', join(",", @fields), join(",", ("?")x@fields)));
					$qh->execute(@values);
					if ( ! $qh->errstr ){
						$qh = $dbh->prepare('SELECT * FROM linktypes WHERE linkhost=?');
						$qh->execute($linktypeParams->{'linkhost'});
						$return->{'linktype'} = $qh->fetchrow_hashref();
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
	
					$return->{'filters'} = $dbh->selectall_arrayref(q( SELECT * FROM filters ORDER BY title ), { Slice => {} });
				}
					
				if(!$dbh->errstr){
					$return->{'status'} = 'success';
				}
				
	
			}
			$return = encode_json($return);
			$req->respond ({ content => ['application/json',  $return ]});
		}
	# TODO: Replace these static file requests with a function to make adding new static files easier
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
	'/favicon.ico' => sub {
		my ($httpd, $req) = @_;
		
		$req->respond({ content => ['', $static->{'favicon'}] });
	},
);

$httpd->run; # making a AnyEvent condition variable would also work



package JdlBot::TV;


sub checkTvMatch {
	my ( $title , $filter , $dbh ) = @_;
	my $tv_type;
	my $tv_last;
	
	# Make sure that we're working with the latest and greatest tv_last
	my $sth = $dbh->prepare('SELECT tv_last FROM filters WHERE title=? LIMIT 1');
	$sth->execute($filter->{'title'});
	if( $sth->errstr ){ return 0; }
	$filter->{'tv_last'} = ($sth->fetchall_arrayref())->[0]->[0];
	
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

1;

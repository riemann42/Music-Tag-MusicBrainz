package Music::Tag::MusicBrainz;
our $VERSION = 0.29;

# Copyright (c) 2006 Edward Allen III. Some rights reserved.
#
## This program is free software; you can redistribute it and/or
## modify it under the terms of the Artistic License, distributed
## with Perl.
#

=pod

=head1 NAME

Music::Tag::MusicBrainz - Plugin module for Music::Tag to get information from MusicBrainz database.

=head1 SYNOPSIS

	use Music::Tag

	my $info = Music::Tag->new($filename);
   
	my $plugin = $info->add_plugin("MusicBrainz");
	$plugin->get_tag;

	print "Music Tag Track ID ", $info->mb_trackid();

=head1 DESCRIPTION

Music::Tag::MusicBrainz is normally created in Music::Tag. This plugin gathers additional information about a track from amazon, and updates the tag object.

=head1 REQUIRED VALUES

=over 4

=item artist

=back

=head1 USED VALUES

=over 4

=item album

This is used to filter results. 

=item releasedate

This is used to filter results. 

=item totaltracks

This is used to filter results. 

=item title

title is used only if track is not true, or if trust_title option is set.

=item tracknum

tracknum is used only if title is not true, or if trust_track option is set.

=back

=head1 SET VALUES

=over 4

=item album

=item title

title is set only if trust_track is true.

=item track

track is set only if track is not true or trust_title is true.

=item releasedate


=cut

use strict;
use WebService::MusicBrainz::Artist;
use WebService::MusicBrainz::Release;
use WebService::MusicBrainz::Track;
use utf8;
our @ISA = qw(Music::Tag::Generic);

sub default_options {
    {  prefered_country         => "US",
       min_artist_score         => 1,
       min_album_score          => 17,
       min_track_score          => 3,
       ignore_mbid              => 0,
       trust_time               => 0,
       trust_track              => 0,
       trust_title              => 0,
       skip_seen                => 0,
       ignore_multidisc_warning => 1,
       mb_host                  => "www.musicbrainz.org",
    };
}

=back

=head1 METHODS

=over 4

=item get_tag

Updates current tag object with information from MusicBrainz database.

Same as $mbplugin->artist_info() && $mbplugin->album_info() && $mbplugin->track_info();

=cut

sub get_tag {
    my $self = shift;
    if ( ( $self->options->{skip_seen} ) && ( length( $self->info->mb_trackid ) == 36 ) ) {
        $self->status(
                 "Skipping previously looked up track with mb_trackid " . $self->info->mb_trackid );
    }
    else {
        $self->artist_info() && $self->album_info() && $self->track_info();
    }
    return $self;
}

=item artist_info

Update the tag object with information about the artist from MusicBrainz.

=cut

sub artist_info {
    my $self = shift;
    $self->status( "Looking up artist from " . $self->options->{mb_host} );
    unless ( exists $self->{mb_a} ) {
        $self->{mb_a} = WebService::MusicBrainz::Artist->new( HOST => $self->options->{mb_host} );
    }
    my $params   = {};
    my $maxscore = 0;
    my $artist   = undef;
    if (    ( defined $self->info->mb_artistid )
         && ( $self->info->mb_artistid )
         && ( not $self->options->{ignore_mbid} ) ) {
        $params->{MBID} = $self->info->mb_artistid;
        $artist = $self->{mb_a}->search($params);
        unless ( ref($artist) eq "WebService::MusicBrainz::Response::Artist" ) {
            $artist = $artist->artist();
        }
        $maxscore = 8;
    }
    elsif ( ( defined $self->info->artist ) && ( $self->info->artist ) ) {
        $params->{NAME} = $self->info->artist;
        my $response = $self->{mb_a}->search($params);
        return unless $response;
        return unless $response->artist_list();
        foreach ( @{ $response->artist_list->artists() } ) {
            my $s = 0;
            if (($self->info->artist) && ($_->{name}) && ( $self->info->artist eq $_->{name} )) {
                $s += 16;
            }
            elsif (($self->info->artist) && ($_->{sortname}) && ($self->info->artist eq $_->{sortname} )) {
                $s += 8;
            }
            elsif (($self->info->mb_artistid) && ($_->{id}) &&  ($self->info->mb_artistid eq $_->{id} )) {
                $s += 4;
            }
            elsif (($self->info->artist) && ($_->{name}) &&  ($self->simple_compare( $self->info->artist, $_->{name}, .90 )) ) {
                $s += 2;
            }
            if ( $s > $maxscore ) {
                $artist   = $_;
                $maxscore = $s;
            }
        }
        if ( $maxscore > $self->options->{min_artist_score} ) {
            $self->status( "Artist ", $artist->name, " won election with ", $maxscore, "pts" );
        }
        elsif ($maxscore) {
            $self->status( "Artist ", $artist->name, " won election with ",
                           $maxscore, "pts, but that is not good enough" );
            return;
        }
        else {
            $self->status("No Artist found");
            return;
        }
    }
    return unless ( defined $artist );

    if ( $artist->{name} ) {
        unless (     ( defined $self->info->artist )
                 and ( ( $self->info->artist ) eq ( $artist->{name} ) ) ) {
            $self->info->artist( $artist->name );
            $self->tagchange("ARTIST");
        }
    }
    if ( $artist->{id} ) {
        unless (     ( defined $self->info->mb_artistid )
                 and ( ( $self->info->mb_artistid ) eq ( $artist->{id} ) ) ) {
            $self->info->mb_artistid( $artist->id );
            $self->tagchange("MB_ARTISTID");
        }
    }
    if ( $artist->{sort_name} ) {
        unless (     ( defined $self->info->sortname )
                 and ( ( $self->info->sortname ) eq ( $artist->{sort_name} ) ) ) {
            $self->info->sortname( $artist->sort_name );
            $self->tagchange("SORTNAME");
        }
    }
    if ( $artist->{type} ) {
        unless (     ( defined $self->info->artist_type )
                 and ( ( $self->info->artist_type ) eq ( $artist->{type} ) ) ) {
            $self->info->artist_type( $artist->type );
            $self->tagchange("ARTIST_TYPE");
        }
    }
    if ( $artist->life_span_begin ) {
        unless (     ( defined $self->info->artist_start )
                 and ( ( $self->info->artist_start ) eq ( $artist->life_span_begin ) ) ) {
            $self->info->artist_start( $artist->life_span_begin );
            $self->tagchange("ARTIST_START");
        }
    }
    if ( $artist->life_span_end ) {
        unless (     ( defined $self->info->artist_end )
                 and ( ( $self->info->artist_end ) eq ( $artist->life_span_end ) ) ) {
            $self->info->artist_end( $artist->life_span_end );
            $self->tagchange("ARTIST_END");
        }
    }
    return $self->info;
}

=item album_info

Update the tag object with information about the album from MusicBrainz.

=cut


sub album_info {
    my $self = shift;
    $self->status( "Looking up album from " . $self->options->{mb_host} );
    unless ( exists $self->{mb_r} ) {
        $self->{mb_r} = WebService::MusicBrainz::Release->new( HOST => $self->options->{mb_host} );
    }
    my $params = { LIMIT => 200 };
    my $release = undef;
    if (    ( defined $self->info->mb_albumid )
         && ( $self->info->mb_albumid )
         && ( not $self->info->options->{ignore_mbid} ) ) {
        $params->{MBID} = $self->info->mb_albumid;
        my $response = $self->{mb_r}->search($params);
        $release = $response->release();

        #print Dumper($release);
    }
    else {

        #if (( defined $self->info->album ) && ( $self->info->album )) {
        #   $params->{title} = $self->info->album;
        #}
        if ( ( defined $self->info->mb_artistid ) && ( $self->info->mb_artistid ) ) {
            $params->{artistid} = $self->info->mb_artistid;
        }
        elsif ( ( defined $self->info->artist ) && ( $self->info->artist ) ) {
            $params->{artist} = $self->info->artist;
        }
        else {
            $self->status("Artist required for album lookup...");
            return ();
        }

        my $response = $self->{mb_r}->search($params);
        return unless $response;

        #     albumid          256 pts
        #     title             64 pts
        #	    asin              32 pts
        #     simple_title      32 pts
        #	    discid            32 pts
        #	    track_count       16 pts
        #     release_date       8 pts
        #     track name match   4 pts
        #     strack name match  2 pts
        #     track time match   1 pts

        my $releases = $response->release_list();
        return unless $releases;

        my $maxscore = 0;
        foreach ( @{ $releases->releases } ) {
            my $s = 0;
			my $title = $_->{title};
			my $disc = 1;
			if ($title =~ /^(.+) \(disc (\d)(\: ([^)]*))?\)/i) {
				$title = $1;
				$disc = $2;
			}
            if (     ( defined $self->info->mb_albumid )
                 and ( $self->info->mb_albumid eq $_->id )
                 and ( not $self->options->{ignore_mbid} ) ) {
                $s += 256;
            }
            if ( $title eq $self->info->album ) {
                $s += 64;
            }
            if ( ($_->{asin}) && ($self->info->asin) && ( length( $_->{asin} ) > 8 ) && ( $_->{asin} eq $self->info->asin ) ) {
                $s += 32;
            }
            if ( $self->simple_compare( $title, $self->info->album, .80 ) ) {
                $s += 32;
            }
            if (     ( defined $self->info->totaltracks )
                 and ( ( $self->info->totaltracks ) == ( $_->track_list->{count} ) ) ) {
                $s += 16;
            }
			if (     ( defined $self->info->disc)
				  and ( ( $self->info->disc) == ( $disc) ) ) {
				  $s += 8;
			 }
            if ( $s > $maxscore ) {
                $release  = $_;
                $maxscore = $s;
            }
        }
        if ( $maxscore > $self->options->{min_album_score} ) {
            $self->status( "Awarding highest score of " . $maxscore . " to " . $release->title );
        }
        elsif ($release) {
            $self->status(
                       "Highest score of " . $maxscore . " to " . $release->title . " is too low" );
            return;
        }
        else {
            $self->status("No good match found for album, sorry\n");
            return;
        }
    }
    if ( $release->type ) {
        unless (     ( defined $self->info->album_type )
                 and ( ( $self->info->album_type ) eq ( $release->{type} ) ) ) {
            $self->info->album_type( $release->{type} );
            $self->tagchange("ALBUM_TYPE");
        }
    }
    if ( $release->id ) {
        unless (     ( defined $self->info->mb_albumid )
                 and ( ( $self->info->mb_albumid ) eq ( $release->{id} ) ) ) {
            $self->info->mb_albumid( $release->id() );
            $self->tagchange("MB_ALBUMID");
        }
    }
    if ( $release->title ) {
		# Parse out additional disc information.  I still don't know how to deal with multi-volume sets
		# in MusicBrainz.  Style says to use (disc X) or (disc X: Disc Title) or even (box X, disc X).
		# for now, I will support in album_title /\(disc (\d):?[^)]*\)/.  
        unless ( ( defined $self->info->album ) and ( $self->info->album eq $release->title ) ) {
			if ($release->title() =~ /^(.+) \(disc (\d)(\: ([^)]*))?\)/i) {
				my ($alb, $disc, $disctitle) = ($1, $2, $4);
				unless ($self->info->album eq $alb) {
					$self->info->album($1);
					$self->tagchange("ALBUM");
				}
				unless ($self->info->disc eq $disc) {
					$self->info->disc($2);
					$self->tagchange("DISC");
				}
				if ($3) {
					$self->status("Debug disctitle: $disctitle");
					unless ($self->info->disctitle eq $disctitle) {
						$self->info->disctitle($disctitle);
						$self->tagchange("DISCTITLE");
					}
				}
			}
			else {
				$self->info->album( $release->title() );
				$self->tagchange("ALBUM");
			}
        }
    }
    if ( $release->track_list ) {
        unless (     ( defined $self->info->totaltracks )
                 and ( ( $self->info->totaltracks ) == ( $release->track_list->{count} ) ) ) {
            $self->info->totaltracks( $release->track_list->{count} );
            $self->tagchange("TOTALTRACKS");
        }
    }

    if ( exists $release->{asin} ) {
        unless ( ( $self->info->asin ) and ( $self->info->asin eq $release->{asin} ) ) {
            $self->info->asin( $release->{asin} );
            $self->tagchange("ASIN");
        }
    }
    return $self->info;
}

=item track_info

Update the tag object with information about the track from MusicBrainz.

=cut


sub track_info {
    my $self = shift;
    if (    ( ($self->info->totaldiscs && $self->info->totaldiscs > 1 ) or ( $self->info->disc && $self->info->disc > 1 ) )
         && ( not $self->options->{ignore_multidisc_warning} ) ) {
        $self->status(
            "Warning! Multi-Disc item. MusicBrainz is not reliable for this. Will not change track name or number."
        );
    }
    $self->status( "Looking up track from " . $self->options->{mb_host} );
    unless ( exists $self->{mb_r} ) {
        $self->{mb_r} = WebService::MusicBrainz::Release->new( HOST => $self->options->{mb_host} );
    }
    return unless ( defined $self->info->mb_albumid );
    my $params = { MBID => $self->info->mb_albumid,
                   INC  => "tracks+puids+discs+release-events",
                 };
    my $response = $self->{mb_r}->search($params);
    unless ( $response->release->track_list ) {
        return;
    }
    my $tracks   = $response->release->track_list->tracks();
    my $release  = $response->release;
    my $tracknum = 0;
    my $maxscore = 0;
    my $track    = undef;
    my $trackn   = 0;

    #   track ID (unless ignore_ids)  128 pts
    #   tracknum match                  4 pts
    #    trust track set               64 pts
    #   title match                     8 pts
    #    trust title set               64 pts
    #   close title match               4 pts
    #    trust title set               16 pts
    #   time match                      2 pts
    #    trust time set                64 pts
    #   close time match                1 pts
    #    trust time set                16 pts

    foreach my $t ( @{$tracks} ) {
        my $s = 0;
        if (    ( defined $self->info->mb_trackid )
             && ( $self->info->mb_trackid eq $t->{id} )
             && ( not $self->info->{ignore_mbid} ) ) {
            $s += 128;
        }
        if ( ( defined $self->info->track ) && ( $self->info->track - 1 == $tracknum ) ) {
            if ( $self->options->{trust_track} ) {
                $s += 64;
            }
            else {
                $s += 4;
            }
        }
        if ( ( defined $self->info->title ) && ( $self->info->title eq $t->{title} ) ) {
            if ( $self->options->{trust_title} ) {
                $s += 64;
            }
            else {
                $s += 8;
            }
        }
        elsif (    ( defined $self->info->title )
                && ( $self->simple_compare( $self->info->title, $t->{title}, .80 ) ) ) {
            if ( $self->options->{trust_title} ) {
                $s += 16;
            }
            else {
                $s += 4;
            }
        }
        if ( defined $self->info->duration ) {
            my $diff = abs( $self->info->duration - $t->{duration} );
            if ( $diff < 3000 ) {
                if ( $self->options->{trust_time} ) {
                    $s += 16;
                }
                else {
                    $s += 1;
                }
            }
            elsif ( $diff < 100 ) {
                $s += 2;
                if ( $self->options->{trust_time} ) {
                    $s += 64;
                }
                else {
                    $s += 1;
                }
            }
        }
        if ( $s > $maxscore ) {
            $maxscore = $s;
            $track    = $t;
            $trackn   = $tracknum + 1;
        }
        $tracknum++;
    }
    if (($maxscore) && ( $maxscore > $self->options->{min_track_score} )) {
        $self->status( "Awarding highest score of " . $maxscore . " to " . $track->title );
    }
    elsif ($maxscore) {
        $self->status(   "Highest score was "
                       . $maxscore . " for "
                       . $track->title
                       . ", but that is not good enough, skipping track info." );
        return;
    }
    else {
        $self->status("No match for track, skipping track info.");
        return;
    }
    unless (    ( ( $self->info->totaldiscs && $self->info->totaldiscs > 1 ) or ( $self->info->disc && $self->info->disc > 1 ) )
             && ( not $self->options->{ignore_multidisc_warning} ) ) {
        if ( $track->title ) {
            unless (     ( defined $self->info->title )
                     and ( ( $self->info->title ) eq ( $track->title ) ) ) {
                $self->info->title( $track->title );
                $self->tagchange("TITLE");
            }
        }
        unless (     ( defined $self->info->track )
                 and ( $self->info->track == $trackn ) ) {
            $self->info->track($trackn);
            $self->tagchange("TRACK");
        }
        if ( $track->id ) {
            unless (     ( defined $self->info->mb_trackid )
                     and ( ( $self->info->mb_trackid ) eq ( $track->id ) ) ) {
                $self->info->mb_trackid( $track->id );
                $self->tagchange("MB_TRACKID");
            }
        }
    }
    my $releases = [];
    if ( $release->release_event_list ) {
        $releases = $release->release_event_list->events;
    }
    my $countrycode = undef;
    my $releasedate = undef;
    if ( scalar @{$releases} ) {
        $maxscore = 0;
        foreach ( @{$releases} ) {
            my $score = 0;
            if (($_->date) && ($self->info->releasedate) && ( $_->date eq $self->info->releasedate )) {
                $score += 4;
            }
            elsif ( $_->country eq $self->options->{prefered_country} ) {
                $score += 2;
            }
            elsif ( not defined $countrycode ) {
                $score += 1;
            }
            if ( $score > $maxscore ) {
                $countrycode = $_->country();
                $releasedate = $_->date();
                $maxscore    = $score;
            }
        }
    }
    if ( ($countrycode)
         && (
              not(    ( defined $self->info->countrycode )
                   && ( $self->info->countrycode eq $countrycode ) )
            )
      ) {
        $self->info->countrycode($countrycode);
        $self->tagchange("countrycode");
    }
    if ( ($releasedate)
         && (
              not(    ( defined $self->info->releasedate )
                   && ( $self->info->releasedate eq $releasedate ) )
            )
      ) {
        $self->info->releasedate($releasedate);
        $self->tagchange("releasedate");
    }
}

=item default_options

Returns hash of default options for plugin

=back

=head1 OPTIONS

=over 4

=item prefered_country

If multiple release countries are available, prefer this one. Default is 'US'.

=item min_artist_score

Minimum artist score for a match.  Default is 1.

=item min_album_score

Minimum album score for a mach.  Default is 17.  Raise if you get too many false positives.

=item min_track_score.

Minimum track score.  Default is 3.

=item ignore_mbid

If set, will ignore any MusicBrainz ID values found.

=item trust_time

If set, will give high priority to track duration in matching

=item trust_track

If set, will give high priority to track number in matching

=item trust_title

If set, will give high priority to title in matching.

=item skip_seen

If set, will not perform a MusicBrainz lookup if an mb_trackid is set.

=item ignore_multidisc_warning

If set, will enable use of MusicBrainz standards to get disc numbers.

=item mb_host

Set to host for musicbrainz.  Default is www.musicbrainz.org.

=back

=head1 BUGS

Sometimes will grab incorrect info. This is due to the lack of album level view when repairing tags.

=head1 SEE ALSO INCLUDED

L<Music::Tag>, L<Music::Tag::Amazon>, L<Music::Tag::File>, L<Music::Tag::FLAC>, L<Music::Tag::Lyrics>,
L<Music::Tag::M4A>, L<Music::Tag::MP3>, L<Music::Tag::OGG>, L<Music::Tag::Option>

=head1 SEE ALSO

L<WebService::MusicBrainz>


=head1 AUTHOR 

Edward Allen III <ealleniii _at_ cpan _dot_ org>


=head1 COPYRIGHT

Copyright (c) 2007 Edward Allen III. Some rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of the Artistic License, distributed
with Perl.


=cut


1;

package Shipwright::Script::List;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level log_file dist with_latest_version only_update/);

use Shipwright;
use Data::Dumper;

=head2 options
=cut

sub options {
    (
        'r|repository=s'      => 'repository',
        'l|log-level=s'       => 'log_level',
        'log-file=s'          => 'log_file',
        'dist=s'              => 'dist',
        'with-latest-version' => 'with_latest_version',
        'only-update'         => 'only_update',
    );
}

=head2 run
=cut

sub run {
    my $self = shift;
    my $dist = shift;

    $self->dist($dist) if $dist && !$self->dist;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level || 'fatal',
        log_file   => $self->log_file,
    );

    my $versions = $shipwright->backend->versions;
    my $source   = $shipwright->backend->source;

    my $latest_version = {};

    # only_update option implies with_latest_version
    $self->with_latest_version(1) if $self->only_update;

    if ( $self->with_latest_version ) {
        my $map = $shipwright->backend->map;

        if ( $self->dist ) {
            if ( $self->dist =~ /^cpan-/ ) {
                my %reversed = reverse %$map;
                my $module   = $reversed{ $self->dist };
                $latest_version->{ $self->dist } =
                  $self->_latest_version( name => $module );
            }
            else {
                $latest_version->{ $self->dist } =
                  $self->_latest_version( url => $source->{ $self->dist } );
            }
        }
        else {

            for my $module ( keys %$map ) {
                next if exists $latest_version->{ $map->{$module} };
                $latest_version->{ $map->{$module} } =
                  $self->_latest_version( name => $module );
            }

            for my $dist ( keys %$source ) {
                next if exists $latest_version->{$dist};
                if ( $source->{$dist} =~ m{^(svn|svk|//)} ) {
                    $latest_version->{$dist} =
                      $self->_latest_version( url => $source->{$dist} );
                }
            }
        }
    }

    if ( $self->dist ) {
        my $new_versions = {};
        $new_versions->{ $self->dist } = $versions->{ $self->dist }
          if exists $versions->{ $self->dist };
        $versions = $new_versions;
    }
    for my $dist ( sort keys %$versions ) {
        my $flip = 1;

        if ( $self->only_update ) {
            $flip = 0;
            if ( $latest_version->{$dist} ) {
                require version;
                my $latest = version->new( $latest_version->{$dist} );
                if ( $latest gt $versions->{$dist} ) {
                    $flip = 1;
                }
            }

        }

        if ($flip) {
            print $dist, ': ', "\n";
            print ' ' x 4 . 'version: ', $versions->{$dist} || '',     "\n";
            print ' ' x 4 . 'from: ',    $source->{$dist}   || 'CPAN', "\n";
            if ( $self->with_latest_version ) {
                print ' ' x 4 . 'latest_version: ', $latest_version->{$dist}
                  || 'unknown', "\n";
            }
        }
    }

    if ( $self->dist && keys %$versions == 0 ) {
        print $self->dist, " doesn't exist\n";
    }
}

sub _latest_version {
    my $self = shift;
    my %args = @_;
    if ( $args{url} ) {

        my ( $cmd, $out );

        # has url, meaning svn or svk
        if ( $args{url} =~ /^svn[:+]/ ) {
            $args{url} =~ s{^svn:(?!//)}{};
            $cmd = [ 'svn', 'info', $args{url} ];
        }
        elsif ( $args{url} =~ m{^(svk:|//)} ) {
            $args{url} =~ s/^svk://;
            $cmd = [ 'svk', 'info', $args{url} ];
        }

        ($out) = Shipwright::Util->run( $cmd, 1 );    # ignore failure
        if ( $out =~ /^Revision:\s*(\d+)/m ) {
            return $1;
        }
    }
    elsif ( $args{name} ) {

        # cpan
        require CPAN;
        require CPAN::DistnameInfo;
        open my $fh, '>', '/dev/null';
        my $stdout = select $fh;

        my $module = CPAN::Shell->expand( 'Module', $args{name} );
        select $stdout;

        my $info    = CPAN::DistnameInfo->new( $module->cpan_file );
        my $version = $info->version;
        $version =~ s/^v//;    # we don't want the leading 'v'
        return $version;
    }
    return;
}

1;

__END__

=head1 NAME

Shipwright::Script::List - list dists of a project

=head1 SYNOPSIS

  shipwright list         list dists of a project

 Options:
   --repository(-r)   specify the repository of our project
   --log-level(-l)    specify the log level
   --log-file         specify the log file
   --dist             sepecify the dist name
   --with-latest-version  show the latest version if possible
   --only-update      only show the dists that can be updated


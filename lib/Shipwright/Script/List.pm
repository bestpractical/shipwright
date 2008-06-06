package Shipwright::Script::List;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level log_file name with_latest_version only_update/);

use Shipwright;

sub options {
    (
        'r|repository=s'      => 'repository',
        'l|log-level=s'       => 'log_level',
        'log-file=s'          => 'log_file',
        'name=s'              => 'name',
        'with-latest-version' => 'with_latest_version',
        'only-update'         => 'only_update',
    );
}

sub run {
    my $self = shift;
    my $name = shift;

    $self->name($name) if $name && !$self->name;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level || 'fatal',
        log_file   => $self->log_file,
    );

    my $versions = $shipwright->backend->version;
    my $source   = $shipwright->backend->source;

    my $latest_version = {};

    # only_update option implies with_latest_version
    $self->with_latest_version(1) if $self->only_update;

    if ( $self->with_latest_version ) {
        my $map = $shipwright->backend->map;

        if ( $self->name ) {
            if ( $self->name =~ /^cpan-/ ) {
                my %reversed = reverse %$map;
                my $module   = $reversed{ $self->name };
                $latest_version->{ $self->name } =
                  $self->_latest_version( name => $module );
            }
            else {
                $latest_version->{ $self->name } =
                  $self->_latest_version( url => $source->{ $self->name } );
            }
        }
        else {

            for my $module ( keys %$map ) {
                next if exists $latest_version->{ $map->{$module} };
                $latest_version->{ $map->{$module} } =
                  $self->_latest_version( name => $module );
            }

            for my $name ( keys %$source ) {
                next if exists $latest_version->{$name};
                if ( $source->{$name} =~ s{^sv[nk]:}{}g ) {
                    $latest_version->{$name} =
                      $self->_latest_version( url => $source->{$name} );
                }
            }
        }
    }

    if ( $self->name ) {
        my $new_versions = {};
        $new_versions->{ $self->name } = $versions->{ $self->name }
          if exists $versions->{ $self->name };
        $versions = $new_versions;
    }
    for my $name ( sort keys %$versions ) {
        my $flip = 1;

        if ( $self->only_update ) {
            $flip = 0;
            if ( $latest_version->{$name} ) {
                require version;
                my $latest = version->new( $latest_version->{$name} );
                if ( $latest gt $versions->{$name} ) {
                    $flip = 1;
                }
            }

        }

        if ($flip) {
            print $name, ': ', "\n";
            print ' ' x 4 . 'version: ', $versions->{$name} || '',     "\n";
            print ' ' x 4 . 'from: ',    $source->{$name}   || 'CPAN', "\n";
            if ( $self->with_latest_version ) {
                print ' ' x 4 . 'latest_version: ', $latest_version->{$name}
                  || 'unknown', "\n";
            }
        }
    }

    if ( $self->name && keys %$versions == 0 ) {
        print $self->name, " doesn't exist\n";
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

        Shipwright::Util->select( 'cpan' );

        my $module = CPAN::Shell->expand( 'Module', $args{name} );

        Shipwright::Util->select( 'stdout' );

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

Shipwright::Script::List - List dists of a project

=head1 SYNOPSIS

 list

=head1 OPTIONS
   -r [--repository] REPOSITORY    : specify the repository of our project
   -l [--log-level] LOGLEVEL       : specify the log level
   --log-file FILENAME             : specify the log file
                                     (info, debug, warn, error, or fatal)
   --name NAME                     : sepecify the dist name
   --with-latest-version           : show the latest version if possible
   --only-update                   : only show the dists that can be updated

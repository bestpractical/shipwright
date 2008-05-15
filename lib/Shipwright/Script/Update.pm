package Shipwright::Script::Update;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(qw/repository log_level name all follow log_file/);

use Shipwright;
use File::Spec;
use Shipwright::Util;
use File::Copy qw/copy move/;
use File::Temp qw/tempdir/;
use Config;
use Hash::Merge;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
        'name=s'         => 'name',
        'a|all'          => 'all',
        'follow'         => 'follow',
    );
}

my ( $shipwright, $map, $source );

sub run {
    my $self = shift;
    my $name = shift;

    $self->name($name) if $name && !$self->name;

    die 'need name arg' unless $self->name || $self->all;

    $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file,
    );

    $map    = $shipwright->backend->map    || {};
    $source = $shipwright->backend->source || {};

    if ( $self->all ) {
        my $dists = $shipwright->backend->order || [];
        for (@$dists) {
            $self->_update($_);
        }
    }
    else {
        if ( !$source->{ $self->name } && $map->{ $self->name } ) {

            # in case the name is module name
            $self->name( $map->{ $self->name } );
        }

        my @dists;
        if ( $self->follow ) {
            my (%checked);
            my $find_deps;
            $find_deps = sub {
                my $name = shift;

                return if $checked{$name}++;    # we've checked this $name

                my ($require) = $shipwright->backend->requires( name => $name );
                for my $type (qw/requires build_requires recommends/) {
                    for ( keys %{ $require->{$type} } ) {
                        $find_deps->($_);
                    }
                }
            };

            $find_deps->( $self->name );
            @dists = keys %checked;
        }
        for ( @dists, $self->name ) {
            $self->_update($_);
        }
    }
}

sub _update {
    my $self = shift;
    my $name = shift;

    if ( $source->{$name} ) {
        $shipwright->source(
            Shipwright::Source->new(
                name   => $name,
                source => $source->{$name},
                follow => 0,
            )
        );
    }
    else {

        # it's a cpan dist
        my $s;

        if ( $name =~ /^cpan-/ ) {
            $s = { reverse %$map }->{$name};
        }
        elsif ( $map->{$name} ) {
            $s    = $name;
            $name = $map->{$name};
        }
        else {
            die 'invalid name ' . $name;
        }

        $shipwright->source(
            Shipwright::Source->new(
                source => "cpan:$s",
                follow => 0,
            )
        );
    }

    $shipwright->source->run;

    my $version =
      Shipwright::Util::LoadFile( $shipwright->source->version_path );

    $shipwright->backend->import(
        source  => File::Spec->catfile( $shipwright->source->directory, $name ),
        comment => "update $name",
        overwrite => 1,
        version   => $version->{$name},
    );

}

1;

__END__

=head1 NAME

Shipwright::Script::Update - update dist(s)

=head1 SYNOPSIS

  shipwright update          update dist(s)

 Options:
   --repository(-r)   specify the repository of our project
   --log-level(-l)    specify the log level
   --log-file         specify the log file
   --name             specify the source name( only alphanumeric characters and - )
   --all              update all the dists
   --follow           update one dist with all its deps(recursively)


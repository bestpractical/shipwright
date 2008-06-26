package Shipwright::Script::Delete;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(qw/repository log_level log_file name/);

use Shipwright;
use File::Spec;
use Shipwright::Util;

sub options {
    (
        'name=s'         => 'name',
    );
}

sub run {
    my $self = shift;
    my $name = shift;

    $self->name($name) if $name && !$self->name;

    die "need name arg" unless $self->name();

    my $shipwright = Shipwright->new(
        repository => $self->repository,
    );

    my $map = $shipwright->backend->map || {};

    if ( $map->{ $self->name } ) {

        # it's a cpan module
        $self->name( $map->{ $self->name } );
    }

    $name = $self->name;

    my $order = $shipwright->backend->order;

    die "no such dist: $name" unless grep { $_ eq $name } @$order;

    $shipwright->backend->delete( path => "dists/$name" );
    $shipwright->backend->delete( path => "scripts/$name" );

    # clean order.yml
    @$order = grep { $_ ne $name } @$order;
    $shipwright->backend->order($order);

    # clean map.yml
    for ( keys %$map ) {
        delete $map->{$_} if $map->{$_} eq $name;
    }

    # clean version.yml, source.yml and flags.yml
    my $version = $shipwright->backend->version || {};
    my $source  = $shipwright->backend->source  || {};
    my $flags   = $shipwright->backend->flags   || {};

    $self->_clean_hash( $source, $flags, $version );

    $shipwright->backend->version($version);
    $shipwright->backend->map($map);
    $shipwright->backend->source($source);
    $shipwright->backend->flags($flags);

    print "deleted $name with success\n";
}

sub _clean_hash {
    my $self     = shift;
    my @hashrefs = @_;
    my $name     = $self->name;

    for my $hashref (@hashrefs) {
        for ( keys %$hashref ) {
            if ( $_ eq $name ) {
                delete $hashref->{$_} if $_ eq $name;
                last;
            }
        }
    }
}

1;

__END__

=head1 NAME

Shipwright::Script::Delete - Delete a dist

=head1 SYNOPSIS

 delete -r [repository] --name [dist name]

=head1 OPTIONS
 -r [--repository] REPOSITORY   : specify the repository of our project
 -l [--log-level] LOGLEVEL      : specify the log level
                                  (info, debug, warn, error, or fatal)
 --log-file FILENAME            : specify the log file
 --name NAME                    : specify the dist name

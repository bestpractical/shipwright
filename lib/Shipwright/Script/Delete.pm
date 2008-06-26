package Shipwright::Script::Delete;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Shipwright::Script/;

use Shipwright;
use File::Spec;
use Shipwright::Util;

sub run {
    my $self = shift;
    my $name = shift;

    die "need name arg" unless $name;

    my $shipwright = Shipwright->new( repository => $self->repository, );

    my $map = $shipwright->backend->map || {};

    if ( $map->{$name} ) {

        # it's a cpan module
        $name = $map->{$name};
    }

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

    for my $hashref ( $source, $flags, $version ) {
        for ( keys %$hashref ) {
            if ( $_ eq $name ) {
                delete $hashref->{$_};
                last;
            }
        }
    }

    $shipwright->backend->version($version);
    $shipwright->backend->map($map);
    $shipwright->backend->source($source);
    $shipwright->backend->flags($flags);

    print "deleted $name with success\n";
}

1;

__END__

=head1 NAME

Shipwright::Script::Delete - Delete a dist

=head1 SYNOPSIS

 delete NAME

=head1 OPTIONS
 -r [--repository] REPOSITORY   : specify the repository of our project
 -l [--log-level] LOGLEVEL      : specify the log level
                                  (info, debug, warn, error, or fatal)
 --log-file FILENAME            : specify the log file

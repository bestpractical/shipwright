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
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
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
        log_level  => $self->log_level,
        log_file   => $self->log_file,
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

    # clean version.yml, map.yml, source.yml and flags.yml
    my $version = $shipwright->backend->version;
    for ( keys %$version ) {
        if ( $_ eq $name ) {
            delete $version->{$_};
            last;
        }
    }

    for ( keys %$map ) {
        delete $map->{$_} if $map->{$_} eq $name;
    }

    my $source = $shipwright->backend->source || {};

    for ( keys %$source ) {
        if ( $_ eq $name ) {
            delete $source->{$_} if $_ eq $name;
            last;
        }
    }

    my $flags = $shipwright->backend->flags;
    for ( keys %$flags ) {
        delete $flags->{$_} if $_ eq $name;
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

Shipwright::Script::Delete - delete a dist

=head1 SYNOPSIS

  shipwright delete          delete a source

 Options:
   --repository(-r)   specify the repository of our project
   --log-level(-l)    specify the log level
   --log-file         specify the log file
   --name             specify the dist name


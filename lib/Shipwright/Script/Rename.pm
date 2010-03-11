package Shipwright::Script::Rename;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Shipwright::Script/;

use Shipwright;
use Shipwright::Util;

sub run {
    my $self = shift;

    my ( $name, $new_name ) = @_;

    confess "need name arg\n"     unless $name;
    confess "need new-name arg\n" unless $new_name;

    confess "invalid new-name: $new_name, should only contain - and alphanumeric\n"
      unless $new_name =~ /^[-\w]+$/;

    my $shipwright = Shipwright->new( repository => $self->repository, );

    my $order = $shipwright->backend->order;

    confess "no such dist: $name\n" unless grep { $_ eq $name } @$order;

    $shipwright->backend->move(
        path     => "/sources/$name",
        new_path => "/sources/$new_name",
    );
    $shipwright->backend->move(
        path     => "/scripts/$name",
        new_path => "/scripts/$new_name",
    );

    # update order.yml
    @$order = map { $_ eq $name ? $new_name : $_ } @$order;
    $shipwright->backend->order($order);

    # update map.yml
    my $map = $shipwright->backend->map || {};
    for ( keys %$map ) {
        $map->{$_} = $new_name if $map->{$_} eq $name;
    }
    $shipwright->backend->map($map);

    my $version = $shipwright->backend->version;
    my $source  = $shipwright->backend->source;
    my $flags   = $shipwright->backend->flags;
    my $refs    = $shipwright->backend->refs;
    my $branches= $shipwright->backend->branches;

    for my $hashref ( $source, $flags, $version, $refs, $branches ) {
        next unless $hashref; # branches can be undef
        for ( keys %$hashref ) {
            if ( $_ eq $name ) {
                $hashref->{$new_name} = delete $hashref->{$_};
                last;
            }
        }
    }

    $shipwright->backend->version($version);
    $shipwright->backend->source($source);
    $shipwright->backend->flags($flags);
    $shipwright->backend->refs($refs);
    $shipwright->backend->branches($branches) if $branches;

    $self->log->fatal( "renamed $name to $new_name with success" );
}

1;

__END__

=head1 NAME

Shipwright::Script::Rename - Rename a dist

=head1 SYNOPSIS

  shipwright rename NAME NEWNAME          rename a dist

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


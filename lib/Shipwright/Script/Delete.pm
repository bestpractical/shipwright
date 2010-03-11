package Shipwright::Script::Delete;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(qw/unreferenced check_only/);

use Shipwright;
use Shipwright::Util;

sub options {
    (
        'unreferenced' => 'unreferenced',
        'C|check-only' => 'check_only',
    );
}

sub run {
    my $self = shift;
    my $name = shift;

    unless ( $name || $self->unreferenced ) {
        confess "need name arg or --unreferenced\n";
    }

    if ( $name && $self->unreferenced ) {
        confess "please choose only one thing: a dist name or --unreferenced";
    }

    my $shipwright = Shipwright->new( repository => $self->repository, );
    my @names;

    if ($name) {
        my $map = $shipwright->backend->map;
        if ( $map && $map->{$name} ) {

            # it's a cpan module
            $name = $map->{$name};
        }
        @names = $name;
    }
    else {

        # unreferenced dists except the last one
        my $refs  = $shipwright->backend->refs;
        my $order = $shipwright->backend->order;
        if ($refs) {
            for my $name ( keys %$refs ) {
                next if $name eq $order->[-1];
                push @names, $name unless $refs->{$name};
            }
        }
    }

    if ( $self->check_only ) {
        $self->log->info( "dists to be deleted are: @names" );
    }
    else {
        for my $name (@names) {
            $shipwright->backend->trim( name => $name );
        }
        $self->log->fatal( "deleted @names with success" );
    }

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
 --unreferenced                 : to delete all unreferenced dists except the last one
 --check-only                   : show the lists, not really delete

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


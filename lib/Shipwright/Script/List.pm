package Shipwright::Script::List;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level log_file dist/
);

use Shipwright;
use Data::Dumper;

=head2 options
=cut

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
        'dist=s'         => 'dist',
    );
}

=head2 run
=cut

sub run {
    my $self = shift;
    my $dist = shift;

    die "need repository arg" unless $self->repository();

    $self->dist( $dist ) if $dist && ! $self->dist;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level || 'fatal',
        log_file   => $self->log_file,
    );

    my $versions = $shipwright->backend->versions;
    my $source = $shipwright->backend->source;

    if ( $self->dist ) {
        if ( exists $versions->{$self->dist} ) {
            print $self->dist, ': ', "\n";
            print ' ' x 4 . 'version: ', $versions->{$self->dist}, "\n";
            print ' ' x 4 . 'from: ', $source->{$self->dist} || 'CPAN', "\n";
        }
        else {
            print $self->dist, " doesn't exist.\n";
        }
    }
    else {
        for my $dist ( sort keys %$versions ) {
            print $dist, ': ', "\n";
            print ' ' x 4 . 'version: ', $versions->{$dist}, "\n";
            print ' ' x 4 . 'from: ', $source->{$dist} || 'CPAN', "\n";
        }
    }
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
   --dist             sepecify the dist name

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


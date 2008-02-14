package Shipwright::Script::Maintain;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level update_order keep_recommends
      keep_build_requires keep_requires for_dists log_file/
);

use Shipwright;

=head2 options
=cut

sub options {
    (
        'r|repository=s'        => 'repository',
        'l|log-level=s'         => 'log_level',
        'log-file=s'            => 'log_file',
        'update-order'          => 'update_order',
        'keep-recommends=s'     => 'keep_recommends',
        'keep-requires=s'       => 'keep_requires',
        'keep-build-requires=s' => 'keep_build_requires',
        'for-dists=s'           => 'for_dists',
    );
}

=head2 run
=cut

sub run {
    my $self = shift;

    die "need repository arg" unless $self->repository();

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file,
    );

    if ( $self->update_order ) {
        $shipwright->backend->update_order(

            # just for completeness, normally you never need this ;)
            keep_requires =>
              ( defined $self->keep_requires ? $self->keep_requires : 1 ),

            keep_recommends =>
              ( defined $self->keep_recommends ? $self->keep_recommends : 1 ),
            keep_build_requires => (
                defined $self->keep_build_requires
                ? $self->keep_build_requires
                : 1
            ),
            for_dists => [ split /,\s*/, $self->for_dists ],
        );
    }
}

1;

__END__

=head1 NAME

Shipwright::Script::Maintain - maintain a project

=head1 SYNOPSIS

  shipwright maintain --update-order        update the build order

 Options:
   --repository(-r)   specify the repository of our project
   --log-level(-l)    specify the log level
   --update-order     update the build order

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


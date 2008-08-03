package Shipwright::Script::Maintain;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/update_order keep_recommends update_refs
      keep_build_requires keep_requires for_dists/
);

use Shipwright;

sub options {
    (
        'update-order'          => 'update_order',
        'update-refs'           => 'update_refs',
        'keep-recommends=s'     => 'keep_recommends',
        'keep-requires=s'       => 'keep_requires',
        'keep-build-requires=s' => 'keep_build_requires',
        'for-dists=s'           => 'for_dists',
    );
}

sub run {
    my $self = shift;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
    );

    if ( $self->update_order ) {
        $shipwright->backend->update_order(

            # just for completeness, normally you never need this ;)
            keep_requires =>
              ( defined $self->keep_requires ? $self->keep_requires : 1 ),

            keep_recommends =>
              ( defined $self->keep_recommends ? $self->keep_recommends : 0 ),
            keep_build_requires => (
                defined $self->keep_build_requires
                ? $self->keep_build_requires
                : 1
            ),
            for_dists => [ split /,\s*/, $self->for_dists || '' ],
        );
        print "updated order with success\n";
    }

    if ( $self->update_refs ) {
        $shipwright->backend->update_refs;
        print "updated refs with success\n";
    }
}

1;

__END__

=head1 NAME

Shipwright::Script::Maintain - Maintain a project

=head1 SYNOPSIS

 maintain --update-order

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file
 --update-order               : update the build order
 --update-refs                : update refs( times a dist shows in all the require.yml )


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

Shipwright::Script::Maintain - Maintain a project

=head1 SYNOPSIS

 maintain --update-order

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file
 --update-order               : update the build order


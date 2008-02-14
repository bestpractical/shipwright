package Shipwright::Script::Initialize;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(qw/repository log_level log_file/);

use Shipwright;
use File::Spec;
use Shipwright::Util;

=head2 options
=cut

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
    );
}

=head2 run
=cut

sub run {
    my $self       = shift;
    my $repository = shift;
    $self->repository($repository) if $repository;
    die 'need repository arg' unless $self->repository;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file,
    );
    $shipwright->backend->initialize();
}

1;

__END__

=head1 NAME

Shipwright::Script::Initialize - create the specified project

=head1 SYNOPSIS

  shipwright create          create a project

 Options:
   --repository(-r)       specify the repository of our project
   --log-level(-l)            specify the log level

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


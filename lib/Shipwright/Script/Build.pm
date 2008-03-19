package Shipwright::Script::Build;

use warnings;
use strict;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level install_base build_base skip skip_test only_test
      force log_file flags name/
);

use Shipwright;

=head2 options
=cut

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
        'install-base=s' => 'install_base',
        'name=s'         => 'name',
        'skip=s'         => 'skip',
        'flags=s'        => 'flags',
        'skip-test'      => 'skip_test',
        'only-test'      => 'only_test',
        'force'          => 'force',
    );
}

=head2 run
=cut

sub run {
    my $self         = shift;
    my $install_base = shift;
    $self->install_base($install_base)
      if $install_base && !$self->install_base;

    die "need repository arg" unless $self->repository;

    if ( ! $self->name && $self->repository =~ /([-.\w]+)$/ ) {
        $self->name( $1 );
    }

    $self->skip( { map { $_ => 1 } split /\s*,\s*/, $self->skip || '' } );
    $self->flags(
        {
            default => 1,
            map { $_ => 1 } split /\s*,\s*/, $self->flags || ''
        }
    );

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file,
        skip       => $self->skip,
        flags      => $self->flags,
        name       => $self->name,
    );

    $shipwright->backend->export( target => $shipwright->build->build_base );
    $shipwright->build->skip_test(1) if $self->skip_test;
    $shipwright->build->run( map { $_ => $self->$_ }
          qw/install_base only_test force/ );
}

1;

__END__

=head1 NAME

Shipwright::Script::Build - build the specified vessel

=head1 SYNOPSIS

  shipwright build           build a vessel

 Options:
   --repository(-r)   specify the repository of our vessel
   --log-level(-l)    specify the log level
   --install-base     specify install base. default is an autocreated temp dir
   --skip             specify dists which'll be skipped
   --skip-test        specify whether to skip test
   --only-test        just test(the running script is t/test)
   --flags            specify flags
   --name             specify the name of the vessel

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>
    

=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


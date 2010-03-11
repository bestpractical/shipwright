package Shipwright::Script::Create;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Shipwright::Script/;

use Shipwright;
use Shipwright::Util;

__PACKAGE__->mk_accessors('force');

sub options {
    ( 'f|force' => 'force' );
}

sub run {
    my $self = shift;

    my $shipwright = Shipwright->new( repository => $self->repository, );
    $shipwright->backend->initialize();
    $self->log->fatal( 'created with success' );
}

1;

__END__

=head1 NAME

Shipwright::Script::Create - Create a project

=head1 SYNOPSIS

 create -r [repository]

=head1 EXAMPLES

 create -r fs:/tmp/foo
 create -r svk://foo
 create -r svn:file:///tmp/foo/bar
 create -r git:file:///home/me/shipwright/my_proj.git

=head1 OPTIONS

 -r [--repository] REPOSITORY   : specify the repository of our project
 -l [--log-level] LOGLEVEL      : specify the log level
                                  (info, debug, warn, error, or fatal)
 --log-file FILENAME            : specify the log file
 -f [--force]                   : delete the old one if exists

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


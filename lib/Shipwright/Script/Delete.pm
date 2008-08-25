package Shipwright::Script::Delete;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Shipwright::Script/;

use Shipwright;
use File::Spec::Functions qw/catfile catdir/;
use Shipwright::Util;

sub run {
    my $self = shift;
    my $name = shift;

    die "need name arg\n" unless $name;

    my $shipwright = Shipwright->new( repository => $self->repository, );
    my $map = $shipwright->backend->map || {};
    if ( $map->{$name} ) {

        # it's a cpan module
        $name = $map->{$name};
    }

    $shipwright->backend->trim( name => $name );

    print "deleted $name with success\n";
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

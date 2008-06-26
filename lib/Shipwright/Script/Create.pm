package Shipwright::Script::Create;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Shipwright::Script/;

use Shipwright;
use File::Spec;
use Shipwright::Util;

sub run {
    my $self       = shift;
    
    my $shipwright = Shipwright->new(
        repository => $self->repository,
    );
    $shipwright->backend->initialize();
    print "created with success\n";
}

1;

__END__

=head1 NAME

Shipwright::Script::Create - Create a project

=head1 SYNOPSIS

 create -r [repository]

=head1 OPTIONS

 -r [--repository] REPOSITORY   : specify the repository of our project
 -l [--log-level] LOGLEVEL      : specify the log level
                                  (info, debug, warn, error, or fatal)
 --log-file FILENAME            : specify the log file

package Shipwright::Script::Create;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(qw/repository log_level log_file/);

use Shipwright;
use File::Spec;
use Shipwright::Util;

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
    );
}

sub run {
    my $self       = shift;
    
    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file,
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

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
}

1;

__END__

=head1 NAME

Shipwright::Script::Create - create a project

=head1 SYNOPSIS

  shipwright create          create a project

 Options:
   --repository(-r)       specify the repository of our project
   --log-level(-l)            specify the log level
   --log-file         specify the log file


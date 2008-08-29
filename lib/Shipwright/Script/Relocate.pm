package Shipwright::Script::Relocate;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Shipwright::Script/;

use Shipwright;

sub run {
    my $self = shift;
    my ( $name, $new_source ) = @_;

    confess "need name arg\n"   unless $name;
    confess "need source arg\n" unless $new_source;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        source     => $new_source,
    );

    my $source = $shipwright->backend->source;
    if ( exists $source->{$name} ) {
        if ( $source->{$name} eq $new_source ) {
            print "the new source is the same as old source, won't update\n";
        }
        else {
            $source->{$name} = $new_source;
            $shipwright->backend->source($source);
            print "relocated $name to $new_source with success\n";
        }
    }
    else {
        print "haven't found $name in source.yml, won't relocate\n";
    }

}

1;

__END__

=head1 NAME

Shipwright::Script::Relocate - Relocate source of a dist(not cpan)

=head1 SYNOPSIS

 relocate NAME SOURCE

=head1 OPTIONS
   -r [--repository] REPOSITORY    : specify the repository of our project
   -l [--log-level] LOGLEVEL       : specify the log level
   --log-file FILENAME             : specify the log file
                                     (info, debug, warn, error, or fatal)
   NAME                            : sepecify the dist name
   SOURCE                          : specify the new source

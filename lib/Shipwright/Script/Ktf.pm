package Shipwright::Script::Ktf;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(qw/set delete/);

use Shipwright;
use List::MoreUtils qw/uniq/;

sub options {
    (
        'd|delete'       => 'delete',
        's|set=s'        => 'set',
    );
}

sub run {
    my $self = shift;
    my $name = shift;

    die "need name arg\n" unless $name;

    my $shipwright = Shipwright->new( repository => $self->repository, );

    my $ktf = $shipwright->backend->ktf;

    if ( $self->delete || defined $self->set ) {
        if ( $self->delete ) {
            delete $ktf->{$name};
        }
        if ( defined $self->set ) {
            $ktf->{$name} = $self->set;
        }
        $shipwright->backend->ktf($ktf);
    }

    $self->_show_ktf($ktf, $name);
}

sub _show_ktf {
    my $self = shift;
    my $ktf  = shift;
    my $name = shift;

    if ( $self->delete ) {
        print "deleted known test failure for $name\n";
    }
    else {
        if ( defined $self->set ) {
            print "set known test failure condition for $name with success\n";
        }

        print 'the condition is: ' . ( $ktf->{$name} || 'undef' ) . "\n";
    }
}

1;

__END__

=head1 NAME

Shipwright::Script::Ktf - Maintain a dist's known test failure conditions

=head1 SYNOPSIS

 ktf NAME --set '$^O eq "darwin"'

=head1 OPTIONS

 -r [--repository] REPOSITORY   : specify the repository of our project
 -l [--log-level]               : specify the log level
                                  (info, debug, warn, error, or fatal)
 --log-file FILENAME            : specify the log file
 --delete conditions            : delete conditions
 --set conditions               : set conditions

package Shipwright::Script::Flags;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level log_file name add delete set/);

use Shipwright;
use List::MoreUtils qw/uniq/;

sub options {
    (
        'r|repository=s' => 'repository',
        'l|log-level=s'  => 'log_level',
        'log-file=s'     => 'log_file',
        'a|add=s'        => 'add',
        'd|delete=s'     => 'delete',
        's|set=s'        => 'set',
        'name=s'         => 'name',
    );
}

sub run {
    my $self = shift;
    my $name = shift;

    $self->name($name) if $name && !$self->name;

    die "need name arg" unless $self->name();

    $name = $self->name;

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file,
    );

    my $flags = $shipwright->backend->flags;

    unless ( defined $self->add || defined $self->delete || defined $self->set )
    {
        print join( ', ', @{ $flags->{$name} || [] } ), "\n";
        return;
    }

    unless ( 1 == grep { defined $_ } $self->add, $self->delete, $self->set ) {
        die 'you should specify one and only one of add, delete and set';
    }

    if ( defined $self->add ) {
        $self->add( [ grep { /^[-\w]+$/ } split /,\s*/, $self->add ] );
        $flags->{$name} = [ uniq @{ $self->add }, @{ $flags->{$name} || [] } ];
    }
    elsif ( defined $self->delete ) {
        $self->delete( [ split /,\s*/, $self->delete ] );
        my %seen;    # lookup table
        @seen{ @{ $self->delete } } = ();

        @{ $flags->{$name} } =
          grep { exists $seen{$_} } @{ $flags->{$name} || [] };

    }
    elsif ( defined $self->set ) {
        $flags->{$name} = [ grep { /^[-\w]+$/ } split /,\s*/, $self->set ];
    }

    $shipwright->backend->flags($flags);

    print "set flags with success, current flags for $name is "
      . join( ',', @{ $flags->{$name} } ) . "\n";
}

1;

__END__

=head1 NAME

Shipwright::Script::Flags - Maintain a dist's flags

=head1 SYNOPSIS

 flags --name [dist name] --add [flag name]

=head1 OPTIONS

 -r [--repository] REPOSITORY   : specify the repository of our project
 -l [--log-level]               : specify the log level
                                  (info, debug, warn, error, or fatal)
 --log-file FILENAME            : specify the log file
 --name NAME                    : specify the dist name
 --add, --delete, --set FLAGS   : specify the flags, split by commas

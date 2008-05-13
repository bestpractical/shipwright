package Shipwright::Script::Flags;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level log_file dist add delete set/);

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
        'dist=s'         => 'dist',
    );
}

sub run {
    my $self = shift;
    my $dist = shift;

    $self->dist if $dist && !$self->dist;

    die "need dist arg" unless $self->dist();

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file,
    );

    my $flags = $shipwright->backend->flags;

    unless ( defined $self->add || defined $self->delete || defined $self->set )
    {
        print join( ', ', @{ $flags->{ $self->dist } || [] } ), "\n";
        return;
    }

    unless ( 1 == grep { defined $_ } $self->add, $self->delete, $self->set ) {
        die 'you should specify one and only one of add, delete and set';
    }

    if ( defined $self->add ) {
        $self->add( [ grep { /^\w+$/ } split /,\s*/, $self->add ] );
        $flags->{ $self->dist } =
          [ uniq @{ $self->add }, @{ $flags->{ $self->dist } || [] } ];
    }
    elsif ( defined $self->delete ) {
        $self->delete( [ split /,\s*/, $self->delete ] );
        my %seen;    # lookup table
        @seen{ @{ $self->delete } } = ();

        @{ $flags->{ $self->dist } } =
          grep { exists $seen{$_} } @{ $flags->{ $self->dist } || [] };

    }
    elsif ( defined $self->set ) {
        $flags->{ $self->dist } = [ grep { /^\w+$/ } split /,\s*/, $self->set ];
    }

    $shipwright->backend->flags( $flags );

}

1;

__END__

=head1 NAME

Shipwright::Script::Flags - maintain a dist's flags

=head1 SYNOPSIS

  shipwright flags --dist RT --add mysql 

 Options:
   --repository(-r)   specify the repository of our project
   --log-level(-l)    specify the log level
   --log-file         specify the log file
   --dist             specify the dist
   --add, --delete, --set  specify the flags split by comma

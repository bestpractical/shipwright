package Shipwright::Script::Flags;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level log_file dist add delete set/);

use Shipwright;
use List::MoreUtils qw/uniq/;

=head2 options
=cut

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

=head2 run
=cut

sub run {
    my $self = shift;
    my $dist = shift;

    $self->dist if $dist && !$self->dist;

    for (qw/repository dist/) {
        die "need $_ arg" unless $self->$_();
    }

    my $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file,
    );

    my $old = $shipwright->backend->flags( dist => $self->dist ) || [];

    unless ( defined $self->add || defined $self->delete || defined $self->set )
    {
        print join( ', ', @$old ), "\n";
        return;
    }

    unless ( 1 == grep { defined $_ } $self->add, $self->delete, $self->set ) {
        die 'you should specify one and only one of add, delete and set';
    }

    my $new;

    if ( defined $self->add ) {
        $self->add( [ grep { /^\w+$/ } split /,\s*/, $self->add ] );
        $new = [ uniq @{ $self->add }, @$old ];
    }
    elsif ( defined $self->delete ) {
        $self->delete( [ split /,\s*/, $self->delete ] );
        my %seen;    # lookup table
        @seen{ @{ $self->delete } } = ();

        for (@$old) {
            push( @$new, $_ ) unless exists $seen{$_};
        }

    }
    elsif ( defined $self->set ) {
        $new = [ grep { /^\w+$/ } split /,\s*/, $self->set ];
    }

    $shipwright->backend->flags(
        dist  => $self->dist,
        flags => $new,
    );

}

1;

__END__

=head1 NAME

Shipwright::Script::Flags - maintain a dist's flags

=head1 SYNOPSIS

  shipwright flags --dist RT --add mysql 

 Options:
   --repository(-r)   specify the repository of our vessel
   --log-level(-l)    specify the log level
   --dist             specify the dist
   --add, --delete, --set  specify the flags split by comma

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


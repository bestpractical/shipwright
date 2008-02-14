package Shipwright;

use warnings;
use strict;
use Carp;

use version; our $VERSION = '1.0';

use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(qw/backend source build log_level log_file/);

use Shipwright::Backend;
use Shipwright::Source;
use Shipwright::Build;
use Shipwright::Logger;
use Shipwright::Util;

=head2 new

=cut

sub new {
    my $class = shift;

    my %args = @_;

    my $self = { log_level => $args{log_level}, log_file => $args{log_file} };
    bless $self, $class;

    Shipwright::Logger->new($self);

    $self->backend( Shipwright::Backend->new(%args) );

    if ( $args{source} ) {
        $self->source( Shipwright::Source->new(%args) );
    }

    $self->build( Shipwright::Build->new(%args) );

    return $self;
}

1;

__END__

=head1 NAME

Shipwright - Best Practical Builder


=head1 VERSION

This document describes Shipwright version 0.0.2


=head1 SYNOPSIS

    use Shipwright;

=head1 DESCRIPTION


=head1 INTERFACE



=head1 DEPENDENCIES


None.


=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

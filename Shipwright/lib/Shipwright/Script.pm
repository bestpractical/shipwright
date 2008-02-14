package Shipwright::Script;
use strict;
use warnings;
use App::CLI;
use base qw/App::CLI/;

=head2 alias
=cut

sub alias {
    return ( create => 'initialize', ls => 'list');
}

=head2 prepare
=cut

sub prepare {
    my $self = shift;
    if ( $ARGV[0] =~ /--?h(elp)?/i ) {
        $ARGV[0] = 'help';
    }
    return $self->SUPER::prepare(@_);
}

=head2 log
=cut

sub log {
    my $self = shift;
    Shipwright::Logger->new( $self );
    return Log::Log4perl->get_logger( ref $self ) ;
}

1;

__END__

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


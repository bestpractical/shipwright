package Shipwright::Backend;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;

=head2 new

accept the backend part in config as args.
e.g ( module => 'SVK', project => 'test', ... )
returns the the individual Backend object.

=cut

sub new {
    my $class = shift;
    my %args  = @_;

    my $module;

    if ( $args{repository} =~ m{^\s*(svk:|//)} ) {
        $args{repository} =~ s{^\s*svk:}{};
        $module = 'Shipwright::Backend::SVK';
    }
    elsif ( $args{repository} =~ m{^\s*svn[:+]} ) {
        $args{repository} =~ s{^\s*svn:(?!//)}{};
        $module = 'Shipwright::Backend::SVN';
    }
    else {
        croak "invalid repository: $args{repository}\n";
    }

    $module->require or die $@;

    return $module->new(%args);
}

1;

__END__

=head1 NAME

Shipwright::Backend - backend part

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


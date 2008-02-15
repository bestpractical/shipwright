package Shipwright;

use warnings;
use strict;
use Carp;

our $VERSION = '1.0';

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


=head1 SYNOPSIS

    use Shipwright;

=head1 DESCRIPTION

Shipwright's a tool to help you bundle dists.

We don't want to repeat ourself, so when we write a dist, we'll try to use
as many already created and great modules( sure, I bet most of them can be
found on CPAN, though not all ) as we can.

When we want to install it, we have to install all of its dependences to let
it happy. Luckily, we have CPAN:: and CPANPLUS:: to help us install nearly
all of them without much pain, then maybe we need to fix the left non-cpan 
deps manually( usually, we'd fix the non-cpan deps first ;)

This surely works, but there're some drawbacks, especially for a large dist
which uses many cpan modules and even requires other stuff.  The install
instructions maybe too many to not be very friendly to end users, and it's not
easy to do version control with all the dependent dists since most of them are
from somewhere else we can't control.  If we need other non-perl dists( e.g.
we need subversion and swig for SVK ), then things'll be worse.

So we wrote Shipwright, a tool to help you bundle a dist with all of 
dependences, no matter it's a CPAN module or a dist from other place.
And it'll be very easy to install the bundle, usually with just one command:

$ ./bin/shipwright-builder

The thought of shipwright is simple:

   raw material                   shipwright factory            
--------------------           ------------------------       
|  all the seperate|  import   |  internal shipwright |  build
|  dist sources    |  =====>   |  repository          |  ====> 
-------------------|            -----------------------

    final product
------------------------
|  installed to system |
------------------------

So there're mainly two useful commands in shipwright: import and build, which
can be invoked like this:

$ shipwright import ...

$ shipwright build ...

If you get a shipwright build repository, but don't have shipwright installed
on your system, there's no problem to install at all: the repository has
bin/shipwright-builder script.  ( in fact, we encourage you building with
bin/shipwright-builder, because you can hack the script freely without worrying
about global changes )


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

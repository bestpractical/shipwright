package Shipwright::Util::CleanINC;
use strict;
use warnings;
use Config;

sub import {
    @INC = (
        $Config::Config{privlibexp},
        $Config::Config{archlibexp},
        $ENV{PERL5LIB} ? split( ':', $ENV{PERL5LIB} ) : (),
        '.',
    );
}

package inc::Shipwright::Util::CleanINC;
# this file will be copied to inc/ in shipwright's repository
sub import {
    Shipwright::Util::CleanINC->import();
}

1;

=head1 SYNOPSIS

    use Shipwright::Util::CleanINC;

=head1 DESCRIPTION

this will limit the @INC to only contain Core ( technically, they are
$Config::Config{privlibexp} and $Config::Config{archlibexp} ) and PERL5LIB

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Copyright 2007-2009 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


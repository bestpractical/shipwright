package Shipwright::Util::CleanINC;
use strict;
use warnings;
use Config;

sub import {

    # It's expensive to do, but we need to find out what's in @INC now that
    # should be kept (because it was specified on the commandline with -I)
    # and what we should drop because it's baked into perl as a local lib
    my %to_kill = map { $_ => 1} _default_inc();
    my @inc_to_save;
    for (@INC) {
        next if exists $to_kill{$_};
                push @inc_to_save, $_;
            }
    @INC = (
        @inc_to_save,
        '.',
        $ENV{PERL5LIB} ? split( ':', $ENV{PERL5LIB} ) : (),
        $Config::Config{privlibexp},
        $Config::Config{archlibexp},
    );
}



{

    # This code stolen from 
    # http://cpansearch.perl.org/src/ANDYA/Test-Harness-3.15/lib/Test/Harness.pm
    # Cache this to avoid repeatedly shelling out to Perl.
    my @inc;

    sub _default_inc {
        return @inc if @inc;
        local $ENV{PERL5LIB} = '';
        local $ENV{PERLLIB} = '';
        local $ENV{PERL5DB} = '';
        local $ENV{PERL5OPT} = '';
        local $ENV{PERL5ENV} = '';


        my $perl =  $^X;
        # Avoid using -l for the benefit of Perl 6
        chomp( @inc = `$perl -e "print join qq[\\n], \@INC, q[]"` );
        return @inc;
    }
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


package Shipwright::Util;

use warnings;
use strict;
use Carp;
use IPC::Run3;

my $log = Log::Log4perl->get_logger('Shipwright::Util');

BEGIN {
    local $@;
    eval { require YAML::Syck; };
    if ($@) {
        require YAML;
        *Load     = *YAML::Load;
        *Dump     = *YAML::Dump;
        *LoadFile = *YAML::LoadFile;
        *DumpFile = *YAML::DumpFile;
    }
    else {
        *Load     = *YAML::Syck::Load;
        *Dump     = *YAML::Syck::Dump;
        *LoadFile = *YAML::Syck::LoadFile;
        *DumpFile = *YAML::Syck::DumpFile;
    }
}

=head2 Load
to make pod-coverage.t happy.
Load, LoadFile, Dump and DumpFile are just dropped in from YAML or YAML::Syck
=cut
=head2 LoadFile
=cut
=head2 Dump
=cut
=head2 DumpFile
=cut


=head2 run

a wrapper of run3 sub in IPC::Run3.

=cut

sub run {
    my $class = shift;
    my $cmd   = shift;
    my $ignore_failure = shift;

    my ( $out, $err );
    $log->info( "run cmd:\n" . join ' ', @$cmd );
    run3( $cmd, \*STDIN, \$out, \$err );
    $log->info("run output:\n$out") if $out;
    $log->warn("run err:\n$err")    if $err;

    if ($?) {
        $log->error(
            'failed to run ' . join( ' ', @$cmd ) . " with exit number $?" );

        die "something wrong :-(" unless $ignore_failure;
    }

    return ( $out, $err );

}

1;

__END__

=head1 NAME

Shipwright::Util - Shipwright's Utility

=head1 DESCRIPTION

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


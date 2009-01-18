package Shipwright::Util;

use warnings;
use strict;
use Carp;
use IPC::Run3;
use File::Spec::Functions qw/catfile catdir splitpath splitdir tmpdir/;
use File::Temp qw/tempfile/;
use Cwd qw/abs_path/;

use Shipwright;    # we need this to find where Shipwright.pm lives

our ( $SHIPWRIGHT_ROOT, $SHARE_ROOT );

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
    my $class          = shift;
    my $cmd            = shift;
    my $ignore_failure = shift;

    my $log = Log::Log4perl->get_logger('Shipwright::Util');

    my ( $out, $err );
    $log->info( "run cmd: " . join ' ', @$cmd );
    Shipwright::Util->select('null');
    run3( $cmd, \*STDIN, \$out, \$err );
    Shipwright::Util->select('stdout');

    $log->info("run output:\n$out") if $out;
    $log->error("run err:\n$err")   if $err;

    if ($?) {
        $log->error(
            'failed to run ' . join( ' ', @$cmd ) . " with exit number $?" );
        unless ($ignore_failure) {
            confess <<"EOF";
something wrong when execute @$cmd: $?
the output is: $out
the error is: $err
EOF
        }
    }

    return wantarray ? ( $out, $err ) : $out;

}

=head2 shipwright_root

Returns the root directory that Shipwright has been installed into.
Uses %INC to figure out where Shipwright.pm is.

=cut

sub shipwright_root {
    my $self = shift;

    unless ($SHIPWRIGHT_ROOT) {
        my $dir = ( splitpath( $INC{"Shipwright.pm"} ) )[1];
        $SHIPWRIGHT_ROOT = abs_path($dir);
    }

    return ($SHIPWRIGHT_ROOT);
}

=head2 share_root

Returns the 'share' directory of the installed Shipwright module. This is
currently only used to store the initial files in project.

=cut

sub share_root {
    my $self = shift;

    unless ($SHARE_ROOT) {
        my @root = splitdir( $self->shipwright_root );

        if ( $root[-2] ne 'blib' && $root[-1] eq 'lib' ) {

            # so it's -Ilib in the Shipwright's source dir
            $root[-1] = 'share';
        }
        else {
            push @root, qw/auto share dist Shipwright/;
        }

        $SHARE_ROOT = catdir(@root);
    }

    return ($SHARE_ROOT);

}

=head2 select

wrapper for the select in core

=cut

my ( $null_fh, $stdout_fh, $cpan_fh, $cpan_log_path, $cpan_fh_flag );

# use $cpan_fh_flag to record if we've selected cpan_fh before, so so,
# we don't need to warn that any more.

open $null_fh, '>', '/dev/null';

$cpan_log_path = catfile( tmpdir(), 'shipwright_cpan.log');

open $cpan_fh, '>>', $cpan_log_path;
$stdout_fh = select;

sub select {
    my $self = shift;
    my $type = shift;

    if ( $type eq 'null' ) {
        select $null_fh;
    }
    elsif ( $type eq 'stdout' ) {
        select $stdout_fh;
    }
    elsif ( $type eq 'cpan' ) {
        warn "CPAN related output will be at $cpan_log_path\n"
          unless $cpan_fh_flag;
        $cpan_fh_flag = 1;
        select $cpan_fh;
    }
    else {
        confess "unknown type: $type";
    }
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

Copyright 2007-2009 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


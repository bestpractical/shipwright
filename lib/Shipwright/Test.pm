package Shipwright::Test;

use warnings;
use strict;
use base qw/Exporter/;
use Carp;

use File::Temp qw/tempdir/;
use IPC::Cmd qw/can_run/;
use File::Spec::Functions qw/catfile catdir/;
use Shipwright::Util;

our @EXPORT =
  qw/has_svk has_svn create_fs_repo create_svk_repo create_svn_repo devel_cover_enabled test_cmd/;

=head1 NAME

Shipwright::Test - useful subs for tests are here

=head1 SYNOPSIS

    use Shipwright::Test;

=head2 has_svk

check to see if we have svk or not, also limit the svk version to be 2+.
in fact, it also checks svnadmin since we need that to create repo for svk.

=cut

sub has_svk {
    if ( can_run('svk') && can_run('svnadmin') ) {
        my $out = Shipwright::Util->run( [ 'svk', '--version' ], 1 );
        if ( $out && $out =~ /version v(\d)\./i ) {
            return 1 if $1 >= 2;
        }
    }
    return;
}

=head2 has_svn

check to see if we have svn or not, also limit the svn version to be 1.4+.
in fact, it also checks svnadmin since we need that to create repo.

=cut

sub has_svn {
    if ( can_run('svn') && can_run('svnadmin') ) {
        my $out = Shipwright::Util->run( [ 'svn', '--version' ], 1 );
        if ( $out && $out =~ /version 1\.(\d)/i ) {
            return 1 if $1 >= 4;
        }
    }
    return;
}

=head2 create_fs_repo 

create a repo for fs

=cut

sub create_fs_repo {
    return tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
}

=head2 create_svk_repo 

create a repo for svk, will set $ENV{SVKROOT} accrodingly.
return $ENV{SVKROOT}

=cut

sub create_svk_repo {
    $ENV{SVKROOT} = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    my $svk_root_local = catdir( $ENV{SVKROOT}, 'local' );
    system("svnadmin create $svk_root_local");
    system("svk depotmap -i");
    return $ENV{SVKROOT};
}

=head2 create_svn_repo 

create a svn repo.
return the repo's uri, like file:///tmp/foo

=cut

sub create_svn_repo {
    my $repo = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    system("svnadmin create $repo") && confess "create repo failed: $!";
    return "file://$repo";
}

=head2 init

init something, like log

=cut

sub init {
    require Shipwright::Logger;
    Shipwright::Logger->new( log_level => 'FATAL' );
}

=head2 shipwright_bin

return the path of bin/shipwright

=cut

sub shipwright_bin {
    no warnings 'uninitialized';

    # so, we'd better add lib to PERL5LIB before run shipwright.
    # what? you don't want to run shipwright?!!
    # then what did you call this method for?

    $ENV{PERL5LIB} = 'lib:' . $ENV{PERL5LIB} unless $ENV{PERL5LIB} =~ /^lib:/;
    return catfile( 'bin', 'shipwright' );
}

=head2 devel_cover_enabled

return true if -MDevel::Cover

=cut

sub devel_cover_enabled {
    return $INC{'Devel/Cover.pm'};
}

=head2 test_cmd

a simple wrap for test cmd like create, list ...

=cut

sub test_cmd {
    my $repo    = shift;
    my $cmd     = shift;
    my $exp     = shift;
    my $msg     = shift || "@$cmd out";
    my $exp_err = shift;
    my $msg_err = shift || "@$cmd err";

    unshift @$cmd, $^X, '-MDevel::Cover' if devel_cover_enabled;

    require Test::More;
    my ( $out, $err ) = Shipwright::Util->run( $cmd, 1 );    # ingnore failure

    _test_cmd( $out, $exp,     $msg )     if defined $exp;
    _test_cmd( $err, $exp_err, $msg_err ) if defined $exp_err;
}

sub _test_cmd {
    my $out = shift;
    my $exp = shift;
    my $msg = shift;

    if ( ref $exp eq 'Regexp' ) {
        Test::More::like( $out, $exp, $msg );
    }
    else {
        Test::More::is( $out, $exp, $msg );
    }
}

1;

__END__

=head1 INTERFACE

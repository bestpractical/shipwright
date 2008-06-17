package Shipwright::Test;

use warnings;
use strict;
use base qw/Exporter/;

use File::Temp qw/tempdir/;
use IPC::Cmd qw/can_run/;
use File::Spec;

our @EXPORT_OK =
  qw/has_svk has_svn create_svk_repo create_svn_repo devel_cover_enabled/;

=head1 NAME

Shipwright::Test - useful subs for tests are here

=head1 SYNOPSIS

    use Shipwright::Test;

=head2 has_svk

check to see if we have svk or not.
in fact, it also checks svnadmin since we need that to create repo for svk

=cut

sub has_svk {
    return can_run('svk') && can_run('svnadmin');
}

=head2 has_svn

check to see if we have svn or not.
in fact, it also checks svnadmin since we need that to create repo

=cut

sub has_svn {
    return can_run('svn') && can_run('svnadmin');
}

=head2 create_svk_repo 

create a repo for svk, will set $ENV{SVKROOT} accrodingly.
return $ENV{SVKROOT}

=cut

sub create_svk_repo {
    $ENV{SVKROOT} = tempdir;
    my $svk_root_local = File::Spec->catfile( $ENV{SVKROOT}, 'local' );
    system("svnadmin create $svk_root_local");
    system("svk depotmap -i");
    return $ENV{SVKROOT};
}

=head2 create_svn_repo 

create a svn repo.
return the repo's uri, like file:///tmp/foo

=cut

sub create_svn_repo {
    my $repo = tempdir;
    system("svnadmin create $repo") && die "create repo failed: $!";
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
    return File::Spec->catfile( 'bin', 'shipwright' );
}

=head2 devel_cover_enabled

return true if -MDevel::Cover

=cut

sub devel_cover_enabled {
    return $INC{'Devel/Cover.pm'};
}

1;

__END__

=head1 INTERFACE

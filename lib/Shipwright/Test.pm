package Shipwright::Test;

use warnings;
use strict;
use base qw/Exporter/;

use File::Temp qw/tempdir/;
use IPC::Cmd qw/can_run/;

our @EXPORT_OK = qw/has_svk has_svn create_svk_repo create_svn_repo/;

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
    system("svnadmin create $repo" ) && die "create repo failed: $!";
    return "file://$repo";
}

1;


=head2 init

init something, like log

=cut

sub init {
    my $class = shift;
    require Shipwright::Logger;
    Shipwright::Logger->new( log_level => 'FATAL' );
}

__END__

=head1 NAME

Shipwright::Test - useful subs for tests are here


=head1 SYNOPSIS

    use Shipwright::Test;

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




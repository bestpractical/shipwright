package Shipwright::Backend::Git;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile catdir/;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy qw/copy/;
use File::Copy::Recursive qw/dircopy/;
use Cwd qw/getcwd/;
use Shipwright::Backend::FS;

our %REQUIRE_OPTIONS = ( import => [qw/source/] );

use base qw/Shipwright::Backend::Base/;

=head1 NAME

Shipwright::Backend::Git - git repository backend

=head1 DESCRIPTION

This module implements an Git repository backend for Shipwright.

=head1 METHODS

=over

=item initialize

initialize a project.

=cut

sub initialize {
    my $self = shift;

    my $dir = $self->SUPER::initialize(@_);

    my $cwd = getcwd;
    chdir $dir;
    Shipwright::Util->run( [ $ENV{'SHIPWRIGHT_GIT'}, 'init' ] );
    Shipwright::Util->run( [ $ENV{'SHIPWRIGHT_GIT'}, 'add', '.' ] );
    Shipwright::Util->run(
        [ $ENV{'SHIPWRIGHT_GIT'}, 'commit', '-m', 'creating repository' ] );

    my $path = $self->repository;
    $path =~ s!^file://!!;    # this is always true since we check that before

    Shipwright::Util->run( [ 'rm', '-rf', $path ] );

    dircopy( catdir( $dir, '.git' ), $path )
      or confess "can't copy $dir to " . $path . ": $!";
    chdir $cwd;
}

my $cloned_dir;

sub cloned_dir {
    my $self = shift;
    return $cloned_dir if $cloned_dir;

    my $base_dir =
      tempdir( 'shipwright_backend_git_XXXXXX', CLEANUP => 1, TMPDIR => 1 );

    my $target = catdir( $base_dir, 'clone' );
    Shipwright::Util->run(
        [ $ENV{'SHIPWRIGHT_GIT'}, 'clone', $self->repository, $target ] );
    return $cloned_dir = $target;
}

=item check_repository

check if the given repository is valid.

=cut

sub check_repository {
    my $self = shift;
    my %args = @_;

    if ( $args{action} eq 'create' ) {
        if ( $self->repository =~ m{^file://} ) {
            return 1;
        }
        else {
            $self->log->error(
                "git backend only supports creating local repository");
            return;
        }
    }
    else {

        return $self->SUPER::check_repository(@_);
    }
    return;
}

sub fs_backend {
    my $self = shift;
    return $self->{fs_backend} if $self->{fs_backend};
    # XXX TODO not a great place to clone, need refactor
    my $cloned_dir = $self->cloned_dir;
    $self->{fs_backend} = Shipwright::Backend::FS->new(
        repository => $self->cloned_dir,
    );
    return $self->{fs_backend};
}

sub _cmd {
    my $self = shift;
    return $self->fs_backend->_cmd(@_);
}

sub _yml {
    my $self = shift;
    return $self->fs_backend->_yml(@_);
}

sub info {
    my $self = shift;
    return $self->fs_backend->info(@_);
}

sub _update_dir {
    my $self = shift;
    return $self->fs_backend->_update_dir(@_);
}

sub _update_file {
    my $self = shift;
    return $self->fs_backend->_update_file(@_);
}

sub import {
    my $self = shift;
    return $self->fs_backend->import(@_);
}

sub DESTROY {
    my $self = shift;
    my $cwd  = getcwd;
    chdir $self->cloned_dir;
    Shipwright::Util->run( [ $ENV{'SHIPWRIGHT_GIT'}, 'add', '.' ] );
    #TODO comment need to be something special
    Shipwright::Util->run(
        [ $ENV{'SHIPWRIGHT_GIT'}, 'commit', '-m', 'comment', '-a' ], 1 );
    Shipwright::Util->run( [ $ENV{'SHIPWRIGHT_GIT'}, 'push' ] );
    chdir $cwd;
}

=back

=cut

1;

__END__

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2009 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

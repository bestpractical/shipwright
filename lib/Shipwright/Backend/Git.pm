package Shipwright::Backend::Git;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile catdir/;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy::Recursive qw/rcopy/;
use Cwd qw/getcwd/;
use Shipwright::Backend::FS;
use File::Path qw/remove_tree make_path/;
use MIME::Base64::URLSafe;

our %REQUIRE_OPTIONS = ( import => [qw/source/] );

use base qw/Shipwright::Backend::Base/;

=head1 NAME

Shipwright::Backend::Git - Git repository backend

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

    my $path = $self->repository;
    $path =~ s!^file://!!;    # this is always true since we check that before

    Shipwright::Util->run( sub { remove_tree( $path ) } );
    Shipwright::Util->run( sub { make_path( $path ) } );

    my $cwd = getcwd;
    chdir $path;
    Shipwright::Util->run( [ $ENV{'SHIPWRIGHT_GIT'}, '--bare', 'init' ] );

    $self->initialize_cloned_dir;
    rcopy( $dir, $self->cloned_dir )
      or confess "can't copy $dir to " . $path . ": $!";
    $self->commit( comment => 'create project' );
    chdir $cwd;
}

=item cloned_dir

since nearly all the time we need to clone first to use git, it's good that
we keep a cloned dir.
returns the cloned_dir

=cut

sub cloned_dir {
    my $self      = shift;
    my $need_init = shift;
    my $base_dir  = $self->cloned_base_dir;
    my $target = catdir( $base_dir, 'clone.git' );

# if explicitly defined $need_init, we should do exactly what it asks
# else, if the $target is not existed yet, we do the init thing
    if ( defined $need_init ) {
        if ( $need_init ) {
            $self->initialize_cloned_dir;
        }
        else {
            return $target;
        }
    }
    elsif ( !-e $target ) {
        $self->initialize_cloned_dir;
    }
    return $target;
}

=item cloned_base_dir

=cut

sub cloned_base_dir {
    my $self = shift;
    my $dir  = catdir( Shipwright::Util->shipwright_user_root(),
        'repositories', urlsafe_b64encode( $self->repository ) );
    make_path($dir) unless -e $dir;
    return $dir;
}

=item initialize_cloned_dir

=cut

sub initialize_cloned_dir {
    my $self = shift;
    # the 0 is very important, or it may results in recursion
    my $target = $self->cloned_dir( 0 ); 
    remove_tree( $target ) if -e $target;

    Shipwright::Util->run(
        [ $ENV{'SHIPWRIGHT_GIT'}, 'clone', $self->repository, $target ] );
    my $cwd = getcwd;
    chdir $target; 
    # git 1.6.3.3 will warn if we don't specify push.default
    Shipwright::Util->run(
        [ $ENV{'SHIPWRIGHT_GIT'}, 'config', 'push.default', 'matching' ] );
    chdir $cwd;
    return $target;
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

=item fs_backend

git's local clone is nearly the same as a fs backend, this returns
a Shipwright::Backend::FS object which reflects the cloned_dir repository.

=cut

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
    my $return = $self->fs_backend->_yml(@_);
    if ( @_ > 1 ) {
        $self->commit( comment => 'update ' . $_[0] );
    }
    return $return;
}

=item info

=cut

sub info {
    my $self = shift;
    return $self->fs_backend->info(@_);
}

sub _update_dir {
    my $self = shift;
    $self->fs_backend->_update_dir(@_);
    $self->commit( comment => 'update ' . $_[0] );
}

sub _update_file {
    my $self = shift;
    $self->fs_backend->_update_file(@_);
    $self->commit( comment => 'update ' . $_[0] );
}

=item import

=cut 

sub import {
    my $self = shift;
    return unless ref $self; # get rid of class->import
    $self->fs_backend->import(@_);
    my %args = @_;
    my $name = $args{source};
    $name =~ s!.*/!!;
    $self->commit( comment => 'import ' . $name );
}

=item commit

=cut

sub commit {
    my $self = shift;
    my %args =
      ( comment => 'comment', @_ );    # git doesn't allow comment to be blank

    if ( $self->cloned_dir ) {
        my $cwd = getcwd;
        chdir $self->cloned_dir or return;

        Shipwright::Util->run( [ $ENV{'SHIPWRIGHT_GIT'}, 'add', '-f', '.' ] );

        #    TODO comment need to be something special
        Shipwright::Util->run(
            [ $ENV{'SHIPWRIGHT_GIT'}, 'commit', '-m', $args{comment} ], 1 );
        Shipwright::Util->run(
            [ $ENV{'SHIPWRIGHT_GIT'}, 'push', 'origin', 'master' ] );
        chdir $cwd;
    }
    return;
}

=item delete

=cut 

sub delete {
    my $self = shift;
    $self->fs_backend->delete(@_);
    my %args = @_;
    $self->commit( comment => 'delete ' . $args{path} );
}

=item move

=cut 

sub move {
    my $self = shift;
    $self->fs_backend->move(@_);
    my %args     = @_;
    my $path     = $args{path};
    my $new_path = $args{new_path};
    $self->commit( comment => "move $path to $new_path" );
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

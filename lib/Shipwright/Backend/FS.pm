package Shipwright::Backend::FS;

use warnings;
use strict;
use Carp;
use File::Spec;
use Shipwright::Util;
use File::Copy qw/copy/;
use File::Copy::Recursive qw/dircopy/;

our %REQUIRE_OPTIONS = ( import => [qw/source/] );

use base qw/Shipwright::Backend::Base/;

=head1 NAME

Shipwright::Backend::FS - File System backend

=head1 DESCRIPTION

This module implements file system backend

=head1 METHODS

=over

=item initialize

Initialize a project.

=cut

sub initialize {
    my $self = shift;

    my $dir = $self->SUPER::initialize(@_);

    $self->delete;    # clean repository in case it exists

    dircopy( $dir, $self->repository );
}

# a cmd generating factory
sub _cmd {
    my $self = shift;
    my $type = shift;
    my %args = @_;
    $args{path} ||= '';

    for ( @{ $REQUIRE_OPTIONS{$type} } ) {
        croak "$type need option $_" unless $args{$_};
    }

    my $cmd;

    if ( $type eq 'checkout' || $type eq 'export' ) {
        $cmd = [ 'cp', '-r', $self->repository . $args{path}, $args{target} ];
    }
    elsif ( $type eq 'import' ) {
        if ( $args{_extra_tests} ) {
            $cmd = [
                'cp', '-r',
                $args{source}, $self->repository . '/t/extra'
            ];
        }
        else {
            if ( my $script_dir = $args{build_script} ) {
                $cmd = [
                    'cp',        '-r',
                    "$script_dir/", $self->repository . "/scripts/$args{name}",
                ];
            }
            else {
                $cmd = [
                    'cp',          '-r',
                    "$args{source}/", $self->repository . "/dists/$args{name}",
                ];
            }
        }
    }
    elsif ( $type eq 'delete' ) {
        $cmd = [ 'rm', '-rf', $self->repository . $args{path}, ];
    }
    elsif ( $type eq 'move' ) {
        $cmd = [
            'mv',
            $self->repository . $args{path},
            $self->repository . $args{new_path}
        ];
    }
    elsif ( $type eq 'info' || $type eq 'list' ) {
        $cmd = [ 'ls', $self->repository . $args{path} ];
    }
    elsif ( $type eq 'cat' ) {
        $cmd = [ 'cat', $self->repository . $args{path} ];
    }
    else {
        croak "invalid command: $type";
    }

    return $cmd;
}

=item _yml


=cut

sub _yml {
    my $self = shift;
    my $path = shift;
    my $yml  = shift;

    my $file = File::Spec->catfile( $self->repository, $path );
    if ($yml) {

        Shipwright::Util::DumpFile( $file, $yml );
    }
    else {
        Shipwright::Util::LoadFile($file);
    }
}

=item info


=cut

sub info {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';

    my ( $info, $err ) = $self->SUPER::info( path => $path );

    if (wantarray) {
        return $info, $err;
    }
    else {
        return if $info =~ /no such file or directory/;
        return $info;
    }
}

=item check_repository

Check if the given repository is valid.

=cut

sub check_repository {
    my $self = shift;
    return $self->SUPER::check_repository(@_);
}

sub _update_file {
    my $self   = shift;
    my $path   = shift;
    my $latest = shift;

    my $file = File::Spec->catfile( $self->repository, $path );

    copy( $latest, $file );
}

=back

=cut

1;

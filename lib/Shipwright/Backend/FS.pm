package Shipwright::Backend::FS;

use warnings;
use strict;
use Carp;
use File::Spec;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy qw/copy/;
use File::Copy::Recursive qw/dircopy/;
use List::MoreUtils qw/uniq/;
use File::Path;

our %REQUIRE_OPTIONS = ( import => [qw/source/] );

use base qw/Class::Accessor::Fast/;
__PACKAGE__->mk_accessors(qw/repository log/);

=head1 NAME

Shipwright::Backend::FS - File System backend

=head1 DESCRIPTION

This module implements file system backend

=head1 METHODS

=over

=item new

This is the constructor.

=cut

sub new {
    my $class = shift;
    my $self  = {@_};

    bless $self, $class;
    $self->log( Log::Log4perl->get_logger( ref $self ) );
    return $self;
}

=item initialize

Initialize a project.

=cut

sub initialize {
    my $self = shift;

    $self->delete;    # clean repository in case it exists
    mkpath $self->repository unless -e $self->repository;

    dircopy( Shipwright::Util->share_root, $self->repository );

    # share_root can't keep empty dirs, we have to create them manually
    for (qw/dists scripts t/) {
        mkdir File::Spec->catfile( $self->repository, $_ );
    }

    # hack for share_root living under blib/
    unlink( File::Spec->catfile( $self->repository, '.exists' ) );

    return 1;
}

=item import

Import a dist.

=cut

sub import {
    my $self = shift;
    return unless @_;
    my %args = @_;
    my $name = $args{source};
    $name =~ s{.*/}{};

    unless ( $args{_extra_tests} ) {
        if ( $args{build_script} ) {
            if ( $self->info( path => "scripts/$name" )
                && not $args{overwrite} )
            {
                $self->log->warn(
"path scripts/$name alreay exists, need to set overwrite arg to overwrite"
                );
            }
            else {
                $self->log->info(
                    "import $args{source}'s scripts to " . $self->repository );
                Shipwright::Util->run(
                    $self->_cmd( import => %args, name => $name ) );
            }
        }
        else {
            if ( $self->info( path => "dists/$name" ) && not $args{overwrite} )
            {
                $self->log->warn(
"path dists/$name alreay exists, need to set overwrite arg to overwrite"
                );
            }
            else {
                $self->log->info(
                    "import $args{source} to " . $self->repository );
                $self->_add_to_order($name);

                my $version = $self->version;
                $version->{$name} = $args{version};
                $self->version($version);

                Shipwright::Util->run(
                    $self->_cmd( import => %args, name => $name ) );
            }
        }
    }
    else {
        Shipwright::Util->run( $self->_cmd( import => %args, name => $name ) );
    }
}

=item export


=cut

sub export {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    $self->log->info(
        'export ' . $self->repository . "/$path to $args{target}" );
    Shipwright::Util->run( $self->_cmd( checkout => %args ) );
}

=item checkout

=cut

sub checkout;

*checkout = *export;

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

    if ( $type eq 'checkout' ) {
        $cmd = [ 'cp', '-r', $self->repository . $args{path}, $args{target} ];
    }
    elsif ( $type eq 'import' ) {
        if ( $args{_extra_tests} ) {
            $cmd = [
                'cp', '-r',
                $args{source}, join( '/', $self->repository, 't', 'extra' ),
            ];
        }
        else {
            if ( my $script_dir = $args{build_script} ) {
                $cmd = [
                    'cp',        '-r',
                    $script_dir, $self->repository . "/scripts/$args{name}/",
                ];
            }
            else {
                $cmd = [
                    'cp',          '-r',
                    $args{source}, $self->repository . "/dists/$args{name}",
                ];
            }
        }
    }
    elsif ( $type eq 'delete' ) {
        $cmd = [ 'rm', '-rf', join '/', $self->repository, $args{path}, ];
    }
    elsif ( $type eq 'move' ) {
        $cmd = [
            'mv',
            join( '/', $self->repository, $args{path} ),
            join( '/', $self->repository, $args{new_path} )
        ];
    }
    elsif ( $type eq 'info' ) {
        $cmd = [ 'ls', join '/', $self->repository, $args{path} ];
    }
    else {
        croak "invalid command: $type";
    }

    return $cmd;
}

# add a dist to order

sub _add_to_order {
    my $self = shift;
    my $name = shift;

    my $order = $self->order;

    unless ( grep { $name eq $_ } @$order ) {
        $self->log->info( "add $name to order for " . $self->repository );
        push @$order, $name;
        $self->order($order);
    }
}

=item update_order

Regenerate the dependency order.

=cut

sub update_order {
    my $self = shift;
    my %args = @_;

    $self->log->info( "update order for " . $self->repository );

    my @dists = @{ $args{for_dists} || [] };
    unless (@dists) {
        my ($out) =
          Shipwright::Util->run( [ 'ls', $self->repository . '/scripts' ] );
        @dists = split /\s+/, $out;
        chomp @dists;
        s{/$}{} for @dists;
    }

    my $require = {};

    for (@dists) {
        $self->_fill_deps( %args, require => $require, name => $_ );
    }

    require Algorithm::Dependency::Ordered;
    require Algorithm::Dependency::Source::HoA;

    my $source = Algorithm::Dependency::Source::HoA->new($require);
    $source->load();
    my $dep = Algorithm::Dependency::Ordered->new( source => $source, )
      or die $@;
    my $order = $dep->schedule_all();

    $self->order($order);
}

sub _fill_deps {
    my $self    = shift;
    my %args    = @_;
    my $require = $args{require};
    my $name    = $args{name};

    return if $require->{$name};
    my $req = Shipwright::Util::LoadFile(
        $self->repository . "/scripts/$name/require.yml" );

    if ( $req->{requires} ) {
        for (qw/requires recommends build_requires/) {
            push @{ $require->{$name} }, keys %{ $req->{$_} }
              if $args{"keep_$_"};
        }
        @{ $require->{$name} } = uniq @{ $require->{$name} };
    }
    else {

        #for back compatbility
        push @{ $require->{$name} }, keys %$req;
    }

    for my $dep ( @{ $require->{$name} } ) {
        next if $require->{$dep};
        $self->_fill_deps( %args, name => $dep, require => $require );
    }
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

=item order

Get or set the dependency order.

=cut

sub order {
    my $self  = shift;
    my $order = shift;
    my $path  = File::Spec->catfile( 'shipwright', 'order.yml' );
    return $self->_yml( $path, $order );
}

=item map

Get or set the map.

=cut

sub map {
    my $self = shift;
    my $map  = shift;

    my $path = File::Spec->catfile( 'shipwright', 'map.yml' );
    return $self->_yml( $path, $map );
}

=item source

Get or set the sources map.

=cut

sub source {
    my $self   = shift;
    my $source = shift;
    my $path   = File::Spec->catfile( 'shipwright', 'source.yml' );
    return $self->_yml( $path, $source );
}

=item delete


=cut

sub delete {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    if ( $self->info( path => $path ) ) {
        $self->log->info( "delete " . $self->repository . "/$path" );
        Shipwright::Util->run( $self->_cmd( delete => path => $path ), 1 );
    }
}

=item move


=cut

sub move {
    my $self     = shift;
    my %args     = @_;
    my $path     = $args{path} || '';
    my $new_path = $args{new_path} || '';
    if ( $self->info( path => $path ) ) {
        $self->log->info(
            "move " . $self->repository . "/$path to /$new_path" );
        Shipwright::Util->run(
            $self->_cmd(
                move     => path => $path,
                new_path => $new_path,
            ),
        );
    }
}

=item info


=cut

sub info {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';

    my ( $info, $err ) =
      Shipwright::Util->run( $self->_cmd( info => path => $path ), 1 );
    $self->log->warn($err) if $err;

    if (wantarray) {
        return $info, $err;
    }
    else {
        return if $info =~ /no such file or directory/;
        return $info;
    }
}

=item test_script

Set test_script for a project, i.e. update the t/test script.

=cut

sub test_script {
    my $self   = shift;
    my %args   = @_;
    my $script = $args{source};
    croak 'need source option' unless $script;

    my $file = File::Spec->catfile( $self->repository, 't', 'test' );

    copy( $args{source}, $file );
}

=item requires

Return the hashref of require.yml for a dist.

=cut

sub requires {
    my $self = shift;
    my %args = @_;
    my $name = $args{name};

    return $self->_yml(
        File::Spec->catfile( 'scripts', $name, 'require.yml' ) );
}

=item flags

Get or set flags.

=cut

sub flags {
    my $self  = shift;
    my $flags = shift;

    my $path = File::Spec->catfile( 'shipwright', 'flags.yml' );
    return $self->_yml( $path, $flags );
}

=item version

Get or set version.

=cut

sub version {
    my $self    = shift;
    my $version = shift;

    my $path = File::Spec->catfile( 'shipwright', 'version.yml' );
    return $self->_yml( $path, $version );
}

=item check_repository

Check if the given repository is valid.

=cut

sub check_repository {
    my $self = shift;
    my %args = @_;

    if ( $args{action} eq 'create' ) {
        return 1;
    }
    else {

        # every valid shipwright repo has 'shipwright' subdir;
        my $info = $self->info( path => 'shipwright' );

        return 1 if $info;
    }

    return;
}

=item update

Update shipwright's own files, e.g. bin/shipwright-builder.

=cut

sub update {
    my $self = shift;
    my %args = @_;

    croak "need path option" unless $args{path};

    croak "$args{path} seems not shipwright's own file"
      unless -e File::Spec->catfile( Shipwright::Util->share_root,
        $args{path} );

    $args{path} = '/' . $args{path} unless $args{path} =~ m{^/};

    my $file =
      File::Spec->catfile( $self->repository, 'shipwright', $args{path} );

    copy( File::Spec->catfile( Shipwright::Util->share_root, $args{path} ),
        $file );
}

=item ktf

Get or set known failure conditions.

=cut

sub ktf {
    my $self    = shift;
    my $failure = shift;

    my $file =
      File::Spec->catfile( $self->repository, 'shipwright', 'ktf.yml' );
    if ($failure) {
        Shipwright::Util::DumpFile( $file, $failure );
    }
    else {
        Shipwright::Util::LoadFile($file) || {};
    }
}

=back

=cut

1;

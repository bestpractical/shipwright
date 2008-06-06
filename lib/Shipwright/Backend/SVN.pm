package Shipwright::Backend::SVN;

use warnings;
use strict;
use Carp;
use File::Spec;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy qw/copy/;
use File::Copy::Recursive qw/dircopy/;

our %REQUIRE_OPTIONS = ( import => [qw/source/], );

use base qw/Class::Accessor::Fast/;
__PACKAGE__->mk_accessors(qw/repository log/);

=head1 NAME

Shipwright::Backend::SVN - SVN repository backend

=head1 DESCRIPTION

This module implements a SVN repository backend for Shipwright.

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
    my $dir = tempdir( CLEANUP => 1 );
    dircopy( Shipwright::Util->share_root, $dir );

    # share_root can't keep empty dirs, we have to create them manually
    for (qw/dists scripts t/) {
        mkdir File::Spec->catfile( $dir, $_ );
    }

    # hack for share_root living under blib/
    unlink( File::Spec->catfile( $dir, '.exists' ) );

    $self->delete;    # clean repository in case it exists
    $self->log->info( 'initialize ' . $self->repository );
    $self->import(
        source      => $dir,
        comment     => 'create project',
        _initialize => 1,
    );

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

    unless ( $args{_initialize} ) {
        if ( $args{_extra_tests} ) {
            $self->delete( path => "t/extra" );
            $self->log->info( "import extra tests to " . $self->repository );
            Shipwright::Util->run(
                $self->_cmd( import => %args, name => $name ) );
        }
        elsif ( $args{build_script} ) {
            if ( $self->info( path => "scripts/$name" )
                && not $args{overwrite} )
            {
                $self->log->warn(
"path scripts/$name alreay exists, need to set overwrite arg to overwrite"
                );
            }
            else {
                $self->delete( path => "scripts/$name" );
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
                $self->delete( path => "dists/$name" );
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

A wrapper around svn's export command. Export a project, partly or as a whole.

=cut

sub export {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    $self->log->info(
        'export ' . $self->repository . "/$path to $args{target}" );
    Shipwright::Util->run( $self->_cmd( export => %args ) );
}

=item checkout

A wrapper around svn's checkout command. Checkout a project, partly or as a
whole.

=cut

sub checkout {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    $self->log->info(
        'export ' . $self->repository . "/$path to $args{target}" );
    Shipwright::Util->run( $self->_cmd( checkout => @_ ) );
}

=item commit

A wrapper around svn's commit command.

=cut

sub commit {
    my $self = shift;
    my %args = @_;
    $self->log->info( 'commit ' . $args{path} );
    Shipwright::Util->run( $self->_cmd( commit => @_ ), 1 );
}

# a cmd generating factory
sub _cmd {
    my $self = shift;
    my $type = shift;
    my %args = @_;
    $args{path}    ||= '';
    $args{comment} ||= '';

    for ( @{ $REQUIRE_OPTIONS{$type} } ) {
        croak "$type need option $_" unless $args{$_};
    }

    my $cmd;

    if ( $type eq 'checkout' ) {
        $cmd =
          [ 'svn', 'checkout', $self->repository . $args{path}, $args{target} ];
    }
    elsif ( $type eq 'export' ) {
        $cmd =
          [ 'svn', 'export', $self->repository . $args{path}, $args{target} ];
    }
    elsif ( $type eq 'import' ) {
        if ( $args{_initialize} ) {
            $cmd = [
                'svn',         'import',
                $args{source}, $self->repository,
                '-m',          q{'} . $args{comment} . q{'}
            ];
        }
        elsif ( $args{_extra_tests} ) {
            $cmd = [
                'svn', 'import',
                $args{source}, join( '/', $self->repository, 't', 'extra' ),
                '-m', q{'} . $args{comment} . q{'},
            ];
        }
        else {
            if ( my $script_dir = $args{build_script} ) {
                $cmd = [
                    'svn',       'import',
                    $script_dir, $self->repository . "/scripts/$args{name}/",
                    '-m',        q{'} . $args{comment} || '' . q{'},
                ];
            }
            else {
                $cmd = [
                    'svn',         'import',
                    $args{source}, $self->repository . "/dists/$args{name}",
                    '-m',          q{'} . $args{comment} . q{'},
                ];
            }
        }
    }
    elsif ( $type eq 'commit' ) {
        $cmd =
          [ 'svn', 'commit', '-m', q{'} . $args{comment} . q{'}, $args{path} ];
    }
    elsif ( $type eq 'delete' ) {
        $cmd = [
            'svn', 'delete', '-m', q{'} . 'delete' . $args{path} . q{'},
            join '/', $self->repository, $args{path}
        ];
    }
    elsif ( $type eq 'move' ) {
        $cmd = [
            'svn',
            'move',
            '-m',
            q{'} . "move $args{path} to $args{new_path}" . q{'},
            join( '/', $self->repository, $args{path} ),
            join( '/', $self->repository, $args{new_path} )
        ];
    }
    elsif ( $type eq 'info' ) {
        $cmd = [ 'svn', 'info', join '/', $self->repository, $args{path} ];
    }
    elsif ( $type eq 'propset' ) {
        $cmd = [
            'svn',       'propset',
            $args{type}, q{'} . $args{value} . q{'},
            $args{path}
        ];
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
        my ($out) = Shipwright::Util->run(
            [ 'svn', 'ls', $self->repository . '/scripts' ] );
        my $sep = $/;
        @dists = split /$sep/, $out;
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

    my ($string) = Shipwright::Util->run(
        [ 'svn', 'cat', $self->repository . "/scripts/$_/require.yml" ], 1 );

    my $req = Shipwright::Util::Load($string) || {};

    if ( $req->{requires} ) {
        for (qw/requires recommends build_requires/) {
            push @{ $require->{$name} }, keys %{ $req->{$_} }
              if $args{"keep_$_"};
        }
    }
    else {

        #for back compatbility
        push @{ $require->{$name} }, keys %$req;
    }

    for my $dep ( @{ $require->{$name} } ) {
        next if $require->{$dep};
        $self->_fill_deps( %args, name => $dep );
    }
}

=item order

Get or set the dependency order.

=cut

sub order {
    my $self  = shift;
    my $order = shift;
    if ($order) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, 'order.yml' );

        $self->checkout(
            path   => '/shipwright',
            target => $dir,
        );

        Shipwright::Util::DumpFile( $file, $order );
        $self->commit( path => $file, comment => "set order" );

    }
    else {
        my ($out) = Shipwright::Util->run(
            [ 'svn', 'cat', $self->repository . '/shipwright/order.yml' ] );
        return Shipwright::Util::Load($out);
    }
}

=item map

Get or set the map.

=cut

sub map {
    my $self = shift;
    my $map  = shift;
    if ($map) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, 'map.yml' );

        $self->checkout(
            path   => '/shipwright',
            target => $dir,
        );

        Shipwright::Util::DumpFile( $file, $map );
        $self->commit( path => $file, comment => "set map" );

    }
    else {
        my ($out) = Shipwright::Util->run(
            [ 'svn', 'cat', $self->repository . '/shipwright/map.yml' ] );
        return Shipwright::Util::Load($out);
    }
}

=item source

Get or set the sources map.

=cut

sub source {
    my $self   = shift;
    my $source = shift;
    if ($source) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, 'source.yml' );

        $self->checkout(
            path   => '/shipwright',
            target => $dir,
        );

        Shipwright::Util::DumpFile( $file, $source );
        $self->commit( path => $file, comment => "set source" );

    }
    else {
        my ($out) = Shipwright::Util->run(
            [ 'svn', 'cat', $self->repository . '/shipwright/source.yml' ] );
        return Shipwright::Util::Load($out);
    }
}

=item delete

A wrapper around svn's delete command.

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

A wrapper around svn's move command.

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

A wrapper around svn's info command.

=cut

sub info {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';

    my ( $info, $err ) =
      Shipwright::Util->run( $self->_cmd( info => path => $path ), 1 );

    if (wantarray) {
        return $info, $err;
    }
    else {
        if ($err) {
            $err =~ s/\s+$//;
            $self->log->warn($err);
            return;
        }
        return $info;
    }
}

=item propset

A wrapper around svn's propset command.

=cut

sub propset {
    my $self = shift;
    my %args = @_;
    my $dir  = tempdir( CLEANUP => 1 );

    $self->checkout( target => $dir, );
    Shipwright::Util->run(
        $self->_cmd(
            propset => %args,
            path => File::Spec->catfile( $dir, $args{path} )
        )
    );

    $self->commit(
        path    => File::Spec->catfile( $dir, $args{path} ),
        comment => "set prop $args{type}"
    );
}

=item test_script

Set test_script for a project, i.e. update the t/test script.

=cut

sub test_script {
    my $self   = shift;
    my %args   = @_;
    my $script = $args{source};
    croak 'need source option' unless $script;

    my $dir = tempdir( CLEANUP => 1 );

    $self->checkout(
        path   => '/t',
        target => $dir,
    );

    my $file = File::Spec->catfile( $dir, 'test' );

    copy( $args{source}, $file );
    $self->commit( path => $file, comment => "update test script" );
}

=item requires

Return the hashref of require.yml for a dist.

=cut

sub requires {
    my $self = shift;
    my %args = @_;
    my $name = $args{name};

    my ($string) = Shipwright::Util->run(
        [ 'svn', 'cat', $self->repository . "/scripts/$name/require.yml" ], 1 );
    return Shipwright::Util::Load($string) || {};
}

=item flags

Get or set flags.

=cut

sub flags {
    my $self  = shift;
    my $flags = shift;

    if ($flags) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, 'flags.yml' );

        $self->checkout(
            path   => '/shipwright',
            target => $dir,
        );

        Shipwright::Util::DumpFile( $file, $flags );
        $self->commit( path => $file, comment => 'set flags' );
    }
    else {
        my ($out) = Shipwright::Util->run(
            [ 'svn', 'cat', $self->repository . '/shipwright/flags.yml' ] );
        return $out = Shipwright::Util::Load($out) || {};
    }
}

=item version

Get or set version.

=cut

sub version {
    my $self    = shift;
    my $version = shift;

    if ($version) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, 'version.yml' );

        $self->checkout(
            path   => '/shipwright',
            target => $dir,
        );

        Shipwright::Util::DumpFile( $file, $version );

        $self->commit(
            path    => $file,
            comment => 'set version',
        );
    }
    else {
        my ($out) = Shipwright::Util->run(
            [ 'svn', 'cat', $self->repository . '/shipwright/version.yml' ] );
        return Shipwright::Util::Load($out) || {};
    }
}

=item check_repository

Check if the given repository is valid.

=cut

sub check_repository {
    my $self = shift;
    my %args = @_;

    if ( $args{action} eq 'create' ) {

        my ( $info, $err ) = $self->info;

        return 1 if $info || $err && $err =~ /Not a valid URL/;

    }
    else {

        # every valid shipwright repo has 'shipwright' subdir;
        my $info = $self->info( path => 'shipwright' );
        return 1 if $info;

    }

    return 0;
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

    my $dir = tempdir( CLEANUP => 1 );

    my $file = File::Spec->catfile( $dir, $args{path} );

    if ( $args{path} =~ m{(.*)/} ) {
        $self->checkout(
            path   => $1,
            target => $file,
        );

        copy( File::Spec->catfile( Shipwright::Util->share_root, $args{path} ),
            $file );
        $self->commit(
            path    => $file,
            comment => "update $args{path}",
        );
    }
}

=back

=cut

1;

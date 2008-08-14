package Shipwright::Backend::Base;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile catdir/;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy qw/copy/;
use File::Copy::Recursive qw/dircopy/;
use List::MoreUtils qw/uniq/;

our %REQUIRE_OPTIONS = ( import => [qw/source/] );

use base qw/Class::Accessor::Fast/;
__PACKAGE__->mk_accessors(qw/repository log/);

=head1 NAME

Shipwright::Backend::Base - Base Backend Class

=head1 DESCRIPTION

Base Backend Class

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

sub _subclass_method {
    my $method = ( caller(0) )[3];
    die "your should subclass $method\n";
}

=item initialize

Initialize a project.
you should subclass this method, and call this to get the dir with content initialized

=cut

sub initialize {
    my $self = shift;
    my $dir = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );

    dircopy( Shipwright::Util->share_root, $dir );

    # share_root can't keep empty dirs, we have to create them manually
    for (qw/dists scripts t/) {
        mkdir catfile( $dir, $_ );
    }

    # hack for share_root living under blib/
    unlink( catfile( $dir, '.exists' ) );

    return $dir;
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

    unless ( $args{_initialize} || $args{_extra_tests} ) {
        if ( $args{_extra_tests} ) {
            $self->delete( path => "/t/extra" ) if $args{delete};

            $self->log->info( "import extra tests to " . $self->repository );
            Shipwright::Util->run(
                $self->_cmd( import => %args, name => $name ) );
        }
        elsif ( $args{build_script} ) {
            if ( $self->info( path => "/scripts/$name" )
                && not $args{overwrite} )
            {
                $self->log->warn(
"path scripts/$name alreay exists, need to set overwrite arg to overwrite"
                );
            }
            else {
                $self->delete( path =>  "/scripts/$name" ) if $args{delete};

                $self->log->info(
                    "import $args{source}'s scripts to " . $self->repository );
                Shipwright::Util->run(
                    $self->_cmd( import => %args, name => $name ) );
                $self->update_refs;

            }
        }
        else {
            if ( $self->info( path => "/dists/$name" ) && not $args{overwrite} )
            {
                $self->log->warn(
"path dists/$name alreay exists, need to set overwrite arg to overwrite"
                );
            }
            else {
                $self->delete( path =>  "/dists/$name" ) if $args{delete};
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
    Shipwright::Util->run( $self->_cmd( export => %args ) );
}

=item checkout

=cut

sub checkout {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    $self->log->info(
        'export ' . $self->repository . "/$path to $args{target}" );
    Shipwright::Util->run( $self->_cmd( checkout => %args ) );
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
        @dists = $self->dists;
    }

    s{/$}{} for @dists;

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
    my $out = Shipwright::Util->run(
        $self->_cmd( 'cat', path => "/scripts/$name/require.yml" ), 1 );

    my $req = Shipwright::Util::Load( $out ) || {};

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

sub _yml {
    my $self = shift;
    my $path = shift;
    my $yml  = shift;

    my $file = catfile( $self->repository, $path );
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
    my $path  = '/shipwright/order.yml';
    return $self->_yml( $path, $order );
}

=item map

Get or set the map.

=cut

sub map {
    my $self = shift;
    my $map  = shift;

    my $path = '/shipwright/map.yml';
    return $self->_yml( $path, $map );
}

=item source

Get or set the sources map.

=cut

sub source {
    my $self   = shift;
    my $source = shift;
    my $path = '/shipwright/source.yml';
    return $self->_yml( $path, $source );
}

=item flags

Get or set flags.

=cut

sub flags {
    my $self  = shift;
    my $flags = shift;

    my $path = '/shipwright/flags.yml';
    return $self->_yml( $path, $flags );
}

=item version

Get or set version.

=cut

sub version {
    my $self    = shift;
    my $version = shift;

    my $path = '/shipwright/version.yml';
    return $self->_yml( $path, $version );
}

=item ktf

Get or set known failure conditions.

=cut

sub ktf {
    my $self = shift;
    my $ktf  = shift;
    my $path = '/shipwright/known_test_failures.yml';

    return $self->_yml( $path, $ktf );
}

=item refs

Get or set refs

=cut

sub refs {
    my $self = shift;
    my $refs  = shift;
    my $path = '/shipwright/refs.yml';

    return $self->_yml( $path, $refs );
}

=item delete


=cut

sub delete {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    if ( $self->info( path => $path ) ) {
        $self->log->info( "delete " . $self->repository . $path );
        Shipwright::Util->run( $self->_cmd( delete => path => $path ), 1 );
    }
}

=item list


=cut

sub list {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    if ( $self->info( path => $path ) ) {
        my $out = Shipwright::Util->run( $self->_cmd( list => path => $path ) );
        return $out;
    }
}

=item dists


=cut

sub dists {
    my $self = shift;
    my %args = @_;
    my $out  = $self->list( path => '/scripts' );
    return split /\s+/, $out;
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
        return $info;
    }
}

=item requires

Return the hashref of require.yml for a dist.

=cut

sub requires {
    my $self = shift;
    my %args = @_;
    my $name = $args{name};

    return $self->_yml(
        catfile( 'scripts', $name, 'require.yml' ) );
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

        # every valid shipwright repo has '/shipwright' subdir;
        my $info = $self->info( path => '/shipwright' );

        return 1 if $info;
    }
    return;
}

=item update

you should subclass this method, and run this to get the file path with latest version

=cut

sub update {
    my $self = shift;
    my %args = @_;

    croak "need path option" unless $args{path};

    croak "$args{path} seems not shipwright's own file"
      unless -e catfile( Shipwright::Util->share_root,
        $args{path} );

    return $self->_update_file( $args{path},
        catfile( Shipwright::Util->share_root, $args{path} ) );
}

=item test_script

get or set test_script for a project, i.e. /t/test

=cut

sub test_script {
    my $self = shift;
    my %args = @_;

    if ( $args{source} ) {
        $self->_update_file( '/t/test', $args{source} );
    }
    else {
        return $self->cat( path => '/t/test' );
    }
}

=item trim

trim dists

=cut

sub trim {
    my $self = shift;
    my %args = @_;
    my @names_to_trim;

    if ( ref $args{name} ) {
        @names_to_trim = @{ $args{name} };
    }
    else {
        @names_to_trim = $args{name};
    }

    my $order = $self->order;
    my $map = $self->map;
    my $version = $self->version || {};
    my $source  = $self->source  || {};
    my $flags   = $self->flags   || {};

    for my $name (@names_to_trim) {
        $self->delete( path => "/dists/$name" );
        $self->delete( path => "/scripts/$name" );

        # clean order.yml
        @$order = grep { $_ ne $name } @$order;

        # clean map.yml
        for ( keys %$map ) {
            delete $map->{$_} if $map->{$_} eq $name;
        }

        # clean version.yml, source.yml and flags.yml

        for my $hashref ( $source, $flags, $version ) {
            for ( keys %$hashref ) {
                if ( $_ eq $name ) {
                    delete $hashref->{$_};
                    last;
                }
            }
        }

    }
    $self->version($version);
    $self->map($map);
    $self->source($source);
    $self->flags($flags);
    $self->order($order);
    $self->update_refs;
}

=item update_refs

update refs.

we need update this after import and trim

=cut

sub update_refs {
    my $self = shift;
    my $order = $self->order;
    my $refs = {};

    for my $name (@$order) {
        # initialize here, in case we don't have $name entry in $refs
        $refs->{$name} ||= 0;

        my $out = Shipwright::Util->run(
            $self->_cmd( 'cat', path => "/scripts/$name/require.yml" ), 1 );

        my $req = Shipwright::Util::Load($out) || {};

        my @deps;
        if ( $req->{requires} ) {
            @deps = ( keys %{ $req->{requires} }, keys %{ $req->{recommends} },
              keys %{ $req->{build_requires} } );
        }
        else {

            #for back compatbility
            @deps = keys %$req;
        }

        @deps = uniq @deps;

        for (@deps) {
            $refs->{$_}++;
        }
    }

    $self->refs( $refs );
}


*_cmd = *_update_file = *_subclass_method;


=back

=cut

1;

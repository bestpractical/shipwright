package Shipwright::Backend::Base;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile catdir/;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy qw/copy/;
use File::Copy::Recursive qw/dircopy/;
use File::Path;
use List::MoreUtils qw/uniq firstidx/;
use Module::Info;

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

the constructor

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
    confess "your should subclass $method\n";
}

=item initialize

initialize a project
you should subclass this method, and call this to get the dir with content initialized

=cut

sub initialize {
    my $self = shift;
    my $dir =
      tempdir( 'shipwright_backend_base_XXXXXX', CLEANUP => 1, TMPDIR => 1 );

    dircopy( Shipwright::Util->share_root, $dir )
      or confess "copy share_root failed: $!";

    $self->_install_yaml_tiny($dir);
    $self->_install_clean_inc($dir);
    $self->_install_module_build($dir);

    # set proper permissions for yml under /shipwright/
    my $sw_dir = catdir( $dir, 'shipwright' );
    my $sw_dh;
    opendir $sw_dh, $sw_dir or die "can't opendir $sw_dir: $!";
    for my $yml ( grep { /.yml$/ } readdir $sw_dh ) {
        chmod 0644, catfile( $dir, 'shipwright', $yml ); ## no critic
    }
    closedir $sw_dh;

    # share_root can't keep empty dirs, we have to create them manually
    for (qw/scripts t sources/) {
        mkdir catdir( $dir, $_ );
    }

    # hack for share_root living under blib/
    unlink( catfile( $dir, '.exists' ) );

    return $dir;
}

sub _install_module_build {
    my $self = shift;
    my $dir = shift;
    my $module_build_path = catdir( $dir, 'inc', 'Module', );
    mkpath catdir( $module_build_path, 'Build' );
    copy( catdir( Module::Info->new_from_module('Module::Build')->file),
            $module_build_path ) or confess "copy Module/Build.pm failed: $!";
    dircopy(
        catdir(
            Module::Info->new_from_module('Module::Build')->inc_dir, 'Module',
            'Build'
        ),
        catdir( $module_build_path, 'Build' )
      )
      or confess "copy
        Module/Build failed: $!";
}

sub _install_yaml_tiny {
    my $self = shift;
    my $dir = shift;

    my $yaml_tiny_path = catdir( $dir, 'inc', 'YAML' );
    mkpath $yaml_tiny_path;
    copy( Module::Info->new_from_module('YAML::Tiny')->file, $yaml_tiny_path )
      or confess "copy YAML/Tiny.pm failed: $!";
}

sub _install_clean_inc {
    my $self = shift;
    my $dir = shift;
    my $clean_inc_path = catdir( $dir, 'inc', 'Shipwright', 'Util' );
    mkpath $clean_inc_path;
    copy( Module::Info->new_from_module('Shipwright::Util::CleanINC')->file,
        $clean_inc_path )
      or confess "copy Shipwright/Util/CleanINC.pm failed: $!";
}

=item import

import a dist.

=cut

sub import {
    my $self = shift;
    return unless @_;
    my %args = @_;
    my $name = $args{source};
    $name =~ s{.*/}{};

    if ( $self->has_branch_support ) {
        if ( $args{branches} ) {
            $args{as} = '';
        }
        else {
            $args{as} ||= 'vendor';
        }
    }

    unless ( $args{_initialize} || $args{_extra_tests} ) {
        if ( $args{_extra_tests} ) {
            $self->delete( path => "/t/extra" ) if $args{delete};

            $self->log->info( "import extra tests to " . $self->repository );
            for my $cmd ( $self->_cmd( import => %args, name => $name ) ) {
                Shipwright::Util->run($cmd);
            }
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
                $self->delete( path => "/scripts/$name" ) if $args{delete};

                $self->log->info(
                    "import $args{source}'s scripts to " . $self->repository );
                for my $cmd ( $self->_cmd( import => %args, name => $name ) ) {
                    Shipwright::Util->run($cmd);
                }
                $self->update_refs;

            }
        }
        else {
            if ( $self->has_branch_support ) {
                if ( $self->info( path => "/sources/$name/$args{as}" )
                    && not $args{overwrite} )
                {
                    $self->log->warn(
"path sources/$name/$args{as} alreay exists, need to set overwrite arg to overwrite"
                    );
                }
                else {
                    $self->delete( path => "/sources/$name/$args{as}" )
                      if $args{delete};
                    $self->log->info(
                        "import $args{source} to " . $self->repository );
                    $self->_add_to_order($name);

                    my $version = $self->version;
                    $version->{$name}{$args{as}} = $args{version};
                    $self->version($version);

                    my $branches = $self->branches;
                    if ( $args{branches} ) {

                  # mostly this happens when import from another shipwright repo
                        $branches->{$name} = $args{branches};
                        $self->branches($branches);
                    }
                    elsif (
                            $name !~ /^cpan-/ && 
                        !(
                            $branches->{$name} && grep { $args{as} eq $_ }
                            @{ $branches->{$name} }
                        )
                      )
                    {
                        $branches->{$name} =
                          [ @{ $branches->{$name} || [] }, $args{as} ];
                        $self->branches($branches);
                    }

                    for
                      my $cmd ( $self->_cmd( import => %args, name => $name ) )
                    {
                        Shipwright::Util->run($cmd);
                    }
                }
            }
            else {
                if ( $self->info( path => "/dists/$name" )
                    && not $args{overwrite} )
                {
                    $self->log->warn(
"path dists/$name alreay exists, need to set overwrite arg to overwrite"
                    );
                }
                else {
                    $self->delete( path => "/dists/$name" ) if $args{delete};
                    $self->log->info(
                        "import $args{source} to " . $self->repository );
                    $self->_add_to_order($name);

                    my $version = $self->version;
                    $version->{$name} = $args{version};
                    $self->version($version);

                    for
                      my $cmd ( $self->_cmd( import => %args, name => $name ) )
                    {
                        Shipwright::Util->run($cmd);
                    }
                }
            }
        }
    }
    else {
        for my $cmd ( $self->_cmd( import => %args, name => $name ) ) {
            Shipwright::Util->run($cmd);
        }
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
    for my $cmd ( $self->_cmd( export => %args ) ) {
        Shipwright::Util->run($cmd);
    }
}

=item checkout

=cut

sub checkout {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    $self->log->info(
        'export ' . $self->repository . "/$path to $args{target}" );
    for my $cmd ( $self->_cmd( checkout => %args ) ) {
        Shipwright::Util->run($cmd);
    }
}

=item commit

A wrapper around svn's commit command.

=cut

sub commit {
    my $self = shift;
    my %args = @_;
    $self->log->info( 'commit ' . $args{path} );
    for my $cmd ( $self->_cmd( commit => @_ ) ) {
        Shipwright::Util->run( $cmd, 1 );
    }
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

regenerate the dependency order.

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
      or confess $@;
    my $order = $dep->schedule_all();

    $self->order($order);
}

=item graph_deps

Output a dependency graph in graphviz format to stdout

=cut

sub graph_deps {
    my $self = shift;
    my %args = @_;

    $self->log->info( "Outputting a graphviz order for " . $self->repository );

    my @dists = @{ $args{for_dists} || [] };
    unless (@dists) {
        @dists = $self->dists;
    }

    s{/$}{} for @dists;

    my $require = {};

    for my $distname (@dists) {
        $self->_fill_deps( %args, require => $require, name => $distname );
    }

    print 'digraph g {
        graph [ overlap = scale, rankdir= LR ];
        node [ fontsize = "18", shape = record, fontsize = 18 ];
    ';

    for my $dist (@dists) {
        print qq{ "$dist" [shape = record, fontsize = 18, label = "$dist" ];\n};
        for my $dep ( @{ $require->{$dist} } ) {
            print qq{"$dist" -> "$dep";\n};
        }
    }
    print "\n};\n";
}

sub _fill_deps {
    my $self    = shift;
    my %args    = @_;
    my $require = $args{require};
    my $name    = $args{name};

    return if $require->{$name};
    my $out = Shipwright::Util->run(
        $self->_cmd( 'cat', path => "/scripts/$name/require.yml" ), 1 );

    my $req = Shipwright::Util::Load($out) || {};

    if ( $req->{requires} ) {
        for (qw/requires recommends build_requires/) {
            push @{ $require->{$name} }, keys %{ $req->{$_} }
              unless $args{"skip_$_"};
        }
    }
    else {

        #for back compatbility
        push @{ $require->{$name} }, keys %$req;
    }
    @{ $require->{$name} } = uniq @{ $require->{$name} };

    for my $dep ( @{ $require->{$name} } ) {
        next if $require->{$dep};
        $self->_fill_deps( %args, name => $dep );
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

get or set the dependency order.

=cut

sub order {
    my $self  = shift;
    my $order = shift;
    my $path  = '/shipwright/order.yml';
    return $self->_yml( $path, $order );
}

=item map

get or set the map.

=cut

sub map {
    my $self = shift;
    my $map  = shift;

    my $path = '/shipwright/map.yml';
    return $self->_yml( $path, $map );
}

=item source

get or set the sources map.

=cut

sub source {
    my $self   = shift;
    my $source = shift;
    my $path   = '/shipwright/source.yml';
    return $self->_yml( $path, $source );
}

=item flags

get or set flags.

=cut

sub flags {
    my $self  = shift;
    my $flags = shift;

    my $path = '/shipwright/flags.yml';
    return $self->_yml( $path, $flags );
}

=item version

get or set version.

=cut

sub version {
    my $self    = shift;
    my $version = shift;

    my $path = '/shipwright/version.yml';
    return $self->_yml( $path, $version );
}

=item branches

get or set branches.

=cut

sub branches {
    my $self     = shift;
    my $branches = shift;

    if ( $self->has_branch_support ) {
        my $path = '/shipwright/branches.yml';
        return $self->_yml( $path, $branches );
    }

    # no branches support in 1.x
    return;
}

=item ktf

get or set known failure conditions.

=cut

sub ktf {
    my $self = shift;
    my $ktf  = shift;
    my $path = '/shipwright/known_test_failures.yml';

    return $self->_yml( $path, $ktf );
}

=item refs

get or set refs

=cut

sub refs {
    my $self = shift;
    my $refs = shift;
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
        for my $cmd ( $self->_cmd( delete => path => $path ) ) {
            Shipwright::Util->run( $cmd, 1 );
        }
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
        for my $cmd (
            $self->_cmd(
                move     => path => $path,
                new_path => $new_path,
            )
          )
        {
            Shipwright::Util->run($cmd);
        }
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

return the hashref of require.yml for a dist.

=cut

sub requires {
    my $self = shift;
    my %args = @_;
    my $name = $args{name};

    return $self->_yml( catfile( 'scripts', $name, 'require.yml' ) );
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

    if ( $args{path} =~ m{/$} ) {
        # it's a directory
        if ( $args{path} eq '/inc/' && ! $args{source} ) {
            my $dir = tempdir(
                'shipwright_backend_base_XXXXXX',
                CLEANUP => 1,
                TMPDIR  => 1,
            );
            $self->_install_yaml_tiny($dir);
            $self->_install_clean_inc($dir);
            $self->_install_module_build($dir);
            $self->_update_dir( '/inc/', catdir($dir, 'inc') );
        }
        elsif ( $args{source} ) {
            $self->_update_dir( $args{path}, $args{source} );
        }
    }
    else {

        croak "$args{path} seems not shipwright's own file"
          unless -e catfile( Shipwright::Util->share_root, $args{path} );

        return $self->_update_file( $args{path},
            catfile( Shipwright::Util->share_root, $args{path} ) );
    }
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

    my $order   = $self->order;
    my $map     = $self->map;
    my $version = $self->version || {};
    my $source  = $self->source || {};
    my $flags   = $self->flags || {};

    for my $name (@names_to_trim) {
        if ( $self->has_branch_support ) {
            $self->delete( path => "/sources/$name" );
        }
        else {
            $self->delete( path => "/sources/$name" );
        }
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
    my $self  = shift;
    my $order = $self->order;
    my $refs  = {};

    for my $name (@$order) {

        # initialize here, in case we don't have $name entry in $refs
        $refs->{$name} ||= 0;

        my $out = Shipwright::Util->run(
            $self->_cmd( 'cat', path => "/scripts/$name/require.yml" ), 1 );

        my $req = Shipwright::Util::Load($out) || {};

        my @deps;
        if ( $req->{requires} ) {
            @deps = (
                keys %{ $req->{requires} },
                keys %{ $req->{recommends} },
                keys %{ $req->{build_requires} }
            );
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

    $self->refs($refs);
}

=item has_branch_support

return true if has branch support 

=cut

sub has_branch_support {
    my $self = shift;
    return 1 if $self->info( path => '/shipwright/branches.yml' );
    return;
}

*_cmd = *_update_file = *_subclass_method;

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

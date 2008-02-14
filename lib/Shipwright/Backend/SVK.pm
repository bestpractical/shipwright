package Shipwright::Backend::SVK;

use warnings;
use strict;
use Carp;
use File::Spec;
use Shipwright::Util;
use File::Temp qw/tempdir/;
use File::Copy;

# our project's own files will be in //local/test/main
# all the dependance packages will be in //local/test/deps
# the shipwright's stuff will be in //local/test/shipwright

our %REQUIRE_OPTIONS = ( import => [qw/source/] );

use base qw/Class::Accessor::Fast/;
__PACKAGE__->mk_accessors(qw/repository log/);

=head2 new

=cut

sub new {
    my $class = shift;
    my $self  = {@_};

    bless $self, $class;
    $self->log( Log::Log4perl->get_logger( ref $self ) );
    return $self;
}

=head2 initialize

initialize a project

=cut

sub initialize {
    my $self = shift;
    my $dir = tempdir( CLEANUP => 1 );
    for (qw/shipwright dists etc bin scripts t/) {
        mkdir File::Spec->catfile( $dir, $_ );
    }

    my %map = (
        File::Spec->catfile( $dir, 'etc', 'shipwright-script-wrapper' ) =>
          'wrapper',
        File::Spec->catfile( $dir, 'etc', 'shipwright-perl-wrapper' ) =>
          'perl_wrapper',
        File::Spec->catfile( $dir, 'etc', 'shipwright-utility' ) =>
          'installed_utility',
        File::Spec->catfile( $dir, 'etc', 'shipwright-source-bash' ) =>
          'source_bash',
        File::Spec->catfile( $dir, 'etc', 'shipwright-source-tcsh' ) =>
          'source_tcsh',
        File::Spec->catfile( $dir, 'bin', 'shipwright-builder' ) => 'builder',
        File::Spec->catfile( $dir, 'bin', 'shipwright-utility' ) => 'utility',
        File::Spec->catfile( $dir, 't',   'test' )               => 'null',
        File::Spec->catfile( $dir, 'shipwright', 'order.yml' )  => 'null',
        File::Spec->catfile( $dir, 'shipwright', 'map.yml' )    => 'null',
        File::Spec->catfile( $dir, 'shipwright', 'source.yml' ) => 'null',
    );

    for ( keys %map ) {
        open my $fh, '>', $_ or die "can't open file $_: $!";
        print $fh Shipwright::Backend->make_script( $map{$_} );
        close $fh;
    }

    $self->delete;    # clean repository in case it exists
    $self->log->info( 'initialize ' . $self->repository );
    $self->import(
        source      => $dir,
        _initialize => 1,
        comment     => 'created project',
    );
    for (
        'bin/shipwright-builder',      'bin/shipwright-utility',
        'etc/shipwright-perl-wrapper', 'etc/shipwright-script-wrapper',
        't/test',                      'etc/shipwright-utility',
      )
    {
        $self->propset(
            path  => $_,
            type  => 'svn:executable',
            value => '*'
        );
    }
}

=head2 import

import a dist

=cut

sub import {
    my $self = shift;
    return unless @_;
    my %args = @_;
    my $name = $args{source};
    $name =~ s{.*/}{};

    unless ( $args{_initialize} || $args{_extra_tests} ) {
        if ( $args{build_script} ) {
            if ( $self->info("scripts/$name") && not $args{overwrite} ) {
                $self->log->warn(
"path scripts/$name alreay exists, need to set overwrite arg to overwrite"
                );
            }
            else {
                $self->delete("scripts/$name");
                $self->log->info(
                    "import $args{source}'s scripts to " . $self->repository );
                Shipwright::Util->run(
                    $self->_cmd( import => %args, name => $name ) );
            }
        }
        else {
            if ( $self->info("dists/$name") && not $args{overwrite} ) {
                $self->log->warn(
"path dists/$name alreay exists, need to set overwrite arg to overwrite"
                );
            }
            else {
                $self->delete("dists/$name");
                $self->log->info(
                    "import $args{source} to " . $self->repository );
                $self->_add_to_order($name);
                Shipwright::Util->run(
                    $self->_cmd( import => %args, name => $name ) );
            }
        }
    }
    else {
        Shipwright::Util->run( $self->_cmd( import => %args, name => $name ) );
    }
}

=head2 export

export a project, partly or as a whole

=cut

sub export {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    $self->log->info(
        'export ' . $self->repository . "/$path to $args{target}" );
    Shipwright::Util->run( $self->_cmd( checkout => %args ) );
    Shipwright::Util->run( $self->_cmd( checkout => %args, detach => 1 ) );
}

=head2 checkout

a wrapper of checkout cmd of svk
checkout a project, partly or as a whole

=cut

sub checkout {
    my $self = shift;
    my %args = @_;
    my $path = $args{path} || '';
    $self->log->info(
        'export ' . $self->repository . "/$path to $args{target}" );
    Shipwright::Util->run( $self->_cmd( checkout => %args ) );
}

=head2 commit

a wrapper of commit cmd of svk

=cut

sub commit {
    my $self = shift;
    my %args = @_;
    $self->log->info( 'commit ' . $args{path} );

   # have to omit the failure since we will get error if nothing need to commit,
   # which's harmless
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
        if ( $args{detach} ) {
            $cmd = [ 'svk', 'checkout', '-d', $args{target} ];
        }
        else {
            $cmd = [
                'svk',                           'checkout',
                $self->repository . $args{path}, $args{target}
            ];
        }
    }
    elsif ( $type eq 'import' ) {
        if ( $args{_initialize} ) {
            $cmd = [
                'svk',         'import',
                $args{source}, $self->repository,
                '-m',          q{'} . $args{comment} . q{'},
            ];
        }
        elsif ( $args{_extra_tests} ) {
            $cmd = [
                'svk', 'import',
                $args{source}, join( '/', $self->repository, 't', 'extra' ),
                '-m', q{'} . $args{comment} . q{'},
            ];
        }
        else {
            if ( my $script_dir = $args{build_script} ) {
                $cmd = [
                    'svk',       'import',
                    $script_dir, $self->repository . "/scripts/$args{name}/",
                    '-m',        q{'} . $args{comment} . q{'},
                ];
            }
            else {
                $cmd = [
                    'svk',         'import',
                    $args{source}, $self->repository . "/dists/$args{name}",
                    '-m',          q{'} . $args{comment} . q{'},
                ];
            }
        }
    }
    elsif ( $type eq 'commit' ) {
        $cmd =
          [ 'svk', 'commit', '-m', q{'} . $args{comment} . q{'}, $args{path} ];
    }
    elsif ( $type eq 'delete' ) {
        $cmd = [
            'svk', 'delete', '-m', q{'} . 'delete repository' . q{'},
            join '/', $self->repository, $args{path},
        ];
    }
    elsif ( $type eq 'info' ) {
        $cmd = [ 'svk', 'info', join '/', $self->repository, $args{path} ];
    }
    elsif ( $type eq 'propset' ) {
        $cmd = [
            'svk',                                'propset',
            $args{type},                          '-m',
            q{'} . "set prop $args{type}" . q{'}, q{'} . $args{value} . q{'},
            join '/',                             $self->repository,
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

=head2 update_order

regenate order

=cut

sub update_order {
    my $self = shift;
    my %args = @_;

    $self->log->info( "update order for " . $self->repository );

    my @dists = @{ $args{for_dists} || [] };
    unless (@dists) {
        my ($out) = Shipwright::Util->run(
            [ 'svk', 'ls', $self->repository . '/scripts' ] );
        my $sep = $/;
        @dists = split /$sep/, $out;
        chomp @dists;
        s{/$}{} for @dists;
    }

    my $require = {};

    for (@dists) {
        $self->_fill_deps( %args, require => $require, dist => $_ );
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
    my $dist    = $args{dist};

    my ($string) = Shipwright::Util->run(
        [ 'svk', 'cat', $self->repository . "/scripts/$dist/require.yml" ], 1 );
    my $req = Shipwright::Util::Load($string) || {};

    if ( $req->{requires} ) {
        for (qw/requires recommends build_requires/) {
            push @{ $require->{$dist} }, keys %{ $req->{$_} }
              if $args{"keep_$_"};
        }
    }
    else {

        #for back compatbility
        push @{ $require->{$dist} }, keys %$req;
    }

    for my $dep ( @{ $require->{$dist} } ) {
        next if $require->{$dep};
        $self->_fill_deps( %args, dist => $dep );
    }
}

=head2 order

get or set order

=cut

sub order {
    my $self  = shift;
    my $order = shift;
    if ($order) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, 'order.yml' );

        $self->checkout(
            path   => '/shipwright/order.yml',
            target => $file,
        );

        Shipwright::Util::DumpFile( $file, $order );
        $self->commit( path => $file, comment => "set order" );
        $self->checkout( detach => 1, target => $file );
    }
    else {
        my ($out) = Shipwright::Util->run(
            [ 'svk', 'cat', $self->repository . '/shipwright/order.yml' ] );
        return Shipwright::Util::Load($out);
    }
}

=head2 map

get or set map

=cut

sub map {
    my $self = shift;
    my $map  = shift;
    if ($map) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, 'map.yml' );

        $self->checkout(
            path   => '/shipwright/map.yml',
            target => $file,
        );

        Shipwright::Util::DumpFile( $file, $map );
        $self->commit( path => $file, comment => "set map" );
        $self->checkout( detach => 1, target => $file );
    }
    else {
        my ($out) = Shipwright::Util->run(
            [ 'svk', 'cat', $self->repository . '/shipwright/map.yml' ] );
        return Shipwright::Util::Load($out);
    }
}

=head2 source

get or set source

=cut

sub source {
    my $self   = shift;
    my $source = shift;
    if ($source) {
        my $dir = tempdir( CLEANUP => 1 );
        my $file = File::Spec->catfile( $dir, 'source.yml' );

        $self->checkout(
            path   => '/shipwright/source.yml',
            target => $file,
        );

        Shipwright::Util::DumpFile( $file, $source );
        $self->commit( path => $file, comment => "set source" );
        $self->checkout( detach => 1, target => $file );
    }
    else {
        my ($out) = Shipwright::Util->run(
            [ 'svk', 'cat', $self->repository . '/shipwright/source.yml' ] );
        return Shipwright::Util::Load($out);
    }
}

=head2 delete

wrapper of delete cmd of svk

=cut

sub delete {
    my $self = shift;
    my $path = shift || '';
    if ( $self->info($path) ) {
        $self->log->info( "delete " . $self->repository . "/$path" );
        Shipwright::Util->run( $self->_cmd( delete => path => $path ), 1 );
    }
}

=head2 info

wrapper of info cmd of svk

=cut

sub info {
    my $self = shift;
    my $path = shift;
    my ( $info, $err ) =
      Shipwright::Util->run( $self->_cmd( info => path => $path ), 1 );
    $self->log->warn($err) if $err;
    return if $info =~ /not exist/;
    return $info;
}

=head2 propset

wrapper of propset cmd of svk

=cut

sub propset {
    my $self = shift;
    my %args = @_;
    my ( $info, $err ) =
      Shipwright::Util->run( $self->_cmd( propset => %args ) );
    $self->log->warn($err) if $err;
}

=head2 test_script

set test_script for a project, aka. udpate t/test script

=cut

sub test_script {
    my $self   = shift;
    my %args   = @_;
    my $script = $args{source};
    croak 'need source option' unless $script;

    my $dir = tempdir( CLEANUP => 1 );
    my $file = File::Spec->catfile( $dir, 'test' );

    $self->checkout(
        path   => '/t/test',
        target => $file,
    );

    copy( $args{source}, $file );
    $self->commit( path => $file, comment => "update test script" );
    $self->checkout( detach => 1, target => $file );
}

=head2 requires
return hashref to require.yml for a dist
=cut

sub requires {
    my $self = shift;
    my $name = shift;

    my ($string) = Shipwright::Util->run(
        [ 'svk', 'cat', $self->repository . "/scripts/$name/require.yml" ], 1 );
    return Shipwright::Util::Load($string) || {};
}

1;

__END__

=head1 NAME

Shipwright::Backend::SVK - svk backend


=head1 DESCRIPTION


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


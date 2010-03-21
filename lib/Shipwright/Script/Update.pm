package Shipwright::Script::Update;

use strict;
use warnings;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/all follow builder utility inc version only_sources as add_deps delete_deps/
);

use Shipwright;
use File::Spec::Functions qw/catdir/;
use Shipwright::Source;
use Shipwright::Util;
use File::Copy qw/copy move/;
use File::Temp qw/tempdir/;
use Config;

sub options {
    (
        'a|all'         => 'all',
        'follow'        => 'follow',
        'builder'       => 'builder',
        'utility'       => 'utility',
        'inc'           => 'inc',
        'version=s'     => 'version',
        'only-sources'  => 'only_sources',
        'as=s'          => 'as',
        'add-deps=s'    => 'add_deps',
        'delete-deps=s' => 'delete_deps',
    );
}

my ( $shipwright, $map, $source, $branches );

sub run {
    my $self = shift;

    $shipwright = Shipwright->new(
        repository => $self->repository,
        log_level  => $self->log_level,
        log_file   => $self->log_file
    );

    if ( $self->builder ) {
        $shipwright->backend->update( path => '/bin/shipwright-builder' );
    }
    elsif ( $self->utility ) {
        $shipwright->backend->update( path => '/bin/shipwright-utility' );

    }
    elsif ( $self->inc ) {
        $shipwright->backend->update( path => '/inc/' );

    }
    elsif ( $self->add_deps ) {
        my @deps = split /\s*,\s*/, $self->add_deps;
        my $name = shift or confess_or_die 'need name arg';
        my $requires = $shipwright->backend->requires( name => $name ) || {};
        for my $dep ( @deps ) {
            my $new_dep;
            my $version = 0;
            if ( $dep =~ /(.*)=(.*)/ ) {
                $dep = $1;
                $version = $2;
            }

            $new_dep = 1 unless $requires->{requires}{$dep};
            $requires->{requires}{$dep} = { version => $version };
            $shipwright->backend->_yml( "/scripts/$name/require.yml", $requires );

            if ($new_dep) {

                # we need to update refs.yml
                my $refs = $shipwright->backend->refs;
                $refs->{$dep}++;
                $shipwright->backend->refs($refs);
            }
        }
    }
    elsif ( $self->delete_deps ) {
        my @deps = split /\s*,\s*/, $self->delete_deps;
        my $name = shift or confess_or_die 'need name arg';
        my $requires = $shipwright->backend->requires( name => $name ) || {};
        for my $dep ( @deps ) {
            for my $type ( qw/requires build_requires recommends/ ) {
                delete $requires->{$type}{$dep} if $requires->{$type};
            }

            $shipwright->backend->_yml( "/scripts/$name/require.yml", $requires );
            my $refs = $shipwright->backend->refs;
            $refs->{$dep}-- if $refs->{$dep} > 0;
            $shipwright->backend->refs($refs);
        }
    }
    else {
        $map    = $shipwright->backend->map    || {};
        $source = $shipwright->backend->source || {};
        $branches = $shipwright->backend->branches;

        if ( $self->all ) {
            confess_or_die '--all can not be specified with --as or NAME'
              if @_ || $self->as;

            my $dists = $shipwright->backend->order || [];
            for (@$dists) {
                $self->_update($_);
            }
        }
        else {
            my $name = shift;
            confess_or_die "need name arg\n" unless $name;

            # die if the specified branch doesn't exist
            if ( $branches && $self->as ) {
                confess_or_die "$name doesn't have branch "
                  . $self->as
                  . ". please use import cmd instead"
                  unless grep { $_ eq $self->as } @{ $branches->{$name} || [] };
            }

            my $new_source = shift;
            if ($new_source) {
                system(
                        "$0 relocate -r " 
                      . $self->repository
                      . (
                        $self->log_level
                        ? ( " --log-level " . $self->log_level )
                        : ''
                      )
                      . (
                        $self->log_file ? ( " --log-file " . $self->log_file )
                        : ''
                      )
                      . (
                        $self->as ? ( " --as " . $self->as )
                        : ''
                      )
                      . " $name $new_source"
                ) && die "relocate $name to $new_source failed: $!";
                # renew our $source
                $source = $shipwright->backend->source || {};
            }

            my @dists;
            if ( $self->follow ) {
                my (%checked);
                my $find_deps;
                $find_deps = sub {
                    my $name = shift;
                    return if $checked{$name}++;

                    my ($require) =
                      $shipwright->backend->requires( name => $name );
                    for my $type (qw/requires build_requires recommends/) {
                        for ( keys %{ $require->{$type} } ) {
                            $find_deps->($_);
                        }
                    }
                };

                $find_deps->($name);
                @dists = keys %checked;
            }
            else {
                @dists = $name;
            }

            for (@dists) {
                if ( $self->only_sources ) {
                    if ( $_ eq $name ) {
                        $self->_update( $_, $self->version, $self->as );
                    }
                    else {
                        $self->_update($_);
                    }
                }
                else {
                    system(
                            "$0 import -r " 
                          . $self->repository
                          . (
                            $self->log_level
                            ? ( " --log-level " . $self->log_level )
                            : ''
                          )
                          . (
                            $self->log_file
                            ? ( " --log-file " . $self->log_file )
                            : ''
                          )
                          . (
                            $self->as ? ( " --as " . $self->as )
                            : ''
                          )
                          . (
                            $self->version ? ( " --version " . $self->version )
                            : ''
                          )
                          . " --name $_"
                    );
                }
            }
        }
    }
    $self->log->fatal( 'updated with success' );
}

sub _update {
    my $self    = shift;
    my $name    = shift;
    my $version = shift;
    my $as      = shift;
    if ( $source->{$name} ) {
        $shipwright->source(
            Shipwright::Source->new(
                name    => $name,
                source  => $source->{$name}{$as||$branches->{$name}[0]},
                follow  => 0,
                version => $version,
            )
        );
    }
    else {

        # it's a cpan dist
        my $s;

        if ( $name =~ /^cpan-/ ) {
            $s = { reverse %$map }->{$name};
        }
        elsif ( $map->{$name} ) {
            $s    = $name;
            $name = $map->{$name};
        }
        else {
            confess_or_die 'invalid name ' . $name . "\n";
        }

        unless ( $s ) {
            warn "can't find the source name of $name, skipping";
            next;
        }

        $shipwright->source(
            Shipwright::Source->new(
                source  => "cpan:$s",
                follow  => 0,
                version => $version,
            )
        );
    }

    $shipwright->source->run;

    $version = load_yaml_file( $shipwright->source->version_path );

    $shipwright->backend->import(
        source    => catdir( $shipwright->source->directory, $name ),
        comment   => "update $name",
        overwrite => 1,
        version   => $version->{$name},
        as        => $as,
    );
}

1;

__END__

=head1 NAME

Shipwright::Script::Update - Update dist(s) and scripts

=head1 SYNOPSIS

 update --all
 update NAME [NEW_SOURCE_URL] [--follow]
 update --builder
 update --utility

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file
 --version                    : specify the version of the dist
 --all                        : update all dists
 --follow                     : update one dist with all its dependencies
 --builder                    : update bin/shipwright-builder
 --utility                    : update bin/shipwright-utility
 --inc                        : update inc/
 --only-sources               : only update sources, no build scripts
 --as                         : the branch name
 --add-deps                   : add requires deps for a dist e.g. cpan-Foo=0.30,cpan-Bar,cpan-Baz=2.34

=head1 DESCRIPTION

The update command updates one or multiple svk, svn, git or CPAN dists in a
Shipwright repository to the latest version. 
To update other types of sources, you must re-import the new version, using the same name in order to overwrite.

with --only-sources, only sources will be updated, 
while scripts( technically, the stuff below scripts/ ) won't.

The update command can also be used to update a repository's builder or utility
script to the version shipped with the Shipwright dist on your system, by
specifying the C<--builder> or C<--utility> options.

=head1 ALIASES

up

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


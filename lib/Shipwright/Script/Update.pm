package Shipwright::Script::Update;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/all follow builder utility version only_sources as/
);

use Shipwright;
use File::Spec::Functions qw/catdir/;
use Shipwright::Util;
use File::Copy qw/copy move/;
use File::Temp qw/tempdir/;
use Config;
use Hash::Merge;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

sub options {
    (
        'a|all'        => 'all',
        'follow'       => 'follow',
        'builder'      => 'builder',
        'utility'      => 'utility',
        'version=s'    => 'version',
        'only-sources' => 'only_sources',
        'as=s'         => 'as',
    );
}

my ( $shipwright, $map, $source, $branches );

sub run {
    my $self = shift;

    $shipwright = Shipwright->new( repository => $self->repository, );

    if ( $self->builder ) {
        $shipwright->backend->update( path => '/bin/shipwright-builder' );
    }
    elsif ( $self->utility ) {
        $shipwright->backend->update( path => '/bin/shipwright-utility' );

    }
    else {
        $map    = $shipwright->backend->map    || {};
        $source = $shipwright->backend->source || {};
        $branches = $shipwright->backend->branches;

        if ( $self->all ) {
            confess '--all can not be specified with --as or NAME'
              if @_ || $self->as;

            my $dists = $shipwright->backend->order || [];
            for (@$dists) {
                $self->_update($_);
            }
        }
        else {
            my $name = shift;
            confess "need name arg\n" unless $name;

            # die if the specified branch doesn't exist
            if ( $branches && $self->as ) {
                confess "$name doesn't have branch "
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
                          . " --name $_"
                    );
                }
            }
        }
    }

    print "updated with success\n";
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
                source  => $source->{$name},
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
            confess 'invalid name ' . $name . "\n";
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

    $version = Shipwright::Util::LoadFile( $shipwright->source->version_path );

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
 --only-sources               : only update sources, no build scripts
 --as                         : the branch name

=head1 DESCRIPTION

The update command updates one or multiple svk, svn, or CPAN dists in a
Shipwright repository to the latest version. 
To update other types of sources, you must re-import the new version, using the same name in order to overwrite.

with --only-sources, only sources will be updated, 
while scripts( technically, the stuff below scripts/ ) won't.

The update command can also be used to update a repository's builder or utility
script to the version shipped with the Shipwright dist on your system, by
specifying the C<--builder> or C<--utility> options.

=head1 ALIASES

up

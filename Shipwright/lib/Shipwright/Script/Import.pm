package Shipwright::Script::Import;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/repository log_level comment source follow build_script require_yml
      name test_script extra_tests overwrite min_perl_version skip log_file/
);

use Shipwright;
use File::Spec;
use Shipwright::Util;
use File::Copy qw/copy move/;
use File::Temp qw/tempdir/;
use Config;
use Hash::Merge;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

=head2 options
=cut

sub options {
    (
        'r|repository=s'   => 'repository',
        'l|log-level=s'    => 'log_level',
        'log-file=s'       => 'log_file',
        'm|comment=s'      => 'comment',
        's|source=s'       => 'source',
        'name=s'           => 'name',
        'follow=s'         => 'follow',
        'build-script=s'   => 'build_script',
        'require-yml=s'    => 'require_yml',
        'test-script=s'    => 'test_script',
        'extra-tests=s'    => 'extra_tests',
        'overwrite'        => 'overwrite',
        'min-perl-version' => 'min_perl_version',
        'skip=s'           => 'skip',
    );
}

my %imported;

=head2 run
=cut

sub run {
    my $self   = shift;
    my $source = shift;

    $self->source($source) if $source;
    $self->follow(1) unless defined $self->follow;
    $self->skip( { map { $_ => 1 } split /\s*,\s*/, $self->skip || '' } );

    for (qw/repository source/) {
        die "need $_ arg" unless $self->$_();
    }

    if ( $self->name ) {
        if ( $self->name =~ /::/ ) {
            $self->log->warn("we saw '::' in the name, will treat it as '-'");
            my $name = $self->name;
            $name =~ s/::/-/g;
            $self->name($name);
        }
        if ( $self->name !~ /^[-\w]+$/ ) {
            die 'name can only have alphanumeric characters and -';
        }
    }

    my $shipwright = Shipwright->new(
        repository       => $self->repository,
        log_level        => $self->log_level,
        log_file         => $self->log_file,
        source           => $self->source,
        name             => $self->name,
        follow           => $self->follow,
        min_perl_version => $self->min_perl_version,
        skip             => $self->skip,
    );

    if ( $self->source ) {

        unless ( $self->overwrite ) {

            # skip already imported dists
            $shipwright->source->skip(
                Hash::Merge::merge(
                    $self->skip, $shipwright->backend->map || {}
                )
            );
        }

        Shipwright::Util::DumpFile(
            $shipwright->source->map_path,
            $shipwright->backend->map || {},
        );

        $self->source(
            $shipwright->source->run(
                copy => { '__require.yml' => $self->require_yml },
            )
        );

        my ($name) = $self->source =~ m{.*/(.*)$};
        $imported{$name}++;

        my $script_dir = tempdir( CLEANUP => 1 );

        if ( my $script = $self->build_script ) {
            copy( $self->build_script,
                File::Spec->catfile( $script_dir, 'build' ) );
        }
        else {
            $self->generate_build( $self->source, $script_dir, $shipwright );
        }

        if ( $self->follow ) {
            $self->import_req( $self->source, $shipwright );

            move(
                File::Spec->catfile( $self->source, '__require.yml' ),
                File::Spec->catfile( $script_dir,   'require.yml' )
            ) or die "move __require.yml failed: $!";
        }

        $shipwright->backend->import(
            source  => $self->source,
            comment => $self->comment || 'import ' . $self->source,
            overwrite => 1,    # import anyway for the main dist
        );
        $shipwright->backend->import(
            source       => $self->source,
            comment      => 'import scripts for' . $self->source,
            build_script => $script_dir,
            overwrite    => 1,
        );

        # merge new map into map.yml in repo
        my $new_map =
          Shipwright::Util::LoadFile( $shipwright->source->map_path )
          || {};
        $shipwright->backend->map(
            Hash::Merge::merge( $shipwright->backend->map || {}, $new_map ) );

        my $new_url =
          Shipwright::Util::LoadFile( $shipwright->source->url_path )
          || {};
        $shipwright->backend->source(
            Hash::Merge::merge( $shipwright->backend->source || {}, $new_url )
        );
    }

    # import tests
    if ( $self->extra_tests ) {
        $shipwright->backend->import(
            source       => $self->extra_tests,
            comment      => 'import extra tests',
            _extra_tests => 1,
        );
    }

    if ( $self->test_script ) {
        $shipwright->backend->test_script( source => $self->test_script );
    }

}

=head2 import_req

import required dists for a dist

=cut

sub import_req {
    my $self         = shift;
    my $source       = shift;
    my $shipwright   = shift;
    my $require_file = File::Spec->catfile( $source, '__require.yml' );

    my $dir = parent_dir($source);

    my $map_file = File::Spec->catfile( $dir, 'map.yml' );

    if ( -e $require_file ) {
        my $req = Shipwright::Util::LoadFile($require_file);
        my $map = {};

        if ( -e $map_file ) {
            $map = Shipwright::Util::LoadFile($map_file);

        }

        opendir my ($d), $dir;
        my @sources = readdir $d;
        close $d;

        for my $type (qw/requires recommends build_requires/) {
            for my $module ( keys %{ $req->{$type} } ) {
                my $dist = $map->{$module} || $module;
                $dist =~ s/::/-/g;

                unless ( $imported{$dist}++ ) {

                    my ($s) = grep { $_ eq $dist } @sources;
                    unless ($s) {
                        $self->log->warn(
                            "we don't have $dist in source which is for "
                              . $self->source );
                        next;
                    }

                    $s = File::Spec->catfile( $dir, $s );

                    $self->import_req( $s, $shipwright );

                    my $script_dir = tempdir( CLEANUP => 1 );
                    move(
                        File::Spec->catfile( $s,          '__require.yml' ),
                        File::Spec->catfile( $script_dir, 'require.yml' )
                    ) or die "move $s/__require.yml failed: $!";

                    $self->generate_build( $s, $script_dir, $shipwright );

                    $shipwright->backend->import(
                        comment   => 'deps for ' . $source,
                        source    => $s,
                        overwrite => $self->overwrite,
                    );
                    $shipwright->backend->import(
                        source       => $s,
                        comment      => 'import scripts for' . $s,
                        build_script => $script_dir,
                        overwrite    => $self->overwrite,
                    );
                }
            }
        }
    }

}

=head2 generate_build

automatically generate build script if not provided

=cut

sub generate_build {
    my $self       = shift;
    my $source_dir = shift;
    my $script_dir = shift;
    my $shipwright = shift;

    chdir $source_dir;

    my @commands;
    if ( -f 'configure' ) {
        @commands = (
            'configure: ./configure --prefix=%%INSTALL_BASE%%',
            'make: make',
            'install: make install',
            'clean: make clean'
        );
    }
    elsif ( -f 'Build.PL' ) {
        push @commands,
          'configure: %%PERL%% Build.PL --install_base=%%INSTALL_BASE%%';
        push @commands, "make: ./Build";
        push @commands, "test: ./Build test";
        push @commands, "install: ./Build install";

        # ./Build won't work because sometimes the perl path in the shebang line
        # is just a symblic link which can't do things right
        push @commands, "clean: %%PERL%% Build realclean";
    }
    elsif ( -f 'Makefile.PL' ) {
        push @commands,
          'configure: %%PERL%% Makefile.PL INSTALL_BASE=%%INSTALL_BASE%%';
        push @commands, 'make: make';
        push @commands, 'test: make test';
        push @commands, "install: make install";
        push @commands, "clean: make clean";
    }
    else {
        $self->log->warn("I have no idea how to build this distribution");
    }

    open my $fh, '>', File::Spec->catfile( $script_dir, 'build' ) or die $@;
    print $fh $_, "\n" for @commands;
    close $fh;
}

=head2 parent_dir

return parent dir 

=cut

sub parent_dir {
    my $source = shift;
    my @dirs   = File::Spec->splitdir($source);
    pop @dirs;
    return File::Spec->catfile(@dirs);
}

1;

__END__

=head1 NAME

Shipwright::Script::Import - import a source(maybe with a lot of dependences)

=head1 SYNOPSIS

  shipwright import          import a source

 Options:
   --repository(-r)   specify the repository of our project
   --log-level(-l)    specify the log level
   --comment(-m)      specify the comment
   --source(-s)       specify the source path
   --name             specify the source name( only alphanumeric characters and - )
   --build-script     specify the build script
   --require-yml      specify the require.yml
   --follow           follow the dependent chain or not
   --extra-test       specify the extra test source(for --only-test when build)
   --test-script      specify the test script(for --only-test when build)
   --min-perl-version minimal perl version( default is the same as the one
                      which runs this cmd )
   --overwrite        import anyway even if we have deps dists in repo already

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


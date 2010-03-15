package Shipwright;

use warnings;
use strict;
use version; our $VERSION = qv('2.4.8');

use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(qw/backend source build log_level log_file/);

use Shipwright::Logger;
use Shipwright::Util;
use File::Spec::Functions qw/catfile tmpdir/;

# strawberry perl's build make is 'dmake'
$ENV{SHIPWRIGHT_MAKE} ||= $^O =~ /MSWin/ ? 'dmake' : 'make';
$ENV{SHIPWRIGHT_SVK} ||= 'svk';
$ENV{SHIPWRIGHT_SVN} ||= 'svn';
$ENV{SHIPWRIGHT_GIT} ||= 'git';
$ENV{SHIPWRIGHT_LWP_TIMEOUT} ||= 1200;

$ENV{PERL_MM_USE_DEFAULT} = 1; # always true

# FTP_PASSIVE is true by default,
# since many sites use this nowadays.
unless ( defined $ENV{FTP_PASSIVE} ) {
    $ENV{FTP_PASSIVE} = 1;
}

sub new {
    my $class = shift;

    my %args = (
        log_level  => undef,
        log_file   => undef,
        repository => undef,
        source     => undef,
        @_
    );
    $args{log_level} = uc $args{log_level} || 'FATAL';

    $args{log_file} = '-' unless $args{log_file};

    my $self = {
        log_level => $args{log_level},
        log_file  => $args{log_file},
    };

    bless $self, $class;

    Shipwright::Logger->new($self);

    if ( $args{repository} ) {
        require Shipwright::Backend;
        $self->backend( Shipwright::Backend->new(%args) );
    }

    if ( $args{source} ) {
        require Shipwright::Source;
        $self->source( Shipwright::Source->new(%args) );
    }

    return $self;
}

1;

__END__

=head1 NAME

Shipwright - Best Practical Builder

=head1 SYNOPSIS

    use Shipwright;

=head1 DESCRIPTION

=head2 Why use Shipwright?

Shipwright is a tool to help you bundle your software.

Most software packages depend on other bits of software in order to avoid code
repetition and repeating work that's already been done. This can result in pain
and suffering when attempting to install the software, due to having to
untangle the maze of dependencies. First, non-CPAN dependencies must be found
and installed. Then, CPAN:: or CPANPLUS:: can be used to install all
dependencies available on CPAN with minimal pain.

While this works, it has some drawbacks, especially for large projects which
have many dependencies. Installation can take many iterations of trying to
install from CPAN and then stopping to install other non-CPAN dependencies that
the CPAN packages depend on. For example, SVK requires the non-CPAN packages
subversion and swig. In the end, installing large projects with many
dependencies is not very friendly for users, especially since dependencies may
change their functionality and break builds with untested versions.

Enter Shipwright, a tool to help you bundle your software with all of its
dependencies, regardless of whether they are CPAN modules or non-Perl modules
from elsewhere. Shipwright makes it easy to build and install a bundle of your
software, usually with just a single command:

$ ./bin/shipwright-builder

As a general note when reading this and other Shipwright documentation: we
will often call a piece of software that your software depends on and is
distributed elsewhere a I<dist>, short for distribution. This and other
Shipwright terminology are defined in L<Shipwright::Manual::Glossary>.

=head2 Introduction

If this is your first time using Shipwright, L<Shipwright::Manual::Tutorial> is
probably a better place to start.

=head2 Design

The idea of Shipwright is simple:

   raw material                   shipwright factory
---------------------           ------------------------
|  all the separate |  import   |  internal shipwright |  build
|  dist sources     |  =====>   |  repository          |  ====>
---------------------           ------------------------

     vessel (final product)
----------------------------------------------
| all packages installed with smart wrappers |
----------------------------------------------

There are two main commands in shipwright: import and build, which can be
invoked like this:

$ shipwright import ...

$ check out your repository and cd there
$ ./shipwright-builder ...

=head2 What's in a Shipwright repository or vessel

=head3 repository after initialization

After initializing a project, the files in the repository are:

bin/
     # used for building, installing and testing
     shipwright-builder

    # a utility for doing things such as updating the build order
     shipwright-utility

etc/
    # wrapper for installed bin files, mainly for optimizing the environment
     shipwright-script-wrapper

    # wrapper for installed perl scripts
    shipwright-perl-wrapper

    # source files you can `source', for tcsh and bash, respectively.
    # both will be installed to tools/
    shipwright-source-tcsh, shipwright-source-bash

    # utility which will be installed to tools/
    shipwright-utility

sources/      # all the sources of your dists live here

scripts/    # all the build scripts and dependency hints live here

shipwright/
    # the actual build order
    order.yml
    # non-cpan dists' name => url map
    source.yml
    # cpan dists' module => name map
    map.yml

t/
    # will run this if with --only-test when build
    test

=head3 repository after import

After importing, say cpan:Acme::Hello, both the sources and scripts directories
will have a `cpan-Acme-Hello' directory.

Under scripts/cpan-Acme-Hello there are two files: 'build' and 'require.yml'.

=head4 build

configure: %%PERL%% Build.PL --install_base=%%INSTALL_BASE%%
make: %%PERL%% Build
test: %%PERL%% Build test
install: %%PERL%% Build install
clean: %%PERL%% Build realclean

Each line is of `type: command' format, and the command is executed line by
line (which is also true for t/test).

See L<Shipwright::Manual::CustomizeBuild> for more information on
customizing the build process for dists.

=head4 require.yml

build_requires: {}

conflicts: {}

recommends:
  cpan-Locale-Maketext-Lexicon: 
    version: 0.15
requires: {}

This file details the hints needed in order for Shipwright to create the
right build order.

=head4 vessel

After the source repository is built, we have a new directory structure
which we call a I<vessel>.

Normally, the vessel contains bin/, bin-wrapper/, etc/, tools/ and lib/
directories. One thing to note is that files below bin/ are for you to run,
while the files below bin-wrapper/ are not. The bin/ directory contains links
to a wrapper around the files in bin-wrapped/, and these programs will only
work correctly if run through the wrapper.

=head2 METHODS

=head3 new PARAMHASH

This class method instantiates a new Shipwright object, which initializes
all Shipwright components (if possible).

=head4 Arguments

general part:

    repository: specify backend's path, e.g. svk:/t/test
    log_level: specify log level, default is FATAL
    log_file: specify log file, default is append to screen

source part:

    source: the source we need to import
    name: source's name
    follow: follow dependency chain or not, default is true
    min_perl_version: minimal required perl version,
             default is the same as the perl which is running shipwright
    skip: hashref where the keys are the skipped modules when importing,
          default is undefined
    version: source's version, default is undefined

build part:

    perl: the path of the perl that runs the commands in scripts/foo/build(.pl),
          default is $^X, the one that is running shipwright
    skip: hashref where the keys are the skipped dists when install,
          default is undefined
    skip_test: skip test or not, default is false
    install_base: install base path, default is a temp directory
    force: force install even if tests fail, default is false
    only_test: don't install, just test, (used for previously installed dists),
                default is false
    flags: flags for building, default is { default => 1 }
    branches: branches build should use

=head1 SEE ALSO

L<Shipwright::Manual>

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

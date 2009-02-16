use strict;
use warnings;

use Test::More tests => 1;

use Shipwright::Util;
use File::Spec::Functions qw/catfile/;
my $share_root = Shipwright::Util->share_root;
my $builder = catfile( $share_root, 'bin', 'shipwright-builder' );
my $help = <<'EOF';
run: ./bin/shipwright-builder

options: 

help: print this usage

install-base: where we will install
    defaults: a temp dir below your system's tmp
    e.g. --install-base /home/local/mydist

name: the name of the project. used to create a better named dir if
    install_base is not supplied
    e.g. --name mydist

perl: which perl to use for the to be installed dists
    defaults: if we have perl in the source, it will use that one
              otherwise, it will use the one which runs this builder script
    e.g. --perl /usr/bin/perl

skip: dists we don't want to install, comma-separated
    e.g. --skip perl,Module-Build

only:  dists we want to install only, comma-separated
    e.g. --only perl,Module-Build

flags: set flags we need, comma-separated
    e.g.  --flags mysql,standalone

skip-test: skip all the tests

skip-test-except-final: skip all the tests except the final dist

force: if tests fail, install anyway

only-test: test for the installed dists
    it's used to be sure everything is ok after we install with success,
    need to specify --install-base if nothing find in __install_base.

clean: clean the source

noclean: don't clean before build

with: don't build the dist of the name in repo, use the one specified here instead.
    e.g. --with svn=dir:/home/foo/svn
    'svn' is the dist name, 'dir:/home/foo/svn' is its source, with the format of Shipwright::Source

make: specify the path of your make command, default is 'make'.
    e.g. --make /usr/bin/make

branches: specify the branch you want to build.
    e.g. --branches Foo,trunk,Bar,2.0

EOF

is( `$^X $builder --help`, $help, 'usage string' );


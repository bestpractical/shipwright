use strict;
use warnings;

use Test::More tests => 64;

use Shipwright;
use Shipwright::Test;

my $sw = Shipwright::Test->shipwright_bin;

Shipwright::Test->init;

SKIP: {
    skip "no svn found", Test::More->builder->expected_tests / 2
      unless has_svn();

    my $repo = 'svn:' . create_svn_repo() . '/hello';

    start_test($repo);
}

SKIP: {
    skip "no svk and svnadmin found", Test::More->builder->expected_tests / 2,
      unless has_svk();

    create_svk_repo();

    my $repo = 'svk://__shipwright/hello';
    start_test($repo);

}

sub start_test {
    my $repo = shift;

    # test create
    my @cmds = (

        # create hello repo
        [ [ 'create', ], qr/created with success/, "create $repo" ],

        # non exist cmd
        [
            [ 'obra', ],
            undef, undef,
            qr/Command not recognized/,
            "non exist cmd",
        ],

        # list cmd
        [ [ 'list', ], '', "list null $repo" ],
        [
            [ 'list', '--name', 'foo' ],
            qr/foo doesn't exist/,
            "list non exist name $repo"
        ],

        # import cmd
        [
            [ 'import', ],
            undef, undef,
            qr/need source arg/,
            'import without --source ...'
        ],
        [
            [ 'import', '--source' ],
            undef,
            undef,
            qr/source requires an argument/,
            'import with --source but no value'
        ],
        [
            [ 'import', '--source', 'foo' ],
            undef,
            undef,
            qr/invalid source: foo/,
            'import with invalid source'
        ],
        [
            [ 'import', 'foo' ],
            undef,
            undef,
            qr/invalid source: foo/,
            'import with invalid source'
        ],

        [
            [ 'import', 'file:t/hello/Acme-Hello-0.03.tar.gz', '--follow', 0 ],
            qr/imported with success/,
            'import tar.gz file',
        ],

        # here we has a dist named Acme-Hello
        [
            [ 'list', ],
            qr{Acme-Hello:\s+
        version:\s+0\.03\s+
        from:\s+\Qfile:t/hello/Acme-Hello-0.03.tar.gz\E}mx,
            'list the repo'
        ],

        # rename cmd
        [
            [ 'rename', '--name', 'Acme-Hello', '--new-name', 'foo' ],
            qr/renamed Acme-Hello to foo with success/
        ],

        # now Acme-Hello is renamed to foo
        [
            [ 'list', ],
            qr{foo:\s+
        version:\s+0\.03\s+
        from:\s+\Qfile:t/hello/Acme-Hello-0.03.tar.gz\E}mx,
            'list the repo'
        ],

        # invalid rename cmds
        [
            [ 'rename', '--name', 'foo', '--new-name' ],
            undef, undef, qr/new-name requires an argument/
        ],
        [ [ 'rename', '--name' ], undef, undef, qr/name requires an argument/ ],
        [
            [ 'rename', ],
            undef, undef,
            qr/need name arg/,
            "rename without name arg"
        ],
        [
            [ 'rename', '--name', 'foo' ],
            undef,
            undef,
            qr/need new-name arg/,
            "rename without new-name arg"
        ],
        [
            [ 'rename', '--name', 'Acme-Hello', '--new-name', '@' ],
            undef, undef,
            qr/invalid new-name: @/,
            'rename with invalid new-name'
        ],
        [
            [ 'rename', '--name', 'NonExist', '--new-name', 'foo' ],
            undef, undef,
            qr/no such dist: NonExist/,
            'rename nonexist dist'
        ],

        # delete cmd
        [
            [ 'delete', '--name', 'foo' ],
            qr/deleted foo with success/,
            'deleted foo'
        ],

        # we don't have foo dist any more
        [
            [ 'list', '--name', 'foo' ], qr/foo doesn't exist/, "foo is deleted"
        ],

        # import dists/dir_configure
        [
            [ 'import', 'dir:t/dists/dir_configure', '--version', 3.14 ],
            qr/imported with success/,
            'imported dists_dir_configure',
        ],
        [
            [ 'ls', '--name', 'dir_configure' ],

            qr{dir_configure:\s+ 
              version:\s+3\.14\s+
              from:\s+ directory:t/dists/dir_configure}mx,
            'list dir_configure, --version arg is works too',
        ],

        # import dists/tgz_build.tar.gz
        [
            [ 'import', 'file:t/dists/tgz_build.tar.gz', '--version', 2.72, 
        '--follow', 0 ],
            qr/imported with success/,
            'imported tgz_build',
        ],
        [
            [ 'ls', '--name', 'tgz_build' ],
            qr{tgz_build:\s+ 
              version:\s+2\.72\s+
              from:\s+ file:t/dists/tgz_build.tar.gz}mx,
            'list tgz_build, --version arg works too',
        ],

        # import dists/tbz_make.tar.bz
        [
            [ 'import', 'file:t/dists/tbz_make.tar.bz2', '--follow', 0 ],
            qr/imported with success/,
            'imported tbz_make',
        ],
        [
            [ 'ls', '--name', 'tbz_make' ],
            qr{tbz_make:\s+ 
              version:\s+
              from:\s+ file:t/dists/tbz_make.tar.bz2}mx,
            'list tgz_make',
        ],

        # set flags dir_configure to 'configure'
        [
            [ 'flags', '--name', 'dir_configure', ],
            qr/flags of dir_configure is \*nothing\*/,
            'default is no flags',
        ],
        [
            [ 'flags', '--name', 'dir_configure', '--set', 'configure,foo', ],
qr/set flags with success\s+flags of dir_configure is configure, foo/,
            'set flags with success',
        ],
        [
            [ 'flags', 'dir_configure', '--add', 'bar', ],
qr/set flags with success\s+flags of dir_configure is bar, configure, foo/,
            'add flags to dir_configure',
        ],
        [
            [ 'flags', 'dir_configure', '--del', 'foo,bar', ],
            qr/set flags with success\s+flags of dir_configure is configure/,
            'delete flags to dir_configure',
        ],
        [
            [ 'flags', 'tgz_build', '--set', 'build' ],
            qr/set flags with success\s+flags of tgz_build is build/,
            'set flags to tgz_build',
        ],
        [
            [ 'flags', 'man1', '--set', 'build', '--mandatary' ],
qr/set mandatary flags with success\s+mandatary flags of man1 is build/,
            'set mandatary flags to man1',
        ],
    );

    for my $item (@cmds) {
        my $cmd = shift @{ $item->[0] };
        test_cmd(
            $repo,
            [ $sw, $cmd, '-r', $repo, @{ $item->[0] }, ],
            @$item[ 1 .. $#$item ],
        );
    }
}


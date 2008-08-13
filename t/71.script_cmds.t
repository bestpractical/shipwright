use strict;
use warnings;

use Test::More tests => 112;

use Shipwright;
use Shipwright::Test;

my $sw = Shipwright::Test->shipwright_bin;

Shipwright::Test->init;

my $repo = 'fs:' . create_fs_repo();
start_test($repo);

SKIP: {
    skip "no svn found", 39 unless has_svn();

    my $repo = 'svn:' . create_svn_repo() . '/hello';

    my $source = create_svn_repo() . '/foo';    # svn source we'll import

    Shipwright::Util->run(
        [ 'svn', 'import', '-m', q{''}, 't/dists/version1', $source ] );

    my $update_cmd = [
        'svn', 'import', '-m', q{''}, 't/dists/version2', $source . '/version2'
    ];
    start_test( $repo, "svn:$source", $update_cmd );
}

SKIP: {
    skip "no svk and svnadmin found", 39 unless has_svk();

    create_svk_repo();

    my $repo   = 'svk://__shipwright/hello';
    my $source = '//foo';
    Shipwright::Util->run(
        [ 'svk', 'import', '-m', q{''}, 't/dists/version1', $source ] );

    start_test( $repo, "svk:$source" );

}

sub start_test {
    my $repo       = shift;
    my $source     = shift;    # the svn or svk dist source
    my $update_cmd = shift;

    # test create
    my @cmds = (

        # create hello repo
        [ ['create'], qr/created with success/, "create $repo" ],

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
            [ 'list', 'foo' ],
            qr/foo doesn't exist/,
            "list non exist name $repo"
        ],

        # import cmd
        [
            [ 'import', ],
            undef, undef,
            qr/need source arg/,
            'import without source ...'
        ],
        [
            [ 'import', 'foo' ],
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
            [ 'import', 'file:t/hello/Acme-Hello-0.03.tar.gz', '--no-follow' ],
            qr/imported with success/,
            'import tar.gz file',
        ],

        # here we has a dist named Acme-Hello
        [
            [ 'list', ],
            qr{Acme-Hello:\s+
        version:\s+0\.03\s+
        from:\s+\Qfile:t/hello/Acme-Hello-0.03.tar.gz\E\s+
        references:\s+0\s+
            }mx,
            'list the repo'
        ],

        # rename cmd
        [
            [ 'rename', 'Acme-Hello', 'foo' ],
            qr/renamed Acme-Hello to foo with success/
        ],

        # now Acme-Hello is renamed to foo
        [
            [ 'list', ],
            qr{foo:\s+
        version:\s+0\.03\s+
        from:\s+\Qfile:t/hello/Acme-Hello-0.03.tar.gz\E\s+
        references:\s+0\s+
            }mx,
            'list the repo'
        ],

        # invalid rename cmds
        [ [ 'rename', 'foo' ], undef, undef, qr/need new-name arg/ ],
        [
            ['rename'], undef,
            undef,      qr/need name arg/,
            "rename without name arg"
        ],
        [
            [ 'rename', 'foo' ],
            undef, undef,
            qr/need new-name arg/,
            "rename without new-name arg"
        ],
        [
            [ 'rename', 'Acme-Hello', '@' ],
            undef,
            undef,
            qr/invalid new-name: @/,
            'rename with invalid new-name'
        ],
        [
            [ 'rename', 'NonExist', 'foo' ],
            undef,
            undef,
            qr/no such dist: NonExist/,
            'rename nonexist dist'
        ],

        # delete cmd
        [ [ 'delete', 'foo' ], qr/deleted foo with success/, 'deleted foo' ],

        # we don't have foo dist any more
        [ [ 'list', 'foo' ], qr/foo doesn't exist/, "foo is deleted" ],

        # import dists/dir_configure
        [
            [ 'import', 'dir:t/dists/dir_configure', '--version', 3.14 ],
            qr/imported with success/,
            'imported dists_dir_configure',
        ],
        [
            [ 'ls', 'dir_configure' ],

            qr{dir_configure:\s+ 
              version:\s+3\.14\s+
              from:\s+\Qdirectory:t/dists/dir_configure\E\s+
              references:\s+0\s+
            }mx,
            'list dir_configure, --version arg works too',
        ],

        # import dists/tgz_build.tar.gz
        [
            [
                'import',    'file:t/dists/tgz_build.tar.gz',
                '--version', 2.72,
                '--no-follow',
            ],
            qr/imported with success/,
            'imported tgz_build',
        ],
        [
            [ 'ls', 'tgz_build' ],
            qr{tgz_build:\s+ 
              version:\s+2\.72\s+
              from:\s+\Qfile:t/dists/tgz_build.tar.gz\E\s+
              references:\s+0\s+
            }mx,
            'list tgz_build, --version arg works too',
        ],

        # import dists/tbz_make.tar.bz
        [
            [ 'import', 'file:t/dists/tbz_make.tar.bz2', '--no-follow' ],
            qr/imported with success/,
            'imported tbz_make',
        ],
        [
            [ 'ls', 'tbz_make' ],
            qr{tbz_make:\s+ 
              version:\s+
              from:\s+\Qfile:t/dists/tbz_make.tar.bz2\E\s+
              references:\s+0\s+
            }mx,
            'list tgz_make',
        ],

        # set flags dir_configure to 'configure'
        [
            [ 'flags', 'dir_configure', ],
            qr/flags of dir_configure is \*nothing\*/,
            'default is no flags',
        ],
        [
            [ 'flags', 'dir_configure', '--set', 'configure,foo', ],
qr/set flags with success\s+flags of dir_configure is configure, foo/,
            'set flags with success',
        ],
        [
            [ 'flags', 'dir_configure', '--add', 'bar', ],
qr/set flags with success\s+flags of dir_configure is bar, configure, foo/,
            'add flags to dir_configure',
        ],
        [
            [ 'flags', 'dir_configure', '--delete', 'foo,bar', ],
            qr/set flags with success\s+flags of dir_configure is configure/,
            'delete flags to dir_configure',
        ],
        [
            [ 'flags', 'tgz_build', '--set', 'build' ],
            qr/set flags with success\s+flags of tgz_build is build/,
            'set flags to tgz_build',
        ],
        [
            [ 'flags', 'man1', '--set', 'build', '--mandatory' ],
qr/set mandatory flags with success\s+mandatory flags of man1 is build/,
            'set mandatory flag man1',
        ],
        [
            ['build'],
            qr/run, run, Build\.PL.*run, run, Makefile\.PL/ms,
            'Build.PL and Makefile.PL are run',
        ],
        [
            [ 'build', '--flags', 'configure' ],
            qr/run, run, configure/,
            'configure is run',
        ],
        [
            [ 'update', '--builder' ],
            qr/updated with success/,
            "updated builder",
        ],
        [
            [ 'update', '--utility' ],
            qr/updated with success/,
            "updated utility",
        ],

        $source
        ? (

            # import an svn or svk dist named foo
            [
                [ 'import', $source ],
                qr/imported with success/,
                "imported $source",
            ],
            [
                [ 'list', 'foo' ],
                $update_cmd
                ? qr/version:\s+1\s+/
                : qr/version:\s+55\s+/m, # the magic number is from practice ;)
                'list foo, version seems ok',
            ],
            $update_cmd,    # if the source dist is svk, $update_cmd is undef
            [
                [ 'list', 'foo', '--with-latest-version' ],
                $update_cmd
                ? qr/latest_version:\s+([^1]|\d{2,})\s+/
                : qr/latest_version:\s+(?!55)\d+\s+/,
                'list foo, latest version seems ok',
            ],

            # update cmd
            [ [ 'update', 'foo' ], qr/updated with success/, "updated foo", ],
            [
                [ 'list', 'foo' ],
                $update_cmd
                ? qr/version:\s+([^1]|\d{2,})\s+/
                : qr/version:\s+(?!49)\d+\s+/,
                'list foo, update cmd seems ok',
            ],
          )
        : (),
    );

    for my $item (@cmds) {
        next unless $item;    # update_cmd can be undef

        if ( ref $item->[0] eq 'ARRAY' ) {
            my $cmd = shift @{ $item->[0] };
            test_cmd(
                $repo,
                [ $sw, $cmd, '-r', $repo, @{ $item->[0] }, ],
                @$item[ 1 .. $#$item ],
            );
        }
        else {

            # for the update_cmd
            Shipwright::Util->run( $item, 1 );
        }
    }
}


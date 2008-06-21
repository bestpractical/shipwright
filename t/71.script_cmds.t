use strict;
use warnings;

use Test::More tests => 40;

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
        [ [ 'create', '-r', $repo ], qr/created with success/, "create $repo" ],

        # test non exist cmd
        [
            [ 'obra', '-r', $repo ],
            undef,
            undef,
            qr/Command not recognized/,
            "non exist cmd",
        ],

        # test list
        [ [ 'list', '-r', $repo ], '', "list null $repo" ],
        [
            [ 'list', '-r', $repo, '--name', 'foo' ],
            qr/foo doesn't exist/,
            "list non exist name $repo"
        ],

        # test import
        [
            [ 'import', '-r', $repo ],
            undef,
            undef,
            qr/need source arg/,
            'import without --source ...'
        ],
        [
            [ 'import', '-r', $repo, '--source' ],
            undef,
            undef,
            qr/source requires an argument/,
            'import with --source but no value'
        ],
        [
            [ 'import', '-r', $repo, '--source', 'foo' ],
            undef, undef,
            qr/invalid source: foo/,
            'import with invalid source'
        ],
        [
            [ 'import', '-r', $repo, 'foo' ],
            undef,
            undef,
            qr/invalid source: foo/,
            'import with invalid source'
        ],

        [
            [
                'import', '-r', $repo, 'file:t/hello/Acme-Hello-0.03.tar.gz',
                '--follow', 0
            ],
            qr/imported with success/,
            'import tar.gz file',
        ],
        [
            [ 'list', '-r', $repo, ],
            qr{Acme-Hello:\s+
        version:\s+0\.03\s+
        from:\s+\Qfile:t/hello/Acme-Hello-0.03.tar.gz\E}mx,
            'list the repo'
        ],

        # test rename
        [
            [
                'rename',     '-r',         $repo, '--name',
                'Acme-Hello', '--new-name', 'foo'
            ],
            qr/renamed Acme-Hello to foo with success/
        ],

        [
            [ 'list', '-r', $repo, ],
            qr{foo:\s+
        version:\s+0\.03\s+
        from:\s+\Qfile:t/hello/Acme-Hello-0.03.tar.gz\E}mx,
            'list the repo'
        ],

        [
            [ 'rename', '-r', $repo, '--name', 'foo', '--new-name' ],
            undef, undef, qr/new-name requires an argument/
        ],
        [
            [ 'rename', '-r', $repo, '--name' ],
            undef, undef, qr/name requires an argument/
        ],
        [
            [ 'rename', '-r', $repo, ],
            undef,
            undef,
            qr/need name arg/,
            "rename without name arg"
        ],
        [
            [ 'rename', '-r', $repo, '--name', 'foo' ],
            undef, undef,
            qr/need new-name arg/,
            "rename without new-name arg"
        ],
        [
            [
                'rename', '-r', $repo, '--name', 'Acme-Hello', '--new-name', '@'
            ],
            undef, undef,
            qr/invalid new-name: @/,
            'rename with invalid new-name'
        ],
        [
            [
                'rename', '-r', $repo, '--name', 'NonExist', '--new-name', 'foo'
            ],
            undef, undef,
            qr/no such dist: NonExist/,
            'rename nonexist dist'
        ],

        # now the dist is renamed to 'foo'
        [
            [ 'delete', '-r', $repo, '--name', 'foo' ],
            qr/deleted foo with success/,
            'deleted foo'
        ],
        [
            [ 'list', '-r', $repo, '--name', 'foo' ],
            qr/foo doesn't exist/,
            "foo is deleted"
        ],
    );

    for my $item (@cmds) {
        test_cmd( $repo, [ $sw, @{ $item->[0] } ], @$item[ 1 .. $#$item ] );
    }
}


use strict;
use warnings;

use Test::More tests => 8;

use Shipwright;
use Shipwright::Test;

my $sw = Shipwright::Test->shipwright_bin;

Shipwright::Test->init;

SKIP: {
    skip "no svn found", 4
      unless has_svn();

    my $repo = 'svn:' . create_svn_repo() . '/hello';

    start_test($repo);
}

SKIP: {
    skip "no svk and svnadmin found", 4
      unless has_svk();

    create_svk_repo();

    my $repo = 'svk://__shipwright/hello';
    start_test($repo);

}

sub start_test {
    my $repo = shift;
    test_cmd(
        $repo,
        [ $sw, 'create', '-r', $repo ],
        qr/created with success/,
        "create $repo"
    );
    test_cmd( $repo, [ $sw, 'list', '-r', $repo ], '', "list null $repo" );
    test_cmd(
        $repo,
        [ $sw, 'list', '-r', $repo, '--name', 'foo' ],
        qr/foo doesn't exist/,
        "list non exist name $repo"
    );
    test_cmd( $repo, [ $sw, 'import', '-r', $repo ], '', "list null $repo" );
}


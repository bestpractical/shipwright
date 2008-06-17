use strict;
use warnings;

use Test::More tests => 2;

use Shipwright;
use Shipwright::Test qw/has_svn has_svk create_svn_repo create_svk_repo devel_cover_enabled/;

my $sw = Shipwright::Test->shipwright_bin;

Shipwright::Test->init;

SKIP: {
    skip "no svn found", 1
      unless has_svn();

    my $repo = create_svn_repo() . '/hello';

    my $cmd = [ $sw, 'create', '-r', "svn:$repo" ];
    unshift @$cmd, $^X, '-MDevel::Cover' if devel_cover_enabled;
    my $out = Shipwright::Util->run( $cmd );
    like( $out, qr/created with success/, "shipwright create -r 'svn:$repo'");
}

SKIP: {
    skip "no svk and svnadmin found", 1
      unless has_svk();

    create_svk_repo();

    my $repo = '//__shipwright/hello';

    my $cmd = [ $sw, 'create', '-r', "svn:$repo" ];
    unshift @$cmd, $^X, '-MDevel::Cover' if devel_cover_enabled;
    my $out = Shipwright::Util->run( [ $sw, 'create', '-r', "svk:$repo"] );
    like( $out, qr/created with success/, "shipwright create -r 'svk:$repo'");
}

use strict;
use warnings;

use Test::More tests => 2;

use Shipwright;
use Shipwright::Test;

my $sw = Shipwright::Test->shipwright_bin;

Shipwright::Test->init;

SKIP: {
    skip "no svn found", 1
      unless has_svn();

    my $repo = create_svn_repo() . '/hello';

    test_create( "svn:$repo" );
}

SKIP: {
    skip "no svk and svnadmin found", 1
      unless has_svk();

    create_svk_repo();

    my $repo = '//__shipwright/hello';

    test_create( "svk:$repo" );
}

my @cover_prefix = ( $^X, '-MDevel::Cover' );

sub test_create {
    my $repo = shift;
    my $cmd = [ $sw, 'create', '-r', "$repo" ];
    unshift @$cmd, @cover_prefix if devel_cover_enabled;
    my $out = Shipwright::Util->run( $cmd );
    like( $out, qr/created with success/, "shipwright create -r 'svn:$repo'");
}


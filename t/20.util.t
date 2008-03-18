use strict;
use warnings;

use Test::More tests => 2;

use Shipwright::Util;
use File::Spec;
use Cwd;

my $cwd = getcwd;
my ( $shipwright_root, $share_root );

if ( grep { m{blib/lib} } @INC ) {

    # found blib/lib, so we're probably in `make test` or something like that.
    $shipwright_root = File::Spec->catfile( $cwd, 'blib', 'lib' );
    $share_root =
      File::Spec->catfile( $cwd, 'blib', 'lib', 'auto', 'Shipwright' );
}
else {
    $shipwright_root = File::Spec->catfile( $cwd, 'lib' );
    $share_root      = File::Spec->catfile( $cwd, 'share' );
}

is(
    $shipwright_root,
    Shipwright::Util->shipwright_root,
    'shipwright_root works',
);
is( $share_root, Shipwright::Util->share_root, 'share_root works' );


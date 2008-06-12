use strict;
use warnings;

use Test::More tests => 7;

use Shipwright::Test;
use Shipwright::Util;
use File::Spec;
use File::Temp qw/tempfile/;
use Cwd;

Shipwright::Test->init;

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

my ($out) = Shipwright::Util->run( [ 'ls', 'lib' ] );
like( $out, qr/Shipwright/, 'test run sub' );

my $hashref = { foo => 'bar' };
my $string = <<EOF;
--- 
foo: bar
EOF

my ( $fh, $fn ) = tempfile;
print $fh $string;
close $fh;

is_deeply( $hashref, Shipwright::Util::LoadFile($fn), 'LoadFile works' );
is_deeply( $hashref, Shipwright::Util::Load($string), 'Load works' );

is_deeply( $string, Shipwright::Util::Dump($hashref), 'Dump works' );

my ( undef, $fn2 ) = tempfile;
Shipwright::Util::DumpFile( $fn2, $hashref );
my $string2;
{ local $/; open my $fh, '<', $fn2 or die $!; $string2 = <$fh>; }

is( $string, $string2, 'DumpFile works' );


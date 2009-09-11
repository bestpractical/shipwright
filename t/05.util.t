use strict;
use warnings;

use Test::More tests => 16;

use Shipwright::Test;
use Shipwright::Util;
use File::Spec::Functions qw/catfile catdir/;
use File::Temp qw/tempfile/;
use Cwd;

Shipwright::Test->init;

my $cwd = getcwd;
my ( $shipwright_root, $share_root );

if ( grep { m{blib[/\\]lib} } @INC ) {

    # found blib/lib, so we're probably in `make test` or something like that.
    $shipwright_root = catfile( $cwd, 'blib', 'lib' );
    $share_root =
      catfile( $cwd, 'blib', 'lib', 'auto', 'share', 'dist', 'Shipwright' );
}
else {
    $shipwright_root = catfile( $cwd, 'lib' );
    $share_root      = catfile( $cwd, 'share' );
}

# we want to run shipwright_root and share_root twice to get codes covered.
for ( 1 .. 2 ) {
    is(
        $shipwright_root,
        Shipwright::Util->shipwright_root,
        'shipwright_root works',
    );
    is( $share_root, Shipwright::Util->share_root, 'share_root works' );
}

my ( $out, $err );
$out = Shipwright::Util->run( [ $^X, '-e', 'print "ok"' ] );
like( $out, qr/ok/, "normal run" );

( undef, $err ) = Shipwright::Util->run( [ $^X, '-e', 'die "error"' ], 1 );
like(
    $err,
    qr/error/i,
    "run with error again, also with ignore_failure"
);

$out = Shipwright::Util->run( sub { 'ok' } );
like( $out, qr/ok/, "normal code run" );

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

ok( Shipwright::Util->select('null'), 'selected null' );
ok( Shipwright::Util->select('cpan'), 'selected cpan' )
  for 1 .. 2;    # for test coverage
ok( Shipwright::Util->select('stdout'), 'selected stdout' );
eval { Shipwright::Util->select('noexists') };
like( $@, qr/unknown type/, 'unknown type results in death' );

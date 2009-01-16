use strict;
use warnings;

use Shipwright;
use Shipwright::Test;
use File::Spec::Functions qw/catfile catdir/;
use File::Temp qw/tempdir/;

use Test::More tests => 8;
Shipwright::Test->init;

my $repo = 'fs:' . create_fs_repo();

my $install_base = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );

my $sw = Shipwright->new(
    repository   => $repo,
    log_level    => 'FATAL',
    perl         => '/noexist',
    install_base => $install_base,
);
$sw->backend->initialize();

$sw->backend->export( target => $sw->build->build_base );
$sw->build->run();

is( $sw->build->perl, $^X, 'nonexist perl is changed to $^X' );

my $bin  = catfile( $install_base, 'bin' );
my $perl = catfile( $bin,          'perl' );
mkdir $bin unless -e $bin;

open my $fh, '>', $perl;
close $fh;
chmod 0755, $perl;
ok( -e $perl, 'found bin/perl in installed_base' );

$sw->build->perl(undef);
ok( !defined $sw->build->perl, 'make sure perl is undef' );

$sw->build->run;
is( $sw->build->perl, $perl,
    'set $build->perl to the one in install_base if that exists' );

$sw->build->perl(undef);
ok( !defined $sw->build->perl, 'make sure perl is undef' );

$sw->build->build_base(
    catdir( tempdir( CLEANUP => 1, TMPDIR => 1 ), 'build' ) );

# import a fake perl dist
my $source = catfile( tempdir( CLEANUP => 1, TMPDIR => 1 ), 'perl' );
mkdir $source;
my $script_dir = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
my $build_script = catfile( $script_dir, 'build' );
open $fh, '>', $build_script;
close $fh;

$sw->backend->import( source => $source );
$sw->backend->import(
    source       => $source,
    build_script => $script_dir,
);
$sw->backend->export( target => $sw->build->build_base );
$sw->build->run;
is( $sw->build->perl, $perl,
'set $build->perl to the one that will be in installed_dir if there is a dist with name perl'
);

$sw->build->perl(undef);
ok( !defined $sw->build->perl, 'make sure perl is undef' );
$sw->build->skip( { perl => 1 } );
$sw->build->install_base(
    catdir( tempdir( CLEANUP => 1, TMPDIR => 1 ), 'install' ) );
$sw->build->run;
is( $sw->build->perl, $^X,
    'install with --skip perl will not change $build->perl' );


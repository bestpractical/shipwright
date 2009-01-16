use strict;
use warnings;

use Shipwright;
use File::Temp qw/tempdir/;
use File::Copy;
use File::Copy::Recursive qw/dircopy/;
use File::Spec::Functions qw/catfile catdir updir/;
use File::Path qw/rmtree/;
use Cwd qw/getcwd abs_path/;

use Test::More tests => 17;
use Shipwright::Test;
Shipwright::Test->init;

SKIP: {
    skip "svk: no svk found or env SHIPWRIGHT_TEST_SVK not set", Test::More->builder->expected_tests
      if skip_svk();

    my $cwd = getcwd;

    create_svk_repo();

    my $repo = '//__shipwright/hello';

    my $shipwright = Shipwright->new(
        repository => "svk:$repo",
        source => 'file:' . catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ),
        follow => 0,
        log_level => 'FATAL',
        force => 1,
    );
    isa_ok( $shipwright->backend, 'Shipwright::Backend::SVK' );

    # init
    $shipwright->backend->initialize();
    my @dirs = sort `svk ls $repo`;
    chomp @dirs;
    is_deeply(
        [@dirs],
        [ 'bin/', 'etc/', 'inc/', 'scripts/', 'shipwright/', 'sources/', 't/' ],
        'initialize works'
    );

    # source
    my $source_dir = $shipwright->source->run();

    # import

    $shipwright->backend->import( name => 'hello', source => $source_dir );
    ok( grep( {/Build\.PL/} `svk ls $repo/sources/Acme-Hello/vendor` ),
        'imported ok' );

    my $script_dir = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    copy( catfile( 't', 'hello', 'scripts', 'build' ),       $script_dir );
    copy( catfile( 't', 'hello', 'scripts', 'require.yml' ), $script_dir );

    $shipwright->backend->import(
        name         => 'hello',
        source       => $source_dir,
        build_script => $script_dir,
    );
    ok( grep( {/Build\.PL/} `svk cat $repo/scripts/Acme-Hello/build` ),
        'build script ok' );

    # export
    $shipwright->backend->export( target => $shipwright->build->build_base );

    for (
        catfile( $shipwright->build->build_base, 'shipwright', 'order.yml', ),
        catfile(
            $shipwright->build->build_base, 'etc',
            'shipwright-script-wrapper'
        ),
        catfile(
            $shipwright->build->build_base, 'sources',
            'Acme-Hello',                   'vendor',
        ),
        catfile(
            $shipwright->build->build_base, 'sources',
            'Acme-Hello',                   'vendor',
            'MANIFEST',
        ),
        catfile(
            $shipwright->build->build_base, 'scripts',
            'Acme-Hello',                   'build',
        ),
      )
    {
        ok( -e $_, "$_ exists" );
    }

    # install
    $shipwright->build->run();

    for (
        catfile( $shipwright->build->install_base, 'lib', 'perl5', 'Acme', 'Hello.pm' ),
        catfile( $shipwright->build->install_base, 'etc', 'shipwright-script-wrapper' ),
      )
    {
        ok( -e $_, "$_ exists" );
    }

    rmtree( abs_path(catdir( $shipwright->build->install_base, updir() )) );

    # import another dist

    chdir $cwd;
    $shipwright = Shipwright->new(
        repository => "svk:$repo",
        source => 'file:' . catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ),
        name   => 'howdy',
        follow => 0,
        log_level => 'FATAL',
        force => 1,
    );

    $source_dir = $shipwright->source->run();
    like( $source_dir, qr/\bhowdy\b/, 'source name looks ok' );
    $shipwright->backend->import( name => 'hello', source => $source_dir );
    ok( grep( {/Build\.PL/} `svk ls $repo/sources/howdy/vendor` ),
        'imported ok' );
    $script_dir = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    copy( catfile( 't', 'hello', 'scripts', 'build' ), $script_dir );
    copy( catfile( 't', 'hello', 'scripts', 'howdy_require.yml' ),
        catfile( $script_dir, 'require.yml' ) );

    $shipwright->backend->import(
        name         => 'hello',
        source       => $source_dir,
        build_script => $script_dir,
    );
    ok( grep( {/Build\.PL/} `svk cat $repo/scripts/howdy/build` ),
        'build script ok' );

    my $tempdir = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    dircopy(
        catfile( 't',      'hello', 'shipwright' ),
        catfile( $tempdir, 'shipwright' )
    );

    # check to see if update_order works
    like(
        `svk cat $repo/shipwright/order.yml`,
        qr/Acme-Hello.*howdy/s,
        'original order is right'
    );

    system( 'svk import '
          . catfile( $tempdir, 'shipwright' )
          . " $repo/shipwright -m ''" );
    like(
        `svk cat $repo/shipwright/order.yml`,
        qr/howdy.*Acme-Hello/s,
        'imported wrong order works'
    );

    $shipwright->backend->update_order;
    like(
        `svk cat $repo/shipwright/order.yml`,
        qr/Acme-Hello.*howdy/s,
        'updated order works'
    );

}


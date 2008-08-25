use strict;
use warnings;

use Shipwright;
use File::Temp qw/tempdir/;
use File::Copy;
use File::Copy::Recursive qw/dircopy/;
use File::Spec::Functions qw/catfile catdir/;
use Cwd;
use Test::More tests => 17;
use Shipwright::Test qw/has_svn create_svn_repo/;
Shipwright::Test->init;

SKIP: {
    skip "no svn found", Test::More->builder->expected_tests
      unless has_svn();

    my $cwd = getcwd;

    my $repo = create_svn_repo() . '/hello';

    my $shipwright = Shipwright->new(
        repository => "svn:$repo",
        source => 'file:' . catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ),
        log_level => 'FATAL',
        follow    => 0,
    );

    isa_ok( $shipwright->backend, 'Shipwright::Backend::SVN' );

    # init
    $shipwright->backend->initialize();
    my @dirs = sort `svn ls $repo`;
    chomp @dirs;
    is_deeply(
        [@dirs],
        [ 'bin/', 'dists/', 'etc/', 'inc/', 'scripts/', 'shipwright/', 't/' ],
        'initialize works'
    );

    # source
    my $source_dir = $shipwright->source->run();

    # import
    $shipwright->backend->import( name => 'hello', source => $source_dir );
    ok( grep( {/Build\.PL/} `svn ls $repo/dists/Acme-Hello` ), 'imported ok' );

    my $script_dir = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    copy( catfile( 't', 'hello', 'scripts', 'build' ),       $script_dir );
    copy( catfile( 't', 'hello', 'scripts', 'require.yml' ), $script_dir );

    $shipwright->backend->import(
        name         => 'hello',
        source       => $source_dir,
        build_script => $script_dir,
        log_level    => 'FATAL',
    );
    ok( grep( {/Build\.PL/} `svn cat $repo/scripts/Acme-Hello/build` ),
        'build script ok' );

    # export
    $shipwright->backend->export( target => $shipwright->build->build_base );

    for (
        catfile( $shipwright->build->build_base, 'shipwright', 'order.yml', ),
        catfile(
            $shipwright->build->build_base, 'etc',
            'shipwright-script-wrapper'
        ),
        catfile( $shipwright->build->build_base, 'dists', 'Acme-Hello', ),
        catfile(
            $shipwright->build->build_base, 'dists',
            'Acme-Hello',                   'MANIFEST',
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
    my $install_dir = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    $shipwright->build->run( install_base => $install_dir );

    for (
        catfile( $install_dir, 'lib', 'perl5', 'Acme', 'Hello.pm' ),
        catfile( $install_dir, 'etc', 'shipwright-script-wrapper' ),
      )
    {
        ok( -e $_, "$_ exists" );
    }

    # import another dist

    chdir $cwd;
    $shipwright = Shipwright->new(
        repository => "svn:$repo",
        source => 'file:' . catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ),
        name   => 'howdy',
        follow => 0,
        log_level => 'FATAL',
    );

    $source_dir = $shipwright->source->run();
    like( $source_dir, qr/\bhowdy\b/, 'source name looks ok' );
    $shipwright->backend->import( name => 'hello', source => $source_dir );
    ok( grep( {/Build\.PL/} `svn ls $repo/dists/howdy` ), 'imported ok' );
    $script_dir = tempdir( CLEANUP => 1 );
    copy( catfile( 't', 'hello', 'scripts', 'build' ), $script_dir );
    copy( catfile( 't', 'hello', 'scripts', 'howdy_require.yml' ),
        catfile( $script_dir, 'require.yml' ) );

    $shipwright->backend->import(
        name         => 'hello',
        source       => $source_dir,
        build_script => $script_dir,
    );
    ok( grep( {/Build\.PL/} `svn cat $repo/scripts/howdy/build` ),
        'build script ok' );

    my $tempdir = tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    dircopy(
        catfile( 't',      'hello', 'shipwright' ),
        catfile( $tempdir, 'shipwright' )
    );

    # check to see if update_order works
    like(
        `svn cat $repo/shipwright/order.yml`,
        qr/Acme-Hello.*howdy/s,
        'order is right'
    );

    system( 'svn delete -m "" ' . " $repo/shipwright" );
    system( 'svn import '
          . catfile( $tempdir, 'shipwright' )
          . " $repo/shipwright -m ''" );
    like(
        `svn cat $repo/shipwright/order.yml`,
        qr/howdy.*Acme-Hello/s,
        'imported wrong order works'
    );

    $shipwright->backend->update_order;
    like(
        `svn cat $repo/shipwright/order.yml`,
        qr/Acme-Hello.*howdy/s,
        'updated order works'
    );
}


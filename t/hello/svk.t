use strict;
use warnings;

use Shipwright;
use File::Temp qw/tempdir/;
use File::Copy;
use File::Copy::Recursive qw/dircopy/;
use File::Spec::Functions qw/catfile catdir/;
use Cwd;

use Test::More tests => 41;
use Shipwright::Test qw/has_svk create_svk_repo/;
Shipwright::Test->init;

SKIP: {
    skip "no svk and svnadmin found", Test::More->builder->expected_tests
      unless has_svk();

    my $cwd = getcwd;

    create_svk_repo();

    my $repo = '//__shipwright/hello';

    my %source = (
        'http://example.com/hello.tar.gz'    => 'HTTP',
        'ftp://example.com/hello.tar.gz'     => 'FTP',
        'svn:file:///home/sunnavy/svn/hello' => 'SVN',
        'svk://local/hello'                  => 'SVK',
        'cpan:Acme::Hello'                   => 'CPAN',
        'file:'
          . catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ) => 'Compressed',
        'dir:' . catfile( 't', 'hello' ) => 'Directory',
    );

    for ( keys %source ) {
        my $shipwright = Shipwright->new(
            repository => "svk:$repo",
            source     => $_,
            log_level  => 'FATAL',
        );
        isa_ok( $shipwright, 'Shipwright' );
        isa_ok( $shipwright->source, "Shipwright::Source::$source{$_}" );
    }

    my $shipwright = Shipwright->new(
        repository => "svk:$repo",
        source => 'file:' . catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ),
        follow => 0,
        log_level => 'FATAL',
        force => 1,
    );

    isa_ok( $shipwright,          'Shipwright' );
    isa_ok( $shipwright->backend, 'Shipwright::Backend::SVK' );
    isa_ok( $shipwright->source,  'Shipwright::Source::Compressed' );
    isa_ok( $shipwright->build,   'Shipwright::Build' );

    # init
    $shipwright->backend->initialize();
    my @dirs = sort `svk ls $repo`;
    chomp @dirs;
    is_deeply(
        [@dirs],
        [ 'bin/', 'dists/', 'etc/', 'inc/', 'scripts/', 'shipwright/', 't/' ],
        'initialize works'
    );

    # source
    my $source_dir = $shipwright->source->run();
    like( $source_dir, qr/\bAcme-Hello\b/, 'source name looks ok' );

    for (qw/source backend build/) {
        isa_ok( $shipwright->$_->log, 'Log::Log4perl::Logger' );
    }

    ok( -e catfile( $source_dir, 'lib', 'Acme', 'Hello.pm' ),
        'lib/Acme/Hello.pm exists in the source' );
    ok( -e catfile( $source_dir, 'META.yml' ),
        'META.yml exists in the source' );

    # import

    $shipwright->backend->import( name => 'hello', source => $source_dir );
    ok( grep( {/Build\.PL/} `svk ls $repo/dists/Acme-Hello` ), 'imported ok' );

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
    ok( grep( {/Build\.PL/} `svk ls $repo/dists/howdy` ), 'imported ok' );
    $script_dir = tempdir( CLEANUP => 1 );
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

    # build with 0 packages

    {
        my $shipwright = Shipwright->new(
            repository => "svk:$repo",
            log_level  => 'FATAL',
        );

        # init
        $shipwright->backend->initialize();
        $shipwright->backend->export(
            target => $shipwright->build->build_base );
        my $install_dir =
          tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
        $shipwright->build->run( install_base => $install_dir );
        ok( -e catfile( $install_dir, 'etc', 'shipwright-script-wrapper' ),
            'build with 0 packages ok' );
    }
}


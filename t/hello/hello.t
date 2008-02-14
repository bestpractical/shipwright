use strict;
use warnings;

use Shipwright;
use File::Temp qw/tempdir/;
use File::Copy;
use File::Copy::Recursive qw/dircopy/;
use File::Spec;
use Cwd;

use Test::More tests => 40;
SKIP: {
    skip "can't find svk in PATH", 40,
      unless `whereis svk`;

    my $cwd  = getcwd;

    my $svk_root = tempdir;
    $ENV{SVKROOT} = $svk_root;
    my $svk_root_local = File::Spec->catfile( $svk_root, 'local' );
    system("svnadmin create $svk_root_local");
    system("svk depotmap -i");

    my $repo = '//__shipwright/hello';

    my %source = (
        'http://example.com/hello.tar.gz'    => 'HTTP',
        'ftp://example.com/hello.tar.gz'     => 'FTP',
        'svn:file:///home/sunnavy/svn/hello' => 'SVN',
        'svk://local/hello'                  => 'SVK',
        'Acme::Hello'                        => 'CPAN',
        File::Spec->catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ) =>
          'Compressed',
        File::Spec->catfile( 't', 'hello' ) => 'Directory',
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
        source => File::Spec->catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ),
        follow => 0,
        log_level => 'FATAL',
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
        [ 'bin/', 'dists/', 'etc/', 'scripts/', 'shipwright/', 't/' ],
        'initialize works'
    );

    # source
    my $source_dir = $shipwright->source->run();
    like( $source_dir, qr/\bAcme-Hello\b/, 'source name looks ok' );

    for (qw/source backend build/) {
        isa_ok( $shipwright->$_->log, 'Log::Log4perl::Logger' );
    }

    ok( -e File::Spec->catfile( $source_dir, 'lib', 'Acme', 'Hello.pm' ),
        'lib/Acme/Hello.pm exists in the source' );
    ok( -e File::Spec->catfile( $source_dir, 'META.yml' ),
        'META.yml exists in the source' );

    # import

    $shipwright->backend->import( name => 'hello', source => $source_dir );
    ok( grep( {/Build\.PL/} `svk ls $repo/dists/Acme-Hello` ), 'imported ok' );

    my $script_dir = tempdir( CLEANUP => 1 );
    copy( File::Spec->catfile( 't', 'hello', 'scripts', 'build' ),
        $script_dir );
    copy( File::Spec->catfile( 't', 'hello', 'scripts', 'require.yml' ),
        $script_dir );

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
        File::Spec->catfile(
            $shipwright->build->build_base,
            'shipwright', 'order.yml',
        ),
        File::Spec->catfile(
            $shipwright->build->build_base, 'etc',
            'shipwright-script-wrapper'
        ),
        File::Spec->catfile(
            $shipwright->build->build_base,
            'dists', 'Acme-Hello',
        ),
        File::Spec->catfile(
            $shipwright->build->build_base, 'dists',
            'Acme-Hello',                   'MANIFEST',
        ),
        File::Spec->catfile(
            $shipwright->build->build_base, 'scripts',
            'Acme-Hello',                   'build',
        ),
      )
    {
        ok( -e $_, "$_ exists" );
    }

    # install
    my $install_dir = tempdir;
    $shipwright->build->run( install_base => $install_dir );

    for (
        File::Spec->catfile( $install_dir, 'lib', 'perl5', 'Acme', 'Hello.pm' ),
        File::Spec->catfile( $install_dir, 'etc', 'shipwright-script-wrapper' ),
      )
    {
        ok( -e $_, "$_ exists" );
    }

    # import another dist

    chdir $cwd;
    $shipwright = Shipwright->new(
        repository => "svk:$repo",
        source => File::Spec->catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ),
        name   => 'howdy',
        follow => 0,
        log_level => 'FATAL',
    );

    $source_dir = $shipwright->source->run();
    like( $source_dir, qr/\bhowdy\b/, 'source name looks ok' );
    $shipwright->backend->import( name => 'hello', source => $source_dir );
    ok( grep( {/Build\.PL/} `svk ls $repo/dists/howdy` ), 'imported ok' );
    $script_dir = tempdir( CLEANUP => 1 );
    copy( File::Spec->catfile( 't', 'hello', 'scripts', 'build' ),
        $script_dir );
    copy( File::Spec->catfile( 't', 'hello', 'scripts', 'howdy_require.yml' ),
        File::Spec->catfile( $script_dir, 'require.yml' ) );

    $shipwright->backend->import(
        name         => 'hello',
        source       => $source_dir,
        build_script => $script_dir,
    );
    ok( grep( {/Build\.PL/} `svk cat $repo/scripts/howdy/build` ),
        'build script ok' );

    my $tempdir = tempdir( CLEANUP => 1 );
    dircopy(
        File::Spec->catfile( 't',      'hello', 'shipwright' ),
        File::Spec->catfile( $tempdir, 'shipwright' )
    );

    # check to see if update_order works
    like(
        `svk cat $repo/shipwright/order.yml`,
        qr/Acme-Hello.*howdy/s,
        'original order is right'
    );

    system( 'svk import '
          . File::Spec->catfile( $tempdir, 'shipwright' )
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

use strict;
use warnings;

use Shipwright;
use Shipwright::Test qw/has_svk create_svk_repo has_svn create_svn_repo/;
use File::Spec::Functions qw/catfile/;
use File::Temp qw/tempdir/;

use Test::More tests => 8;

SKIP: {
    skip "no svk and svnadmin found", 3
      unless has_svk();

    create_svk_repo();

    my $repo = '//__shipwright/foo';

    my $install_base = tempdir;

    my $sw = Shipwright->new(
        repository   => "svk:$repo",
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

    $sw->build->build_base( catfile( tempdir, 'build' ) );

    $sw->build->perl(undef);
    ok( !defined $sw->build->perl, 'make sure perl is undef' );

    # import a fake perl dist
    my $source = catfile( tempdir, 'perl' );
    mkdir $source;
    my $script_dir = tempdir;
    my $build_script = catfile( $script_dir, 'build' );
    open $fh, '>', $build_script;
    close $fh;

    $sw->backend->import( source => $source );
    $sw->backend->import(
        source       => $source,
        build_script => $script_dir,
    );
    $sw->backend->export( target => $sw->build->build_base );
    $sw->build->build_base;
    $sw->build->run;
    is( $sw->build->perl, $perl,
'set $build->perl to the one that will be in installed_dir if there is a dist with name perl'
    );

    $sw->build->perl(undef);
    ok( !defined $sw->build->perl, 'make sure perl is undef' );
    $sw->build->skip( { perl => 1 } );
    $sw->build->install_base(tempdir);
    $sw->build->run;
    is( $sw->build->perl, $^X,
        'install with --skip perl will not change $build->perl' );
}


use strict;
use warnings;

use Shipwright;
use Shipwright::Test qw/has_svk create_svk_repo has_svn create_svn_repo/;
use File::Spec;

use Test::More tests => 6;

SKIP: {
    skip "no svk and svnadmin found", 3
      unless has_svk();

    create_svk_repo();
    my $repo = '//__shipwright/foo';

    my $shipwright = Shipwright->new(
        repository => "svk:$repo",
        log_level => 'FATAL',
    );

    test_flags( shipwright => $shipwright, dist => 'foo' );

}

SKIP: {
    skip "no svn and svnadmin found", 3
      unless has_svn();

    my $repo = create_svn_repo . '/foo';

    my $shipwright = Shipwright->new(
        repository => "svn:$repo",
        log_level => 'FATAL',
    );

    test_flags( shipwright => $shipwright, dist => 'foo' );

}

sub test_flags {
    my %args = @_;
    my $shipwright = $args{shipwright};
    my $dist = $args{dist};

    # init
    $shipwright->backend->initialize();

    my $flags = $shipwright->backend->flags( dist => 'hello' );
    is_deeply( $flags, [], 'initial flags are []' );

    $shipwright->backend->flags( dist => 'hello', flags => [ 'foo', 'bar' ] );
    $flags = $shipwright->backend->flags( dist => 'hello' );
    is_deeply( $flags, [ 'foo', 'bar' ], "set flags to ['foo', 'bar']" );

    $shipwright->backend->flags( dist => 'hello', flags => [] );
    $flags = $shipwright->backend->flags( dist => 'hello' );
    is_deeply( $flags, [], "set flags to []" );
}

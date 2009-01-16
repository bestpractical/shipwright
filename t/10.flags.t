use strict;
use warnings;

use Shipwright;
use Shipwright::Test qw/skip_svk create_svk_repo skip_svn create_svn_repo/;
use File::Spec::Functions qw/catfile catdir/;

use Test::More tests => 6;

Shipwright::Test->init;

SKIP: {
    skip "svk: no svk found or env SHIPWRIGHT_TEST_BACKEND_SVK not set", 3
      if skip_svk();

    create_svk_repo();
    my $repo = '//__shipwright/foo';

    my $shipwright = Shipwright->new(
        repository => "svk:$repo",
        log_level  => 'FATAL',
    );

    test_flags( shipwright => $shipwright, name => 'foo' );

}

SKIP: {
    skip "svn: no svn found or env SHIPWRIGHT_TEST_BACKEND_SVN not set", 3
      if skip_svn();

    my $repo = create_svn_repo . '/foo';

    my $shipwright = Shipwright->new(
        repository => "svn:$repo",
        log_level  => 'FATAL',
    );

    test_flags( shipwright => $shipwright, name => 'foo' );

}

sub test_flags {
    my %args       = @_;
    my $shipwright = $args{shipwright};
    my $name       = $args{name};

    # init
    $shipwright->backend->initialize();

    my $flags = $shipwright->backend->flags;
    is_deeply( $flags->{$name}, undef, 'initial flags are undef' );

    $flags->{$name} = [ 'foo', 'bar' ];
    $shipwright->backend->flags($flags);

    $flags = $shipwright->backend->flags;
    is_deeply(
        $flags->{$name},
        [ 'foo', 'bar' ],
        "set flags to ['foo', 'bar']"
    );

    $flags->{$name} = [];
    $shipwright->backend->flags($flags);

    $flags = $shipwright->backend->flags;
    is_deeply( $flags->{$name}, [], "set flags to []" );
}

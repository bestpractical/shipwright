use strict;
use warnings;

use Shipwright;
use Shipwright::Test qw/has_svk create_svk_repo has_svn create_svn_repo/;
use File::Spec::Functions qw/catfile/;
use File::Temp qw/tempdir/;

use Test::More tests => 4;

my $shipwright = Shipwright->new( log_level => 'fatal', repository => '//foo' );

SKIP: {
    skip "no svk found", 4
      unless has_svk();

    create_svk_repo();

    # repo check for action 'create'

    my %map = (
        create => {
            '//__shipwright/foo' => 1,
            'svk:/noexists/'          => 0,
        },
        list => {
            '//__shipwright/foo' => 0,
            'svk:/noexists/'          => 0,
        },
    );

    for my $action ( keys %map ) {
        for my $repo ( keys %{ $map{$action} } ) {
            my $backend = Shipwright::Backend->new( repository => $repo );
            is(
                $backend->check_repository( action => $action ),
                $map{$action}{$repo},
                "$repo for action $action",
            );
        }
    }

}


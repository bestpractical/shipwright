use strict;
use warnings;

use Shipwright;
use Shipwright::Test qw/has_svk create_svk_repo has_svn create_svn_repo/;
use File::Spec::Functions qw/catfile/;
use File::Temp qw/tempdir/;

use Test::More tests => 8;

my $shipwright = Shipwright->new( log_level => 'fatal', repository => '//foo' );

SKIP: {
    skip "no svk found", 4
      unless has_svk();

    create_svk_repo();

    # repo check for action 'create'

    my %map = (
        create => {
            '//__shipwright/foo' => 1,
            'svk:/noexists/'     => 0,
        },
        list => {
            '//__shipwright/foo' => 0,
            'svk:/noexists/'     => 0,
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

SKIP: {
    skip "no svn found", 4
      unless has_svn();

    my $valid   = create_svn_repo();
    my $invalid = 'svn:file:///aa/bb/cc';

    # repo check for action 'create'

    my %map = (
        create => {
            "svn:$valid" => 1,
            $invalid     => 0,
        },
        list => {
            "svn:$valid" => 0,
            $invalid     => 0,
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

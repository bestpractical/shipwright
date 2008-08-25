use strict;
use warnings;

use Shipwright;
use Shipwright::Test qw/has_svk create_svk_repo has_svn create_svn_repo/;
use File::Spec::Functions qw/catfile/;
use File::Temp qw/tempdir/;

use Test::More tests => 10;

Shipwright::Test->init;

SKIP: {
    skip "no svk found", 5
      unless has_svk();

    create_svk_repo();

    my $shipwright =
      Shipwright->new( log_level => 'fatal', repository => '//bar' );
    $shipwright->backend->initialize;

    my %map = (
        create => {
            '//__shipwright/foo' => 1,
            'svk:/noexists/'     => undef,
        },
        list => {
            '//__shipwright/foo' => undef,
            'svk:/noexists/'     => undef,
            '//bar'              => 1,
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
    skip "no svn found", 5
      unless has_svn();

    my $valid   = create_svn_repo();
    my $invalid = 'svn:file:///aa/bb/cc';

    my $shipwright = Shipwright->new(
        log_level  => 'fatal',
        repository => "svn:$valid/bar"
    );
    $shipwright->backend->initialize;

    my %map = (
        create => {
            "svn:$valid" => 1,
            $invalid     => undef,
        },
        list => {
            "svn:$valid"     => undef,
            $invalid         => undef,
            "svn:$valid/bar" => 1,
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

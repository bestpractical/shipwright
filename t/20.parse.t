use strict;
use warnings;

use Test::More tests => 8;    # last test to print

# we don't want to include YAML lib in vessel, so we reinvent some simple
# parsers for yaml files we use in vessel. Fortunately, what we use in vessel
# are very simple yamls ;)

use Data::Dumper;
use Shipwright::Util;

my %map = (
    't/parse/order1.yml' => [qw/foo bar/],
    't/parse/order2.yml' => [],
);

for my $file ( keys %map ) {
    my $a = parse_order($file);
    my $b = Shipwright::Util::LoadFile($file) || [];
    is_deeply( $a, $map{$file}, 'parse_order returns right' );
    is_deeply( $a, $b, 'parse_order returns the same as YAML' );
}

%map = (
    't/parse/flags1.yml' => {
        foo => [qw/a bc/],
        bar => [qw/abc/],
        baz => ['c'],
    },

    't/parse/flags2.yml' => {},
);

for my $file ( keys %map ) {
    my $a = parse_flags($file);
    my $b = Shipwright::Util::LoadFile($file) || {};
    is_deeply( $a, $map{$file}, 'parse_order returns right' );
    is_deeply( $a, $b, 'parse_order returns the same as YAML' );
}

sub parse_order {
    my $file  = shift;
    my $order = [];
    open my $fh, '<', $file or die $!;
    while (<$fh>) {
        if (/^- (\S+)/) {
            push @$order, $1;
        }
    }
    return $order;
}

sub parse_flags {
    my $file  = shift;
    my $flags = {};
    open my $fh, '<', $file or die $!;
    my $dist;

    while (<$fh>) {
        if (/^(\S+):/) {
            $dist = $1;
            $flags->{$dist} = undef;
        }
        elsif (/\s+- (\S+)/) {
            push @{ $flags->{$dist} }, $1;
        }
    }
    return $flags;
}


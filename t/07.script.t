use strict;
use warnings;

use Test::More tests => 11;

use Shipwright::Script;
use Shipwright;

is_deeply(
    { del => 'delete', ls => 'list', up => 'update' },
    { Shipwright::Script->alias },
    "alias returns ( del => 'delete', ls => 'list', up => 'update' )"
);

my $logger = Shipwright::Script->log;
isa_ok( $logger, 'Log::Log4perl::Logger', 'Shipwright::Script->log' );

my %argv = (
    'passed nothing will get a help' => [],
    'passed -h will get a help'  => ['-h'],
    'passed --help will get a help'  => ['--help'],
);

for my $msg ( keys %argv ) {
    @ARGV = @{ $argv{$msg} };
    my $cmd = Shipwright::Script->prepare();
    isa_ok($cmd, 'Shipwright::Script::Help' )
}

my %wrong_argv = (
    'Unknown option: (r|repository)' => [
        [ 'ls', '-r' ],
        [ 'ls', '--repository' ],
    ],
    'need repository arg' => [ ['ls'] ],
    'invalid repository' => [
        [ 'ls', '-r', 'lalal' ],
        [ 'ls', '-r', 'svn:///foo/bar' ],
        [ 'ls', '-r', '-l' ],
    ],
);

for my $msg ( keys %wrong_argv ) {
    for my $v ( @{ $wrong_argv{$msg} } ) {
        eval { @ARGV = @$v; Shipwright::Script->prepare };
        like( $@, qr/$msg/, $msg );
    }
}


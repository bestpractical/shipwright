use strict;
use warnings;

use Test::More tests => 19;

use Shipwright::Script;
use Shipwright;
use Shipwright::Test::Fake::App::CLI;
@Shipwright::Script::ISA = 'Shipwright::Test::Fake::App::CLI';

is_deeply(
    { del => 'delete', ls => 'list', up => 'update' },
    { Shipwright::Script->alias },
    "alias returns ( del => 'delete', ls => 'list', up => 'update' )"
);

my $logger = Shipwright::Script->log;
isa_ok( $logger, 'Log::Log4perl::Logger', 'Shipwright::Script->log' );

my %argv = (
    'passed nothing will get a help' => [ [],         ['help'] ],
    'passed -h will get a help'      => [ ['-h'],     ['help'] ],
    'passed --help will get a help'  => [ ['--help'], ['help'] ],
    'passed cmd without -r will get a cmd help',
    [ [ 'ls', 'foo' ], [ 'help', 'ls' ] ],
    'passed cmd without -r args but with -l will get cmd help',
    [ [ 'ls', '-l', 'info' ], [ 'help', 'ls' ] ],
    'passed cmd without -r args but with --log-level will get cmd help', [
        [ 'ls', '--log-file', 'info' ], [ 'help', 'ls' ]
    ],
);

for my $msg ( keys %argv ) {
    @ARGV = @{ $argv{$msg}->[0] };
    Shipwright::Script->prepare;
    is_deeply( \@ARGV, $argv{$msg}->[1], $msg );
}

my %wrong_argv = (
    'option repository requires an argument' => [
        [ 'ls', '-r' ],
        [ 'ls', '-r', '-l',         'info' ],
        [ 'ls', '--repository' ],
        [ 'ls', '-r', '--log-file', '/tmp/t.log' ]
    ],
    'invalid repository' =>
      [ [ 'ls', '-r', 'lalal' ], [ 'ls', '-r', 'svn:///foo/bar' ] ],
    'option log-level requires an argument' =>
      [ [ 'ls', '-l' ], [ 'ls', '-l', '-foo' ], [ 'ls', '--log-level' ] ],
    'option log-file requires an argument' =>
      [ [ 'ls', '--log-file' ], [ 'ls', '--log-file', '-foo' ] ],
);

for my $msg ( keys %wrong_argv ) {
    for my $v ( @{ $wrong_argv{$msg} } ) {
        eval { @ARGV = @$v; Shipwright::Script->prepare };
        like( $@, qr/$msg/, $msg );
    }
}


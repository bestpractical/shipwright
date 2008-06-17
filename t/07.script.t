use strict;
use warnings;

use Test::More tests => 2;

use Shipwright::Script;

is_deeply(
    { del => 'delete', ls => 'list', up => 'update' },
    { Shipwright::Script->alias },
    "alias returns ( del => 'delete', ls => 'list', up => 'update' )"
);

my $logger = Shipwright::Script->log;
isa_ok( $logger, 'Log::Log4perl::Logger', 'Shipwright::Script->log' );


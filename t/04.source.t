use strict;
use warnings;

use Test::More tests => 12;
use Shipwright::Test;
use Shipwright::Source;

Shipwright::Test->init;

my %source = (
    'http://example.com/hello.tar.gz'           => 'HTTP',
    'ftp://example.com/hello.tar.gz'            => 'FTP',
    'svn:file:///home/sunnavy/svn/hello'        => 'SVN',
    'svk://local/hello'                         => 'SVK',
    'cpan:Acme::Hello'                          => 'CPAN',
    'cpan:S/SU/SUNNAVY/IP-QQWry-v0.0.15.tar.gz' => 'CPAN',
    'file:'
      . File::Spec->catfile( 't', 'hello', 'Acme-Hello-0.03.tar.gz' ) =>
      'Compressed',
    'dir:' . File::Spec->catfile( 't', 'hello' ) => 'Directory',
);

for ( keys %source ) {
    my $source = Shipwright::Source->new( source => $_ );
    isa_ok( $source, 'Shipwright::Source::' . $source{$_}, $_ );
}

my @invalid_sources = ( 'file:/tmp/ok', 'foo', '' );

for (@invalid_sources) {
    eval { my $source = Shipwright::Source->new( source => $_ ) };
    like( $@, qr/invalid source/, "$_ is invalid source" );
}

eval { my $source = Shipwright::Source->new };
like( $@, qr/need source arg/, 'new need source arg' );


use strict;
use warnings;

use Test::More tests => 2;

use Shipwright::Util;
use File::Spec::Functions qw/catfile/;
my $share_root = Shipwright::Util->share_root;
my $builder = catfile( $share_root, 'bin', 'shipwright-builder' );

my $help = `$^X $builder --help`;
like($help, qr/--advanced-help/, 'usage string' );
like($help, qr/--skip-test/,'usage string');

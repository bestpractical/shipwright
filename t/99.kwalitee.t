use Test::More;
eval { use Test::Kwalitee 1.01; };
plan( skip_all => 'Test::Kwalitee not installed; skipping' ) if $@;

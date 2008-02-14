use Test::More tests => 18;

BEGIN {
    use_ok('Shipwright');
    use_ok('Shipwright::Build');
    use_ok('Shipwright::Backend');
    use_ok('Shipwright::Backend::SVK');
    use_ok('Shipwright::Logger');
    use_ok('Shipwright::Source');
    use_ok('Shipwright::Source::Compressed');
    use_ok('Shipwright::Source::CPAN');
    use_ok('Shipwright::Source::Directory');
    use_ok('Shipwright::Source::HTTP');
    use_ok('Shipwright::Source::FTP');
    use_ok('Shipwright::Script');
    use_ok('Shipwright::Script::Initialize');
    use_ok('Shipwright::Script::Import');
    use_ok('Shipwright::Script::Build');
    use_ok('Shipwright::Script::Help');
    use_ok('Shipwright::Script::Maintain');
    use_ok('Shipwright::Util');
}

diag("Testing Shipwright $Shipwright::VERSION");

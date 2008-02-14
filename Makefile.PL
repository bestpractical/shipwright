use strict;
use warnings;
use inc::Module::Install 0.46;
name 'Shipwright';
all_from 'lib/Shipwright.pm';
build_requires 'Module::Build' => 0;
requires 'App::CLI' => 0;
requires 'Algorithm::Dependency::Ordered' => 0;
requires 'Algorithm::Dependency::Source::HoA' => 0;
requires 'CPAN' => 1.9205;
requires 'CPAN::DistnameInfo' => 0;
requires 'Class::Accessor::Fast' => 0;
requires 'File::Temp' => 0;
requires 'File::Copy' => 0;
requires 'File::Copy::Recursive' => 0;
requires 'File::Spec' => 0;
requires 'File::Slurp' => 0;
requires 'Hash::Merge' => 0;
requires 'IPC::Run3' => 0;
requires 'Log::Log4perl' => 0;
requires 'LWP::UserAgent' => 0;
requires 'Module::CoreList' => 0;
requires 'UNIVERSAL::require' => 0;
requires 'version' => 0;

if ( can_cc() ) {
    requires( 'YAML::Syck' => 0.71 );
}
else {
    requires( 'YAML' => 0.35 ) unless can_use( 'YAML::Syck' => 0.71 );
}


no_index( directory => 'examples' );
no_index( directory => 'docs' );
no_index( directory => 't' );

install_script('bin/shipwright');
auto_install;

tests('t/*.t t/*/*.t');

WriteAll;


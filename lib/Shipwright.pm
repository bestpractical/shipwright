package Shipwright;

use warnings;
use strict;
use Carp;

our $VERSION = '1.01';

use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(qw/backend source build log_level log_file/);

use Shipwright::Logger;
use Shipwright::Util;
use Shipwright::Backend;
use Shipwright::Source;
use Shipwright::Build;

=head2 new

initialize all Shipwright's components if possible.
args is a hash, supported keys: 

general part:

    repository: specify backend's path. e.g. svk:/t/test
    log_level: specify log level. default is INFO
    log_file: specify log file. default is append to screen.

source part:

    source: source need to import
    name: source's name
    follow: follow dep chain or not. default is true
    min_perl_version: minimal required perl version. 
             default is the same as the perl which's running shipwright
    skip: hashref of which the keys are the skipped modules when import
          default is undefined

build part:

    skip: hashref of which the keys are the skipped dists when install
          default is undefined
    skip_test: skip test or not. default is false
    install_base: install base path. default is a temp directory
    force: force install even if tests fail. default is false
    only_test: not install, just test. (used for already installed dists)
                default is false

=cut

sub new {
    my $class = shift;

    my %args = @_;

    my $self = { log_level => $args{log_level}, log_file => $args{log_file} };
    bless $self, $class;

    Shipwright::Logger->new($self);

    $self->backend( Shipwright::Backend->new(%args) );

    if ( $args{source} ) {
        $self->source( Shipwright::Source->new(%args) );
    }

    $self->build( Shipwright::Build->new(%args) );

    return $self;
}

1;

__END__

=head1 NAME

Shipwright - Best Practical Builder


=head1 SYNOPSIS

    use Shipwright;

=head1 DESCRIPTION

=head2 Summary

Shipwright's a tool to help you bundle dists.

We don't want to repeat ourself, so when we write a dist, we'll try to use
as many already created and great modules( sure, I bet most of them can be
found on CPAN, though not all ) as we can.

When we want to install it, we have to install all of its dependences to let
it happy. Luckily, we have CPAN:: and CPANPLUS:: to help us install nearly
all of them without much pain, then maybe we need to fix the left non-cpan 
deps manually( usually, we'd fix the non-cpan deps first because some cpan
modules depend on them ;)

This surely works, but there're some drawbacks, especially for a large dist
which uses many cpan modules and even requires other stuff.  The install cmds
sometimes are too many to not be very friendly to end users, and it's not easy
to do version control with all the dependent dists since most of them are from
somewhere else we can't control.  If we need other non-perl dists( e.g.  we
need subversion and swig for SVK ), things'll be worse.

So we wrote Shipwright, a tool to help you bundle a dist with all of 
dependences, no matter it's a CPAN module or a dist from other place.
And it'll be very easy to install the bundle, usually with just one command:

$ ./bin/shipwright-builder

Follow the tutorial to feel how it's going :)

=head2 Design

The thought of shipwright is simple:

   raw material                   shipwright factory            
--------------------           ------------------------       
|  all the seperate|  import   |  internal shipwright |  build
|  dist sources    |  =====>   |  repository          |  ====> 
-------------------|            -----------------------

 vessels(final product) 
------------------------
|  installed to system |
------------------------

So there're mainly two useful commands in shipwright: import and build, which
can be invoked like this:

$ shipwright import ...

$ shipwright build ...

If you get a shipwright build repository, but don't have shipwright installed
on your system, there's no problem to install at all: the repository has
bin/shipwright-builder script.  ( in fact, we encourage you to build with
bin/shipwright-builder, because you can hack the script freely without worrying
about the changes maybe hurt other shipwright builds )

=head2 Details

=head3 after initialize

After initialize a project, the files in the repo are:

=over 4

bin/
     shipwright-builder   # used for build, install or just test
    
    # builder's own utlity, you can use it to update build order
     shipwright-utility

etc/
    # wrapper for installed bin files, mainly for optimizing env
     shipwright-script-wrapper
    
    # wrapper for installed perl scripts
    shipwright-perl-wrapper         
    
    # source files you can `source', for tcsh and bash, respectively.
    # both'll be installed to tools/
    shipwright-source-tcsh, shipwright-source-bash
    
    shipwright-utility # utility which'll be installed to tools/
 
dists/ # all the sources of your dists live here

scripts/ # all the build scripts and dependence hints live here

shipwright/
    order.yml # the actual build order
    source.yml # non-cpan dists' name => url map
    map.yml # cpan dists' module => name map

t/
    test # will run this if with --only-test when build

=back

=head3 after import

After import, e.g. Acme::Hello, both the dists and scripts directories will
have `cpan-Acme-Hello' directory.

Under scripts/cpan-Acme-Hello there're two files: 'build' and 'require.yml'.

=head4 build

=over 4

configure: %%PERL%% Build.PL --install_base=%%INSTALL_BASE%%
make: ./Build
test: ./Build test
install: ./Build install
clean: %%PERL%% Build realclean

=back

Each line is of `type: cmd' format, and the cmd is executed line by
line(which's also true for t/test).

We now support three templates in cmd, %%PERL%%, %%PERL_ARCHNAME%% and
%%INSTALL_BASE%%, so you can set it till build.

The `test' type is paticular:
- if we build with --skip-test, the corresponding cmd won't be executed. 
- if we build with --force, even the test cmd failed, we still go on building.

the `clean' type is also different: it's executed only when --clean.

=head4 require.yml

=over 4

build_requires: {}

conflicts: {}

recommends: 
  cpan-Locale-Maketext-Lexicon: 
    version: 0.15
requires: {}

This's the hint by which we can get right build order 

=back

=head4 after install

Normally, there're bin, bin-wrapper, etc, tools and lib directories.
One thing need to note is files below bin are for you to run, which are 
wrappers to the files bellow bin-wrapper with same names.

=head1 SEE ALSO

L<Shipwright::Tutorial>

=head1 DEPENDENCIES

None.


=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

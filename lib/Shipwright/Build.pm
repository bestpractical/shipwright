package Shipwright::Build;

use warnings;
use strict;
use Carp;

use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(
    qw/install_base perl build_base skip_test commands log
      skip only_test force order flags name only/
);

use File::Spec::Functions qw/catfile catdir splitdir/;
use File::Temp qw/tempdir/;
use File::Copy::Recursive qw/dircopy/;
use File::Copy qw/move copy/;
use File::Find qw/find/;
use File::Slurp;
use File::Path;
use Cwd qw/getcwd/;

=head2 new

=cut

# keeps the info of the already installed dists
my ( $installed, $installed_file );

sub new {
    my $class = shift;
    my $self  = {@_};
    bless $self, $class;

    $self->log( Log::Log4perl->get_logger( ref $self ) );

    $self->{build_base} ||=
      tempdir( 'shipwright_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
    rmdir $self->{build_base};

    $self->name('vessel') unless $self->name;
    $self->skip( {} ) unless $self->skip;

    unless ( $self->install_base ) {

        my $dir = tempdir( 'vessel_' . $self->name . '-XXXXXX', TMPDIR => 1 );
        $self->install_base( catfile( $dir, $self->name ) );
    }

    no warnings 'uninitialized';

    $ENV{DYLD_LIBRARY_PATH} =
      catfile( $self->install_base, 'lib' ) . ':' . $ENV{DYLD_LIBRARY_PATH};
    $ENV{LD_LIBRARY_PATH} =
      catfile( $self->install_base, 'lib' ) . ':' . $ENV{LD_LIBRARY_PATH};
    $ENV{PERL5LIB} =
        catfile( $self->install_base, 'lib', 'perl5', 'site_perl' ) . ':'
      . catfile( $self->install_base, 'lib', 'perl5' ) . ':'
      . $ENV{PERL5LIB};
    $ENV{PATH} =
        catfile( $self->install_base, 'bin' ) . ':'
      . catfile( $self->install_base, 'sbin' ) . ':'
      . $ENV{PATH};
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{LDFLAGS} .= ' -L' . catfile( $self->install_base, 'lib' );
    $ENV{CFLAGS}  .= ' -I' . catfile( $self->install_base, 'include' );

    require CPAN;
    require Module::Info;
    if ( Module::Info->new_from_module('CPAN::Config') ) {

        # keep original CPAN::Config info
        require CPAN::Config;
    }

    # we don't want any prereqs any more!
    $CPAN::Config->{prerequisites_policy} = 'ignore';

    return $self;
}

=head2 run

the mainly method, it do the actual work.

=cut

sub run {
    my $self = shift;
    my %args = @_;

    for ( keys %args ) {
        $self->$_( $args{$_} ) if $args{$_};
    }

    $self->log->info( 'run build to install to ' . $self->install_base );

    mkpath $self->install_base unless -e $self->install_base;

    my $orig_cwd = getcwd;
    chdir $self->build_base;

    if ( $self->only_test ) {
        $self->test;
    }
    else {
        dircopy( 'etc', catfile( $self->install_base, 'etc' ) );

        my $installed_hash = {};
        $installed_file = catfile( $self->install_base, 'installed.yml' );
        if ( -e $installed_file ) {
            $installed = Shipwright::Util::LoadFile($installed_file);
            $installed_hash = { map { $_ => 1 } @$installed };
        }
        else {
            $installed = [];
        }

        my $order =
          Shipwright::Util::LoadFile( catfile( 'shipwright', 'order.yml' ) )
          || [];

        my ( $flags, $ktf );
        if ( -e catfile( 'shipwright', 'flags.yml' ) ) {

            $flags =
              Shipwright::Util::LoadFile(
                catfile( 'shipwright', 'flags.yml' ) );

            # fill not specified but mandatory flags
            if ( $flags->{__mandatory} ) {
                for my $list ( values %{ $flags->{__mandatory} } ) {
                    next unless @$list;
                    next if grep { $self->flags->{$_} } @$list;
                    $self->flags->{ $list->[0] }++;
                }
            }
        }
        else {
            $flags = {};
        }

        if ( -e catfile( 'shipwright', 'known_test_failures.yml' ) ) {

            $ktf =
              Shipwright::Util::LoadFile(
                catfile( 'shipwright', 'known_test_failures.yml' ) );
        }
        else {
            $ktf = {};
        }

        # calculate the real order
        if ( $self->only ) {
            @$order = grep { $self->only->{$_} } @$order;
        }
        else {
            @$order =
              grep {
                (
                    $flags->{$_}
                    ? ( grep { $self->flags->{$_} } @{ $flags->{$_} } )
                    : 1
                  )
                  && !$self->skip->{$_}
              } @$order;
        }

        # remove the already installed ones
        @$order = grep { !$installed_hash->{$_} } @$order;

        unless ( $self->perl && -e $self->perl ) {
            my $perl = catfile( $self->install_base, 'bin', 'perl' );

            # -e $perl makes sense when we install on to another vessel
            if ( ( grep { /^perl/ } @{$order} ) || -e $perl ) {
                $self->perl($perl);
            }
            else {
                $self->perl($^X);
            }
        }

        for my $dist (@$order) {
            $self->_install( $dist, $ktf );
            $self->_record($dist);
            chdir $self->build_base;
        }

        $self->_wrapper();

        $self->log->info(
            "install finished. the dists are at " . $self->install_base );
    }

    chdir $orig_cwd;
}

# install one dist, the install methods are in scripts/distname/build

sub _install {
    my $self = shift;
    my $dir  = shift;
    my $ktf  = shift;

    chdir catfile( 'dists', $dir );

    if ( -e catfile( '..', '..', 'scripts', $dir, 'build.pl' ) ) {
        $self->log->info(
            "found build.pl for $dir, will install $dir using that");
        Shipwright::Util->run(
            [
                $self->perl,
                catfile( '..', '..', 'scripts', $dir, 'build.pl' ),
                '--install-base' => $self->install_base,
                '--flags'        => join( ',', keys %{ $self->flags } ),
                $self->skip_test ? '--skip-test' : (),
                $self->force     ? '--force'     : (),
            ]
        );

    }
    else {

        my @cmds = read_file( catfile( '..', '..', 'scripts', $dir, 'build' ) );
        chomp @cmds;
        @cmds = map { $self->_substitute($_) } @cmds;

        for (@cmds) {
            my ( $type, $cmd );
            next unless /\S/ && /^(?!#)/;    # skip commented and blank lines

            if (/^(\S+):\s*(.*)/) {
                $type = $1;
                $cmd  = $2;
            }
            else {
                $type = '';
                $cmd  = $_;
            }

            if ( $self->skip_test && $type eq 'test' ) {
                $self->log->info("skip build $type part in $dir");
                next;
            }

            $self->log->info("build $type part in $dir");

            if ( system($cmd) ) {
                $self->log->error("build $dir with failure when run $type: $!");
                if ( $type eq 'test' ) {
                    if ( $self->force ) {
                        $self->log->error(
"although tests failed, will install anyway since we have force arg\n"
                        );
                    }
                    ## no critic
                    elsif ( eval "$ktf->{$dir}" ) {
                        $self->log->error(
"although tests failed, will install anyway since it's a known failure\n"
                        );
                    }
                    next;
                }
                elsif ( $type ne 'clean' ) {

                    # clean is trivial, we'll just ignore if 'clean' fails
                    confess "build $dir $type part with failure.";
                }
            }
        }
    }
    $self->log->info("build $dir with success!");
}

# wrap the bin files, mainly for ENV
sub _wrapper {
    my $self = shift;

    my $sub = sub {
        my $file = $_;
        return unless $file and -f $file;

        # return if it's been wrapped already
        if ( -l $file ) {
            $self->log->warn(
                "seems $file has been already wrapped, skipping\n");
            return;
        }

        my $dir = ( splitdir($File::Find::dir) )[-1];
        mkdir catfile( $self->install_base,       "$dir-wrapped" )
          unless -d catfile( $self->install_base, "$dir-wrapped" );

        if ( -e catfile( $self->install_base, "$dir-wrapped", $file ) ) {
            $self->log->warn( 'found old '
                  . catfile( $self->install_base, "$dir-wrapped", $file )
                  . ', deleting'
                  . "\n" );
            unlink catfile( $self->install_base, "$dir-wrapped", $file );
        }

        my $type;
        if ( -T $file ) {
            open my $fh, '<', $file or confess "can't open $file: $!";
            my $shebang = <$fh>;
            my $base    = quotemeta $self->install_base;
            my $perl    = quotemeta $self->perl;

            return unless $shebang;
            if ( $shebang =~ m{$perl} ) {
                $type = 'perl';
            }
            elsif (
                $shebang =~ m{$base(?:/|\\)(?:s?bin)(?:/|\\)(\w+)
                |\benv\s+(\w+)}x
              )
            {
                $type = $1 || $2;
            }
        }

        move( $file => catfile( $self->install_base, "$dir-wrapped" ) )
          or confess $!;

    # if we have this $type(e.g. perl) installed and have that specific wrapper,
    # then link to it, else link to the normal one
        if (   $type
            && -e catfile( '..', 'bin', $type )
            && -e catfile( '..', 'etc', "shipwright-$type-wrapper" ) )
        {
            symlink catfile( '..', 'etc', "shipwright-$type-wrapper" ) => $file
              or confess $!;
        }
        else {

            symlink catfile( '..', 'etc', 'shipwright-script-wrapper' ) => $file
              or confess $!;
        }
    };

    my @dirs =
      grep { -d $_ }
      map { catfile( $self->install_base, $_ ) } qw/bin sbin/;
    find( $sub, @dirs ) if @dirs;
}

# substitute template string, now only support %%PERL%% and %%INSTALL_BASE%%

sub _substitute {
    my $self = shift;
    my $text = shift;

    return unless $text;

    my $perl          = $self->perl;
    my $perl_archname = `$perl -MConfig -e 'print \$Config{archname}'`;
    my $install_base  = $self->install_base;
    $text =~ s/%%PERL%%/$perl/g;
    $text =~ s/%%PERL_ARCHNAME%%/$perl_archname/g;
    $text =~ s/%%INSTALL_BASE%%/$install_base/g;
    return $text;
}

=head2 test

run the commands in t/test

=cut

sub test {
    my $self = shift;

    my @cmds = read_file( catfile( 't', 'test' ) );
    chomp @cmds;
    @cmds = map { $self->_substitute($_) } @cmds;
    $self->log->info('run tests:');

    for (@cmds) {
        my ( $type, $cmd );
        next unless /\S/;

        if (/^(\S+):\s*(.*)/) {
            $type = $1;
            $cmd  = $2;
        }
        else {
            $type = '';
            $cmd  = $_;
        }
        $self->log->info("run tests $type:");
        if ( system($cmd) ) {
            $self->log->error("tests failed");
            confess;
        }
    }
}

# record the installed dist, so we don't need to installed it later
# if at the same install_base

sub _record {
    my $self = shift;
    my $dist = shift;

    push @$installed, $dist;
    Shipwright::Util::DumpFile( $installed_file, $installed );
}

1;

__END__

=head1 NAME

Shipwright::Build - builder part

=head1 DESCRIPTION



=head1 INTERFACE



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


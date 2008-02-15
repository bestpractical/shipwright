package Shipwright::Build;

use warnings;
use strict;
use Carp;

use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(
    qw/install_base perl build_base skip_test commands log
      skip only_test force order/
);

use File::Spec;
use File::Temp qw/tempdir/;
use File::Copy::Recursive qw/dircopy/;
use File::Copy qw/move copy/;
use File::Find qw/find/;
use File::Slurp;

=head2 new

=cut

sub new {
    my $class = shift;
    my $self  = {@_};
    bless $self, $class;

    $self->log( Log::Log4perl->get_logger( ref $self ) );

    $self->{build_base} =
      File::Spec->catfile( tempdir( CLEANUP => 0 ), 'build' );

    unless ( $self->install_base ) {
        $self->install_base( tempdir( CLEANUP => 0 ) );
    }

    no warnings 'uninitialized';

    $ENV{DYLD_LIBRARY_PATH} =
      File::Spec->catfile( $self->install_base, 'lib' ) . ':'
      . $ENV{DYLD_LIBRARY_PATH};
    $ENV{LD_LIBRARY_PATH} =
      File::Spec->catfile( $self->install_base, 'lib' ) . ':'
      . $ENV{LD_LIBRARY_PATH};
    $ENV{PERL5LIB} =
        File::Spec->catfile( $self->install_base, 'lib', 'perl5', 'site_perl' )
      . ':'
      . File::Spec->catfile( $self->install_base, 'lib', 'perl5' ) . ':'
      . $ENV{PERL5LIB};
    $ENV{PATH} =
        File::Spec->catfile( $self->install_base, 'bin' ) . ':'
      . File::Spec->catfile( $self->install_base, 'sbin' ) . ':'
      . $ENV{PATH};
    $ENV{PERL_MM_USE_DEFAULT} = 1;

    require CPAN;
    eval { require CPAN::Config; }
      or warn("can't require CPAN::Config: $@");

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

    mkdir $self->install_base unless -e $self->install_base;

    chdir $self->build_base;

    if ( $self->only_test ) {
        $self->test;
    }
    else {
        dircopy( 'etc', File::Spec->catfile( $self->install_base, 'etc' ) );

        $self->order(
            Shipwright::Util::LoadFile(
                File::Spec->catfile( 'shipwright', 'order.yml' )
            )
        );

        for my $dist ( @{ $self->order } ) {
            unless ( $self->skip && $self->skip->{$dist} ) {
                $self->_install($dist);
            }
            chdir $self->build_base;
        }

        $self->_wrapper();

        $self->log->info(
            "install finished. the dists are at " . $self->install_base );
    }

}

# install one dist, the install methods are in scripts/distname/build

sub _install {
    my $self = shift;
    my $dir  = shift;

    my @cmds = read_file( File::Spec->catfile( 'scripts', $dir, 'build' ) );
    chomp @cmds;
    @cmds = map { $self->_substitute($_) } @cmds;

    chdir File::Spec->catfile( 'dists', $dir );

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

        next if $type eq 'clean'; # don't need to clean when install
        if ( $self->skip_test && $type eq 'test' ) {
            $self->log->info("skip build $type part in $dir");
            next;
        }

        $self->log->info("build $type part in $dir");

        if ( system($cmd) ) {
            $self->log->error("build $dir with failure when run $type: $!");
            if ( $self->force && $type eq 'error' ) {
                $self->log->error(
"although tests failed, will install anyway since we have force arg\n"
                );
            }
            else {
                die "install failed";
            }
        }
    }

    $self->log->info("build $dir with success!");
}

# wrap the bin files, mainly for ENV
sub _wrapper {
    my $self = shift;

    my %seen;

    my $sub = sub {
        my $file = $_;
        return unless $file and -f $file;
        return if $seen{$File::Find::name}++;
        my $dir = ( File::Spec->splitdir($File::Find::dir) )[-1];
        mkdir File::Spec->catfile( $self->install_base,       "$dir-wrapped" )
          unless -d File::Spec->catfile( $self->install_base, "$dir-wrapped" );

        my $type;
        if ( -T $file ) {
            open my $fh, '<', $file or die "can't open $file: $!";
            my $shebang = <$fh>;
            my $base    = quotemeta $self->install_base;
            my $perl    = quotemeta $self->perl || $^X;

            if ( $shebang =~ m{$perl} ) {
                $type = 'perl';
            }
            elsif (
                $shebang =~ m{$base(?:/|\\)(?:s?bin|libexec)(?:/|\\)(\w+)
                |\benv\s+(\w+)}x
              )
            {
                $type = $1 || $2;
            }
        }

        move(
            $file => File::Spec->catfile( $self->install_base, "$dir-wrapped" )
        ) or die $!;

    # if we have this $type(e.g. perl) installed and have that specific wrapper,
    # then link to it, else link to the normal one
        if (   $type
            && grep( { $_ eq $type } @{ $self->order } )
            && !( $self->skip && $self->skip->{$type} )
            && -e File::Spec->catfile( '..', 'etc', "shipwright-$type-wrapper" )
          )
        {
            symlink File::Spec->catfile( '..', 'etc',
                "shipwright-$type-wrapper" ) => $file
              or die $!;
        }
        else {

            symlink File::Spec->catfile( '..', 'etc',
                'shipwright-script-wrapper' ) => $file
              or die $!;
        }
    };

    my @dirs =
      grep { -d $_ }
      map { File::Spec->catfile( $self->install_base, $_ ) }
      qw/bin sbin libexec/;
    find( $sub, @dirs ) if @dirs;
}

# substitute template string, now only support %%PERL%% and %%INSTALL_BASE%%

sub _substitute {
    my $self = shift;
    my $text = shift;

    return unless $text;

    my $perl          = $self->perl || $^X;
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

    my @cmds = read_file( File::Spec->catfile( 't', 'test' ) );
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
            die;
        }
    }
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


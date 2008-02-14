package Shipwright::Backend;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;

=head2 new

accept the backend part in config as args.
e.g ( module => 'SVK', project => 'test', ... )
returns the the individual Backend object.

=cut

sub new {
    my $class = shift;
    my %args  = @_;

    my $module;

    if ( $args{repository} =~ m{^\s*(svk:|//)} ) {
        $args{repository} =~ s{^\s*svk:}{};
        $module = 'Shipwright::Backend::SVK';
    }
    elsif ( $args{repository} =~ m{^\s*svn[:+]} ) {
        $args{repository} =~ s{^\s*svn:(?!//)}{};
        $module = 'Shipwright::Backend::SVN';
    }
    else {
        croak "invalid repository: $args{repository}\n";
    }

    $module->require or die $@;

    return $module->new(%args);
}

my %scripts = (
    wrapper => <<'EOF'
#!/bin/sh
if [ -z `which readlink` ]; then  
    # if we don't have readlink, we're on some pitiful platform like solaris
    test -h $0 && LINK=`ls -l $0 | awk -F\>  '{print $NF}'`
else
    LINK=`readlink $0`
fi

if [ "$LINK" = '' ] || [ $LINK = '../etc/shipwright-script-wrapper' ]; then
    BASE=$0
    BASE_DIR=`dirname "$BASE"`
    BASE_DIR=` (cd "$BASE_DIR"; pwd) `
    FILENAME=`basename "$BASE"`
    WRAPPED_DIR=`basename "$BASE_DIR"`
    PERL5LIB=${BASE_DIR}/../lib/perl5/site_perl:${BASE_DIR}/../lib/perl5:${PERL5LIB}\
        LD_LIBRARY_PATH=${BASE_DIR}/../lib:${LD_LIBRARY_PATH}\
        DYLD_LIBRARY_PATH=${BASE_DIR}/../lib:${DYLD_LIBRARY_PATH}\
        exec ${BASE_DIR}/../${WRAPPED_DIR}-wrapped/${FILENAME}  "$@"
else
    exec $LINK "$@"
fi
EOF
    ,
    perl_wrapper => <<'EOF'
#!/bin/sh
if [ -z `which readlink` ]; then  
    # if we don't have readlink, we're on some pitiful platform like solaris
    test -h $0 && LINK=`ls -l $0 | awk -F\>  '{print $NF}'`
else
    LINK=`readlink $0`
fi

if [ "$LINK" = '' ] || [ $LINK = '../etc/shipwright-perl-wrapper' ]; then
    BASE=$0
    BASE_DIR=`dirname "$BASE"`
    BASE_DIR=` (cd "$BASE_DIR"; pwd) `
    FILENAME=`basename "$BASE"`
    WRAPPED_DIR=`basename "$BASE_DIR"`
    PERL5LIB=${BASE_DIR}/../lib/perl5/site_perl:${BASE_DIR}/../lib/perl5:${PERL5LIB}\
        LD_LIBRARY_PATH=${BASE_DIR}/../lib:${LD_LIBRARY_PATH}\
        DYLD_LIBRARY_PATH=${BASE_DIR}/../lib:${DYLD_LIBRARY_PATH}\
        exec ${BASE_DIR}/../${WRAPPED_DIR}-wrapped/perl ${BASE_DIR}/../${WRAPPED_DIR}-wrapped/${FILENAME}  "$@"
else
    exec $LINK "$@"
fi
EOF
    ,
    utility => <<'EOF'
#!/usr/bin/env perl
use strict;
use warnings;

use Getopt::Long;
use YAML::Syck;

my %args;
GetOptions( \%args, 'update-order', 'keep-requires=s', 'keep-recommends=s',
    'keep-build-requires=s', 'for-dists=s', 'help' );

my $USAGE = <<'END'
run: ./bin/shipwright-utility --update-order

options: 

help: print this usage

update-order: regenerate install order.
    sub options:
        keep-requires: keep dists with requires dep type. default is true.
        keep-recommends: keep dists with recommends dep type. default is true.
        keep-build-requires: keep dists with build-requires dep type. default is true.
        for-dists: make order only for these dists, seperated by comma.
        default is for all the dists in the source.

    e.g. --update-order --keep-recommends 0 --for-dists Jifty-DBI,Jifty

END
;

if ( $args{'help'} ) { 
    print $USAGE;
    exit 0;
}
if ( $args{'update-order'} ) {
    for ( 'keep-requires', 'keep-recommends', 'keep-build-requires' ) {
        $args{$_} = 1 unless defined $args{$_}; 
    }

    my @dists = split /,\s*/, $args{'for-dists'};
    unless (@dists) {
        my $out = `ls scripts`;
        my $sep = $/;
        @dists = split /$sep/, $out;
        chomp @dists;
        s{/$}{} for @dists;
    }

    my $require = {};

    for (@dists) {
        fill_deps( %args, require => $require, dist => $_ );
    }

    require Algorithm::Dependency::Ordered;
    require Algorithm::Dependency::Source::HoA;

    my $source = Algorithm::Dependency::Source::HoA->new($require);
    $source->load();
    my $dep = Algorithm::Dependency::Ordered->new( source => $source, )
      or die $@;
    my $order = $dep->schedule_all();
    DumpFile( 'shipwright/order.yml', $order );
}

sub fill_deps {
    my %args    = @_;
    my $require = $args{require};
    my $dist    = $args{dist};

    my $string;
    my $req = LoadFile("scripts/$dist/require.yml");

    if ( $req->{requires} ) {
        for (qw/requires recommends build_requires/) {
            my $arg = "keep-$_";
            $arg =~ s/_/-/g;
            push @{ $require->{$dist} }, keys %{ $req->{$_} }
              if $args{$arg};
        }
    }
    else {

        #for back compatbility
        push @{ $require->{$dist} }, keys %$req;
    }

    for my $dep ( @{ $require->{$dist} } ) {
        next if $require->{$dep};
        fill_deps( %args, dist => $dep );
    }
}

EOF
    ,
    builder => <<'EOF'
#!/usr/bin/env perl
use warnings;
use strict;

use File::Spec;
use File::Temp qw/tempdir/;
use File::Copy qw/move copy/;
use File::Find qw/find/;
use Config;
use Getopt::Long;
use Cwd;

my $build_base = getcwd;


my %args;
GetOptions(
    \%args,      'install-base=s', 'perl=s', 'skip=s',
    'skip-test', 'only-test',      'force',  'clean',
    'project-name', 'help',
);

my $USAGE = <<'END'
run: ./bin/shipwright-builder

options: 

help: print this usage

install-base: where we will install
    defaults: a temp dir below your system's tmp.
    e.g. --install-base /home/local/mydist

perl: which perl to use for the to be installed dists. 
    defaults: if we have perl in the source, it will use that one.
              else, it will use the one which runs this builder script.
    e.g. --perl /usr/bin/perl

skip: dists we don't want to install, comma seperated. 
    e.g. --skip perl,Module-Build

skip-test: skip test part if there're

force: if tests fail, install anyway

only-test: test for the installed dists.
    it's used to be sure everything is ok after we install with success. 
    need to specify --install-base if nothing find in __install_base.

clean: clean the source

END
  ;

if ( $args{'help'} ) {
    print $USAGE;
    exit 0;
}


$args{skip} = [ split /,\s*/, $args{skip} || '' ];

my $order = parse_order( File::Spec->catfile( 'shipwright', 'order.yml' ) );

my $log;

if ( $args{'only-test'} ) {
    open $log, '>', 'test.log' or die $!;

    $args{'install-base'} = get_install_base() unless $args{'install-base'}; 
    test();
}
elsif ( $args{'clean'} ) {
    open $log, '>', 'clean.log' or die $!;

    $args{'install-base'} = get_install_base() unless $args{'install-base'};
    unless ( $args{perl} ) {
        if ( -e File::Spec->catfile( $args{'install-base'}, 'bin', 'perl' ) ) {
            $args{perl} =
              File::Spec->catfile( $args{'install-base'}, 'bin', 'perl' );
        }
        else {
            $args{perl} = $^X;
        }
    }

    for my $dist (@$order) {
        unless ( grep { $dist eq $_ } @{ $args{skip} } ) {
            clean($dist);
        }
        chdir $build_base;
    }
}
else {
    # for install
    open $log, '>', 'build.log' or die $!;

    require CPAN;
    eval { require CPAN::Config } or warn "can't require CPAN::Config: $@";

    # we don't want any prereqs any more!
    {
        no warnings 'once';
        $CPAN::Config->{prerequisites_policy} = 'ignore';
    }

    my $project_name = $args{'project-name'};
    ($project_name) = $build_base =~ /([-.\w]+)$/ unless $project_name;

    unless ( $args{'install-base'} ) {
        my $dir = tempdir( $project_name . '-XXXXXX', DIR => '/tmp' );
        $args{'install-base'} = File::Spec->catfile( $dir, $project_name );

        print $log
          "no default install-base, will set it to $args{'install-base'}\n";
    }

    open my $fh, '>', '__install_base'
      or die "can't write to __install_base: $!";
    print $fh $args{'install-base'};
    close $fh;

    unless ( $args{perl} ) {
        if ( ( grep { $_ eq 'perl' } @$order )
            && !( grep { $_ eq 'perl' } @{ $args{skip} } ) )
        {
            $args{perl} =
              File::Spec->catfile( $args{'install-base'}, 'bin', 'perl' );
        }
        else {
            $args{perl} = $^X;
        }
    }

    {
        no warnings 'uninitialized';
        $ENV{DYLD_LIBRARY_PATH} =
          File::Spec->catfile( $args{'install-base'}, 'lib' ) . ':'
          . $ENV{DYLD_LIBRARY_PATH};
        $ENV{LD_LIBRARY_PATH} =
          File::Spec->catfile( $args{'install-base'}, 'lib' ) . ':'
          . $ENV{LD_LIBRARY_PATH};
        $ENV{PERL5LIB} =
          File::Spec->catfile( $args{'install-base'}, 'lib', 'perl5',
            'site_perl' )
          . ':'
          . File::Spec->catfile( $args{'install-base'}, 'lib', 'perl5' ) . ':'
          . $ENV{PERL5LIB};
        $ENV{PATH} =
            File::Spec->catfile( $args{'install-base'}, 'bin' ) . ':'
          . File::Spec->catfile( $args{'install-base'}, 'sbin' ) . ':'
          . $ENV{PATH};
        $ENV{PERL_MM_USE_DEFAULT} = 1;
    }

    mkdir $args{'install-base'} unless -e $args{'install-base'};

    mkdir File::Spec->catfile( $args{'install-base'},       'etc' )
      unless -e File::Spec->catfile( $args{'install-base'}, 'etc' );
    mkdir File::Spec->catfile( $args{'install-base'},       'tools' )
      unless -e File::Spec->catfile( $args{'install-base'}, 'tools' );

    for ( 'shipwright-script-wrapper', 'shipwright-perl-wrapper' ) {
        copy( File::Spec->catfile( 'etc', $_ ),
            File::Spec->catfile( $args{'install-base'}, 'etc', $_ ) );
    }

    for ( 'shipwright-utility', 'shipwright-source-bash',
        'shipwright-source-tcsh' )
    {
        copy( File::Spec->catfile( 'etc', $_ ),
            File::Spec->catfile( $args{'install-base'}, 'tools', $_ ) );
    }

    chmod 0755,
      File::Spec->catfile( $args{'install-base'}, 'tools',
        'shipwright-utility' );

    for my $dist (@$order) {
        unless ( grep { $dist eq $_ } @{ $args{skip} } ) {
            install($dist);
        }
        chdir $build_base;
    }

    mkdir File::Spec->catfile( $args{'install-base'},       'bin' )
      unless -e File::Spec->catfile( $args{'install-base'}, 'bin' );

    wrap_bin();
    print "install finished, the dists are at $args{'install-base'}\n";
    print $log "install finished, the dists are at $args{'install-base'}\n";
}

sub install {
    my $dir = shift;

    my $cmds = cmds(File::Spec->catfile( 'scripts', $dir, 'build' ));

    chdir File::Spec->catfile( 'dists', $dir );

    for (@$cmds) {
        my ( $type, $cmd ) = @$_;
        next if $type eq 'clean';

        if ( $args{'skip-test'} && $type eq 'test' ) {
            print $log "skip build $type part in $dir\n";
            next;
        }

        print $log "build $type part in $dir with cmd: $cmd\n";

        print "we'll run the cmd: $cmd\n";
        if ( system($cmd) ) {
            print $log "build $dir $type part with failure: $!\n";
            if ( $args{force} && $type eq 'test' ) {
                print $log
"although tests failed, will install anyway since we have force arg\n";
            }
            else {
                die "build $dir $type part with failure: $!\n";
            }
        }
        else {
            print $log "build $dir $type part with success!\n";
        }
    }

    print $log "build $dir with success!\n";
}

sub wrap_bin {
    my $self = shift;

    my %seen;

    my $sub = sub {
        my $file = $_;
        return unless $file and -f $file;
        return if $seen{$File::Find::name}++;
        my $dir = ( File::Spec->splitdir($File::Find::dir) )[-1];
        mkdir File::Spec->catfile( $args{'install-base'}, "$dir-wrapped" )
          unless -d File::Spec->catfile( $args{'install-base'},
            "$dir-wrapped" );

        my $type;
        if ( -T $file ) {
            open my $fh, '<', $file or die "can't open $file: $!";
            my $shebang = <$fh>;
            if (
                $shebang =~ m{
\Q$args{'install-base'}\E(?:/|\\)(?:s?bin|libexec)(?:/|\\)(\w+)
|\benv\s+(\w+)
}x
              )
            {
                $type = $1 || $2;
            }
        }

        move( $file =>
              File::Spec->catfile( $args{'install-base'}, "$dir-wrapped" ) )
          or die $!;

    # if we have this $type(e.g. perl) installed and have that specific wrapper,
    # then link to it, else link to the normal one
        if (   $type
            && grep( { $_ eq $type } @$order )
            && !( grep { $_ eq $type } @{ $args{skip} } ) 
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
        chmod 0755, $file;
    };

    my @dirs =
      grep { -d $_ }
      map { File::Spec->catfile( $args{'install-base'}, $_ ) }
      qw/bin sbin libexec/;
    find( $sub, @dirs ) if @dirs;

}

sub substitute {
    my $text = shift;
    return unless $text;

    my $perl          = $args{'perl'} || $^X;
    my $perl_archname = `$perl -MConfig -e 'print \$Config{archname}'`;
    my $install_base  = $args{'install-base'};
    $text =~ s/%%PERL%%/$perl/g;
    $text =~ s/%%PERL_ARCHNAME%%/$perl_archname/g;
    $text =~ s/%%INSTALL_BASE%%/$install_base/g;
    return $text;
}

sub parse_order {
    my $file  = shift;
    my $order = [];
    open my $fh, '<', $file or die $!;
    while (<$fh>) {
        if (/^- (\S+)/) {
            push @$order, $1;
        }
    }
    return $order;
}

sub test {

    my $cmds = cmds(File::Spec->catfile( 't', 'test' ));

    for (@$cmds) {
        my ( $type, $cmd ) = @$_;
        print $log "run tests $type part with cmd: $cmd\n";
        if ( system($cmd ) ) {
            die "something wrong when execute $cmd: $?";
        }
        else {
            print $log "run test $type part with success\n";
        }
    }
    print $log "run tests with success\n";
}

sub cmds {
    my $file = shift;

    my @cmds;


    {
        open my $fh, '<', $file or die $!;
        @cmds = <$fh>;
        close $fh;
        chomp @cmds;
        @cmds = map { substitute($_) } @cmds;
    }

    my $return = [];
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
        push @$return, [ $type, $cmd ];
    }

    return $return;
}

sub clean {
    my $dir = shift;

    my $cmds = cmds(File::Spec->catfile( 'scripts', $dir, 'build' ));

    chdir File::Spec->catfile( 'dists', $dir );

    for (@$cmds) {
        my ( $type, $cmd ) = @$_;
        next unless $type eq 'clean';

        if ( system($cmd) ) {
            print $log "clean $dir with failure: $!\n";
        }
        else {
            print $log "clean $dir with success $!\n";
        }
    }
}

sub get_install_base {
    if ( open my $fh, '<', '__install_base' ) {
        my $install_base = <$fh>;
        close $fh;
        chomp $install_base;
        return $install_base;
    }
    else {
        warn
"can't find install-base automatically, you need to specify it manually.\n";
    }

}
EOF
    ,
    installed_utility => <<'EOF'
#!/usr/bin/env perl 
use strict;
use warnings;

use Getopt::Long;
use File::Spec;
use Cwd;

my %args;
GetOptions( \%args, 'install-links=s', 'help' );

my $USAGE = <<'END'
run: ./tools/shipwright-utility --install-links

options: 

help: print this usage

install-links: link files in bin, sbin, or libexec to other places
    e.g. --install-links /usr/local

END
  ;

if ( $args{'help'} ) {
    print $USAGE;
}
elsif ( $args{'install-links'} ) {
    my $cwd = getcwd();

    for my $dir (qw/bin sbin libexec/) {
        next unless -e $dir;
        my $dh;
        opendir $dh, $dir or die $!;

        mkdir File::Spec->catfile( $args{'install-links'},       $dir )
          unless -e File::Spec->catfile( $args{'install-links'}, $dir );
        my @files = readdir $dh;
        for (@files) {
            next if $_ eq '.' || $_ eq '..';
            symlink File::Spec->catfile( $cwd, $dir, $_ ),
              File::Spec->catfile( $args{'install-links'}, $dir, $_ ) or die
                  $!;
        }
    }
}

EOF
    ,
    source_bash => <<'EOF'
#!/usr/bin/env bash
if [ $# = 1 ] || [ "$SHIPENV" != '' ]; then
    if [ "$1" ]; then
        BASENAME=$1;
    else
        DIRNAME=`dirname $SHIPENV`;
        BASENAME="$DIRNAME/.."
    fi

    export PATH=$BASENAME/bin:$PATH
    export PERL5LIB=$BASENAME/lib/perl5/site_perl:$BASENAME/lib/perl5:${PERL5LIB}
    export DYLD_LIBRARY_PATH=$BASENAME/lib:${DYLD_LIBRARY_PATH}
else
    echo 'USAGE: source shipwright-source-bash BASEPATH'
fi
EOF
    ,
    source_tcsh => <<'EOF'
#!/usr/bin/env tcsh
if ( "$1" != '' || $?SHIPENV ) then

    if ( $1 != '' ) then
        set BASENAME = $1;
    else
        set DIRNAME = `dirname $SHIPENV`;
        set BASENAME = "$DIRNAME/.."
    endif

    if ( $?PATH ) then
        setenv PATH $BASENAME/bin:$PATH
    else
        setenv PATH $BASENAME/bin
    endif

    if ( $?PERL5LIB ) then
        setenv PERL5LIB $BASENAME/lib/perl5/site_perl:$BASENAME/lib/perl5:$PERL5LIB
    else
        setenv PERL5LIB $BASENAME/lib/perl5/site_perl:$BASENAME/lib/perl5
    endif

    if ( $?LD_LIBRARY_PATH ) then
        setenv LD_LIBRARY_PATH $BASENAME/lib:$LD_LIBRARY_PATH
    else
        setenv LD_LIBRARY_PATH $BASENAME/lib
    endif
    
    if ( $?DYLD_LIBRARY_PATH ) then
        setenv DYLD_LIBRARY_PATH $BASENAME/lib:$DYLD_LIBRARY_PATH
    else
        setenv DYLD_LIBRARY_PATH $BASENAME/lib
    endif
else
    echo 'USAGE: source shipwright-source-tcsh BASEPATH'
endif
EOF
    ,
    null => '',
);

=head2 make_script

help method to get scripts

=cut

sub make_script {
    my $self = shift;
    my $type = shift || 'null';
    return $scripts{$type};
}

1;

__END__

=head1 NAME

Shipwright::Backend - backend part

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


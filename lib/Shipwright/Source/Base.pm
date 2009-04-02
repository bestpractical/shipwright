package Shipwright::Source::Base;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile catdir/;
use File::Slurp;
use Module::CoreList;
use Shipwright::Source;
use Shipwright::Util;
use Cwd qw/getcwd/;

use base qw/Class::Accessor::Fast/;
__PACKAGE__->mk_accessors(
    qw/source directory scripts_directory download_directory follow
      min_perl_version map_path skip map skip_recommends skip_all_recommends
      include_dual_lifed
      keep_build_requires name log url_path version_path branches_path version/
);

=head1 NAME

Shipwright::Source::Base - Base class of source

=head1 SYNOPSIS

=head1 METHODS

=head2 new

=cut

sub new {
    my $class = shift;
    my $self  = {@_};
    bless $self, $class;
    $self->log( Log::Log4perl->get_logger( ref $self ) );
    return $self;
}

=head2 run

=cut

sub run {
    my $self = shift;
    my %args = @_;
    for ( $self->_cmd ) {
        if ( ref $_ eq 'CODE' ) {
            $_->();
        }
        else {
            Shipwright::Util->run($_);
        }
    }
    $self->_copy( %{ $args{copy} } ) if $args{copy};
}

# you should subclass this method.
sub _cmd { }

sub _follow {
    my $self         = shift;
    my $path         = shift;
    my $cwd          = getcwd;
    my $require_path = catfile( $path, '__require.yml' );
    my $map          = {};
    my $url          = {};


    unless ( $self->min_perl_version ) {
        no warnings 'once';
        require Config;
        require version;
        my $version = version->new( $Config::Config{version} );
        $self->min_perl_version( $version->numify );
    }

    if ( -e $self->map_path ) {
        $map = Shipwright::Util::LoadFile( $self->map_path );
    }

    if ( -e $self->url_path ) {
        $url = Shipwright::Util::LoadFile( $self->url_path );
    }

    my @types = qw/requires build_requires/;

    my $reverse_map = { reverse %$map };
    my $skip_recommends = $self->skip_recommends->{ $self->name }
      || ( $reverse_map->{ $self->name }
        && $self->skip_recommends->{ $reverse_map->{ $self->name } } )
      || $self->skip_all_recommends;
    push @types, 'recommends' unless $skip_recommends;

    if ( !-e $require_path ) {

        # if not found, we'll create one according to Build.PL or Makefile.PL
        my $require = {};
        chdir catdir($path);

        if ( $path =~ /\bcpan-Bundle-(.*)/ ) {

            my $file = $1;
            $file =~ s!-!/!;
            $file .= '.pm';

            # so it's a bundle module
            open my $fh, '<', 'MANIFEST' or confess "no manifest found: $!";
            while (<$fh>) {
                chomp;
                if (/$file/) {
                    $file = $_;
                    last;
                }
            }
            open $fh, '<', $file or confess "can't open $file: $!";
            my $flip;
            while (<$fh>) {
                chomp;
                next if /^\s*$/;

                if (/^=head1\s+CONTENTS/) {
                    $flip = 1;
                    next;
                }
                elsif (/^=(?!head1\s+CONTENTS)/) {
                    $flip = 0;
                }

                next unless $flip;
                my $info;
                if (/(.*?)-/) {

                    # things following '-' are comments which we don't want here
                    $info = $1;
                }
                else {
                    $info = $_;
                }
                my ( $module, $version ) = split /\s+/, $info;
                $require->{requires}{$module} = $version || 0;
            }

        }
        elsif ( -e 'Build.PL' ) {
            Shipwright::Util->run(
                [
                    $^X,               '-Mversion',
                    '-MModule::Build', '-MShipwright::Util::CleanINC',
                    'Build.PL'
                ],
                1, # don't die if this fails
            );
            Shipwright::Util->run( [ $^X, 'Build.PL' ] );
            my $source = read_file( catfile( '_build', 'prereqs' ) )
              or confess "can't read _build/prereqs: $!";
            my $eval = '$require = ' . $source;
            eval $eval or confess "eval error: $@";    ## no critic

            $source = read_file( catfile('Build.PL') )
              or confess "can't read Build.PL: $!";

            Shipwright::Util->run(
                [ './Build', 'realclean', '--allow_mb_mismatch', 1 ] );
        }
        elsif ( -e 'Makefile.PL' ) {
            my $makefile = read_file('Makefile.PL')
              or confess "can't read Makefile.PL: $!";

            if ( $makefile =~ /inc::Module::Install/ ) {

  # PREREQ_PM in Makefile is not good enough for inc::Module::Install, which
  # will omit features(..). we'll put deps in features(...) into recommends part

                $makefile =~ s/^\s*requires(?!\w)/shipwright_requires/mg;
                $makefile =~
                  s/^\s*build_requires(?!\w)/shipwright_build_requires/mg;
                $makefile =~
                  s/^\s*test_requires(?!\w)/shipwright_test_requires/mg;
                $makefile =~ s/^\s*recommends(?!\w)/shipwright_recommends/mg;
                $makefile =~ s/^\s*features(?!\w)/shipwright_features/mg;
                $makefile =~ s/^\s*feature(?!\w)/shipwright_feature/mg;
                my $shipwright_makefile = <<'EOF';
my $shipwright_req = {};

sub _shipwright_requires {
    my $type = shift;
    my %req  = @_;
    for my $name ( keys %req ) {
        $shipwright_req->{$type}{$name} = $req{$name};
    }
}

sub shipwright_requires {
    _shipwright_requires( 'requires', @_ == 1 ? ( @_, 0 ) : @_ );
    goto &requires;
}

sub shipwright_build_requires {
    _shipwright_requires( 'build_requires', @_ == 1 ? ( @_, 0 ) : @_ );
    goto &build_requires;
}

sub shipwright_test_requires {
    _shipwright_requires( 'build_requires', @_ == 1 ? ( @_, 0 ) : @_ );
    goto &test_requires;
}

sub shipwright_recommends {
    _shipwright_requires( 'recommends', @_ == 1 ? ( @_, 0 ) : @_ );
    goto &recommends;
}

sub shipwright_feature {
    my $name = shift;
    my @mods = @_;
    for ( my $i = 0 ; $i < @mods ; $i++ ) {
        if ( $mods[$i] eq '-default' ) {
            $i++;    # skip the -default value
        }
        elsif ( $mods[ $i + 1 ] =~ /^[\d\.]*$/ ) {

            # index $i+1 is a version
            $shipwright_req->{recommends}{ $mods[$i] } = $mods[ $i + 1 ] || 0;
            $i++;
        }
        else {
            $shipwright_req->{recommends}{ $mods[$i] } = 0;
        }
    }
    goto &feature;
}

sub shipwright_features {
    my @args = @_;
    while ( my ( $name, $mods ) = splice( @_, 0, 2 ) ) {
        for ( my $i = 0; $i < @$mods; $i++ ) {
            if ( $mods->[$i] eq '-default' ) {
                $i++;
                next;
            }

            if ( ref $mods->[$i] eq 'ARRAY' ) {
# this happends when
# features(
#     'Date loading' => [
#         -default => 0,
#        recommends( 'DateTime' )
#     ],
# );
               for ( my $j = 0; $j < @{$mods->[$i]}; $j++ ) {
                    if ( ref $mods->[$i][$j] eq 'ARRAY' ) {
                        $shipwright_req->{recommends}{$mods->[$i][$j][0]} 
                            = $mods->[$i][$j][1] || 0;
                    }
                    elsif ( $mods->[$i][$j+1] =~ /^[\d\.]*$/ ) {
                        $shipwright_req->{recommends}{$mods->[$i][$j]} 
                            = $mods->[$i][$j+1] || 0;
                        $j++;
                    }
                    else {
                        $shipwright_req->{recommends}{$mods->[$i][$j]} = 0;
                    }
                }
                
                next;
            }

            if ( $mods->[$i+1] =~ /^[\d\.]*$/ ) {
                # index $i+1 is a version
                $shipwright_req->{recommends}{$mods->[$i]} = $mods->[$i+1] || 0;
                $i++;
            }
            else {
                $shipwright_req->{recommends}{$mods->[$i]} = 0;
            }
        }
    }
    
    goto &features;
}

END {
require Data::Dumper;
open my $tmp_fh, '>', 'shipwright_prereqs';
print $tmp_fh Data::Dumper->Dump( [$shipwright_req], [qw/require/] );
}

EOF

                $shipwright_makefile .= $makefile;
                write_file( 'shipwright_makefile.pl', $shipwright_makefile );

                Shipwright::Util->run(
                    [
                        $^X,
                        '-Mversion',
                        '-MShipwright::Util::CleanINC',
                        'shipwright_makefile.pl'
                    ],
                    1, # don't die if this fails
                );
                Shipwright::Util->run( [ $^X, 'shipwright_makefile.pl' ] )
                  if $?;
                my $prereqs = read_file( catfile('shipwright_prereqs') )
                  or confess "can't read prereqs: $!";
                eval $prereqs or confess "eval error: $@";    ## no critic

                Shipwright::Util->run( [ 'rm', 'shipwright_makefile.pl' ] );
                Shipwright::Util->run( [ 'rm', 'shipwright_prereqs' ] );
            }
            else {

                # we extract the deps from Makefile
                Shipwright::Util->run(
                    [
                        $^X,
                        '-MShipwright::Util::CleanINC',
                        'Makefile.PL'
                    ],
                    1, # don't die if this fails
                );
                Shipwright::Util->run(
                    [
                        $^X,
                        'Makefile.PL'
                    ]
                ) if $?;

                my ($source) = grep { /PREREQ_PM/ } read_file('Makefile');
                if ( $source && $source =~ /({.*})/ ) {
                    my $eval .= '$require = ' . $1;
                    $eval =~ s/([\w:]+)=>/'$1'=>/g;
                    eval $eval or confess "eval error: $@";    ## no critic
                }

                for ( keys %$require ) {
                    $require->{requires}{$_} = delete $require->{$_};
                }

            }
            Shipwright::Util->run( [ 'make', 'clean' ] );
            Shipwright::Util->run( [ 'rm',   'Makefile.old' ] );
        }

        for my $type ( @types ) {
            for my $module ( keys %{ $require->{$type} } ) {
                $require->{$type}{$module}{version} =
                  delete $require->{$type}{$module};
            }
        }

        Shipwright::Util::DumpFile( $require_path, $require )
          or confess "can't dump __require.yml: $!";
    }

    if ( my $require = Shipwright::Util::LoadFile($require_path) ) {

       # if not have 'requires' key, all the keys in $require are supposed to be
       # requires type
        if ( !$require->{requires} ) {
            for my $module ( keys %$require ) {
                $require->{requires}{$module}{version} =
                  delete $require->{$module};
            }
        }

        for my $type ( @types ) {
            for my $module ( keys %{ $require->{$type} } ) {

#$module shouldn't be undefined, but it _indeed_ happens in reality sometimes
                next unless $module;
                # we don't want to require perl
                if ( $module eq 'perl' ) {
                    delete $require->{$type}{$module};
                    next;
                }

                if ( !$self->include_dual_lifed 
                    && Module::CoreList->first_release( $module, $require->{$type}{$module}{version} )
                    && Module::CoreList->first_release( $module, $require->{$type}{$module}{version} ) <= $self->min_perl_version)
                {
                    delete $require->{$type}{$module};
                    next;
                }

                my $name = $module;

                if ( $self->_is_skipped($module) ) {
                    unless ( defined $map->{$module}
                        || defined $url->{$module} )
                    {

                        # not in the map, meaning it's not been imported before,
                        # so it's safe to erase it
                        delete $require->{$type}{$module};
                        next;
                    }
                }
                else {

                    opendir my $dir, $self->directory;
                    my @sources = readdir $dir;
                    close $dir;

                    #reload map
                    if ( -e $self->map_path ) {
                        $map = Shipwright::Util::LoadFile( $self->map_path );
                    }

                    if ( $map->{$module} && $map->{$module} =~ /^cpan-/ ) {
                        $name = $map->{$module};
                    }
                    else {

                        # assuming it's a CPAN module
                        $name =~ s/::/-/g;
                        $name = 'cpan-' . $name unless $name =~ /^cpan-/;
                    }

                    unless ( grep { $name eq $_ } @sources ) {
                        my $s;
                        my $cwd = getcwd;
                        chdir $self->directory;
                        if (   $require->{$type}{$module}{source}
                            && $require->{$type}{$module}{source} ne 'CPAN' )
                        {
                            $s = Shipwright::Source->new(
                                %$self,
                                source  => $require->{$type}{$module}{source},
                                name    => $name,
                                version => undef,
                                _path   => undef,
                            );
                        }
                        else {
                            $s = Shipwright::Source->new(
                                %$self,
                                source  => "cpan:$module",
                                version => undef,
                                name => '',   # cpan name is automaticaly fixed.
                                _path   => undef,
                            );
                        }
                        unless ($s->run()) { 
                            # if run returns false, we should skip trying to install it.
                            # this lets us skip explicit dependencies that are actually part of the perl core
                            #delete $require->{$type}{$module};
                            chdir $cwd;
                            next;

                        }
                        chdir $cwd;
                    }

                    # reload map
                    if ( -e $self->map_path ) {
                        $map = Shipwright::Util::LoadFile( $self->map_path );
                    }

                }

                # convert required module name to dist name like cpan-Jifty-DBI
                if ( $map->{$module} && $map->{$module} =~ /^cpan-/ ) {
                    $require->{$type}{ $map->{$module} } =
                      delete $require->{$type}{$module};
                }
                else {
                    $require->{$type}{$name} =
                      delete $require->{$type}{$module};
                }
            }
        }
        # don't keep recommends info if we skip them, so we won't encounter
        # them when update later
        $require->{recommends} = {} if $skip_recommends;

        Shipwright::Util::DumpFile( $require_path, $require );
    }
    else {
        croak "invalid __require.yml in $path";
    }

    # go back to the cwd before we run _follow
    chdir $cwd;
}

sub _update_map {
    my $self   = shift;
    my $module = shift;
    my $dist   = shift;

    my $map = {};
    if ( -e $self->map_path ) {
        $map = Shipwright::Util::LoadFile( $self->map_path );
    }
    return if $map->{$module};

    $map->{$module} = $dist;
    Shipwright::Util::DumpFile( $self->map_path, $map );
}

sub _update_url {
    my $self = shift;
    my $name = shift;
    my $url  = shift;

    my $map = {};
    if ( -e $self->url_path && !-z $self->url_path ) {
        $map = Shipwright::Util::LoadFile( $self->url_path );
    }
    $map->{$name} = $url;
    Shipwright::Util::DumpFile( $self->url_path, $map );
}

sub _update_version {
    my $self    = shift;
    my $name    = shift;
    my $version = shift;

    my $map = {};
    if ( -e $self->version_path && !-z $self->version_path ) {
        $map = Shipwright::Util::LoadFile( $self->version_path );
    }
    $map->{$name} = $version;
    Shipwright::Util::DumpFile( $self->version_path, $map );
}

sub _update_branches {
    my $self     = shift;
    my $name     = shift;
    my $branches = shift;

    my $map = {};
    if ( -e $self->version_path && !-z $self->branches_path ) {
        $map = Shipwright::Util::LoadFile( $self->branches_path );
    }
    $map->{$name} = $branches;
    Shipwright::Util::DumpFile( $self->branches_path, $map );
}

sub _is_skipped {
    my $self   = shift;
    my $module = shift;
    my $skip;

    if ( $self->skip ) {
        if ( $self->skip->{$module} ) {
            $skip = 1;
        }
        elsif ( grep { /-/ } keys %{ $self->skip } ) {

       # so we have a dist skip, we need to resolve the $module to the dist name
            my $source = Shipwright::Source->new( source => "cpan:$module" );
            $source->_run;
            my $name = $source->name;
            my ($name_without_prefix) = $name =~ /^cpan-(.*)/;
            $skip = 1
              if $self->skip->{$name} || $self->skip->{$name_without_prefix};
        }
        if ($skip) {
            $self->log->warn("$module is skipped");
            return 1;
        }
    }
    return;
}

sub _copy {
    my $self = shift;
    my %file = @_;
    for ( keys %file ) {
        if ( $file{$_} ) {
            my $cmd = [
                'cp',
                $file{$_},
                catfile(
                    $self->directory,
                    $self->name || $self->just_name( $self->path ), $_
                )
            ];
            Shipwright::Util->run($cmd);
        }
    }
}

=head2 just_name

trim the version stuff from dist name

=cut

sub just_name {
    my $self = shift;
    my $name = shift;

    $name =~ s/tar\.bz2$/tar.gz/;    # CPAN::DistnameInfo doesn't like bz2

    $name .= '.tar.gz' unless $name =~ /(tar\.gz|tgz)$/;

    require CPAN::DistnameInfo;
    my $info = CPAN::DistnameInfo->new($name);
    my $dist = $info->dist;
    return $dist;
}

=head2 just_version

return version

=cut

sub just_version {
    my $self = shift;
    my $name = shift;
    $name .= '.tar.gz' unless $name =~ /(tar\.gz|tgz|tar\.bz2)$/;

    require CPAN::DistnameInfo;
    my $info    = CPAN::DistnameInfo->new($name);
    my $version = $info->version;
    $version =~ s/^v// if $version;
    return $version;
}

=head2 is_compressed

return true if the source is compressed file, i.e. tar.gz(tgz) and tar.bz2

=cut

sub is_compressed {
    my $self = shift;
    return 1 if $self->source =~ m{.*/.+\.(tar.(gz|bz2)|tgz)$};
    return;
}

1;

__END__

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2009 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


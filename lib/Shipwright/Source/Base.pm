package Shipwright::Source::Base;

use warnings;
use strict;
use Carp;
use File::Spec;
use File::Slurp;
use Module::CoreList;
use Shipwright::Source;
use Shipwright::Util;
use Cwd qw/getcwd/;

use base qw/Class::Accessor::Fast/;
__PACKAGE__->mk_accessors(
    qw/source directory download_directory follow min_perl_version map_path
      skip map keep_recommends keep_build_requires name log url_path
      version_path version/
);

=head1 NAME

Shipwright::Source::Base - base class for source

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
        Shipwright::Util->run($_);
    }
    $self->_copy( %{ $args{copy} } ) if $args{copy};
}

# you should subclass this method.
sub _cmd { }

sub _follow {
    my $self         = shift;
    my $path         = shift;
    my $cwd          = getcwd;
    my $require_path = File::Spec->catfile( $path, '__require.yml' );
    my $map          = {};

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

    if ( !-e $require_path ) {

        # if not found, we'll create one according to Build.PL or Makefile.PL
        my $require = {};
        chdir File::Spec->catfile($path);

        if ( -e 'Build.PL' ) {
            Shipwright::Util->run( [ $^X, 'Build.PL' ] );
            my $source = read_file( File::Spec->catfile( '_build', 'prereqs' ) )
              or die "can't read _build/prereqs: $!";
            my $eval .= '$require = ' . $source;
            eval $eval or die "eval error: $@";    ## no critic

            $source = read_file( File::Spec->catfile('Build.PL') )
              or die "can't read Build.PL: $!";
            if (   $source =~ /Module::Build/
                && $self->name ne 'cpan-Module-Build' )
            {
                unless ( defined $require->{build_requires}{'Module::Build'} ) {
                    $require->{build_requires}{'Module::Build'} = 0;
                }
            }

            Shipwright::Util->run( [ './Build', 'realclean' ] );
        }
        elsif ( -e 'Makefile.PL' ) {
            Shipwright::Util->run( [ $^X, 'Makefile.PL' ] );
            my ($source) = grep { /PREREQ_PM/ } read_file('Makefile');
            if ( $source && $source =~ /({.*})/ ) {
                my $eval .= '$require = ' . $1;
                $eval =~ s/([\w:]+)=>/'$1'=>/g;
                eval $eval or die "eval error: $@";    ## no critic
            }

            for ( keys %$require ) {
                $require->{requires}{$_} = delete $require->{$_};
            }

            $source = read_file('Makefile.PL')
              or die "can't read Makefile.PL: $!";

            if (   $source =~ /ExtUtils::/
                && $self->name ne 'cpan-ExtUtils-MakeMaker' )
            {
                unless ( defined $require->{requires}{'ExtUtils::MakeMaker'}
                    && $require->{requires}{'ExtUtils::MakeMaker'} >= 6.31 )
                {
                    $require->{build_requires} =
                      { 'ExtUtils::MakeMaker' => 6.31 };
                }
            }

#      # Makefile doesn't have recommends or build_requires stuff, we need to fix
#      # that accroding to META.yml
#            my $meta_path = File::Spec->catfile( $path, 'META.yml' );
#            if ( -e $meta_path ) {
#                my $meta = Shipwright::Util::LoadFile($meta_path);
#
#                for (qw/recommends build_requires/) {
#                    my $keep = 'keep_' . $_;
#                    if ( $self->$keep && $meta->{$_} && ! $require->{$_} ) {
#                        $require->{$_} = $meta->{$_};
#                    }
#                }
#            }

            Shipwright::Util->run( [ 'make', 'clean' ] );
            Shipwright::Util->run( [ 'rm',   'Makefile.old' ] );
        }

        for my $type (qw/requires recommends build_requires/) {
            for my $module ( keys %{ $require->{$type} } ) {
                $require->{$type}{$module}{version} =
                  delete $require->{$type}{$module};
            }
        }

        Shipwright::Util::DumpFile( $require_path, $require )
          or die "can't dump __require.yml: $!";
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

        for my $type (qw/requires recommends build_requires/) {
            for my $module ( keys %{ $require->{$type} } ) {

                # we don't want to require perl
                if ( $module eq 'perl' ) {
                    delete $require->{$type}{$module};
                    next;
                }

                if (
                    Module::CoreList->first_release( $module,
                        $require->{$type}{$module}{version} )
                    && Module::CoreList->first_release( $module,
                        $require->{$type}{$module}{version} ) <=
                    $self->min_perl_version
                  )
                {
                    delete $require->{$type}{$module};
                    next;
                }

                my $name = $module;
                if ( $self->_is_skipped($module) ) {
                    delete $require->{$type}{$module}
                      unless defined $map->{$module};
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
                            );
                        }
                        else {
                            $s = Shipwright::Source->new(
                                %$self,
                                source  => "cpan:$module",
                                version => undef,
                                name => '',   # cpan name is automaticaly fixed.
                            );
                        }
                        $s->run();
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

sub _is_skipped {
    my $self   = shift;
    my $module = shift;

    if ( $self->skip && defined $self->skip->{$module} ) {
        $self->log->warn("$module is skipped");
        return 1;
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
                File::Spec->catfile(
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

    $name =~ s/tar\.bz2$/tar.gz/;  # CPAN::DistnameInfo doesn't like bz2

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

=head1 INTERFACE

package Shipwright::Script::Build;

use warnings;
use strict;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(
    qw/build_base skip skip_test only_test install_base
      force log_file flags name perl only with/
);

use Shipwright;
use Cwd 'abs_path';
use File::Spec::Functions qw/catdir/;

sub options {
    (
        'install-base=s' => 'install_base',
        'build-base=s'   => 'build_base',
        'name=s'         => 'name',
        'skip=s'         => 'skip',
        'only=s'         => 'only',
        'flags=s'        => 'flags',
        'skip-test'      => 'skip_test',
        'only-test'      => 'only_test',
        'force'          => 'force',
        'perl'           => 'perl',
        'with=s'         => 'with',
    );
}

sub run {
    my $self         = shift;
    my $install_base = shift;
    $self->install_base($install_base)
      if $install_base && !$self->install_base;

    if ( $self->install_base ) {

        # convert relative path to be absolute
        $self->install_base( abs_path( $self->install_base ) );
    }

    unless ( $self->name ) {
        if ( $self->repository =~ m{([-.\w]+)/([.\d]+)$} ) {
            $self->name("$1-$2");
        }
        elsif ( $self->repository =~ /([-.\w]+)$/ ) {
            $self->name($1);
        }
    }

    $self->skip( { map { $_ => 1 } split /\s*,\s*/, $self->skip || '' } );

    if ( $self->only ) {
        $self->only( { map { $_ => 1 } split /\s*,\s*/, $self->only } );
    }

    $self->flags(
        {
            default => 1,
            map { $_ => 1 } split /\s*,\s*/, $self->flags || ''
        }
    );

    $self->with( { map { split /=/ } split /\s*,\s*/, $self->with || '' } );

    my %source;
    for my $name ( keys %{ $self->with } ) {
        my $shipwright = Shipwright->new(
            name   => $name,
            source => $self->with->{$name},
            follow => 0,
            map { $_ => $self->$_ } qw/repository only_test perl/
        );
        $source{$name} = $shipwright->source->run;
    }

    my $shipwright = Shipwright->new(
        map { $_ => $self->$_ }
          qw/repository log_level log_file skip skip_test
          flags name force only_test install_base build_base perl only/
    );

    $shipwright->backend->export( target => $shipwright->build->build_base );

    my $dists_dir = $shipwright->build->build_base;
    for my $name ( keys %source ) {
        my $dir = catdir( $dists_dir, 'dists', $name );
        system("rm -rf $dir");
        system("cp -r $source{$name} $dir");
    }
    $shipwright->build->run();
}

1;

__END__

=head1 NAME

Shipwright::Script::Build - Build the specified project

=head1 SYNOPSIS

 build -r [repository]

=head1 OPTIONS

 -r [--repository] REPOSITORY : specify the repository of our project
 -l [--log-level] LOGLEVEL    : specify the log level
                                (info, debug, warn, error, or fatal)
 --log-file FILENAME          : specify the log file
 --install-base PATH          : specify install base, default is an autocreated
                                temp dir
 --skip DISTS                 : specify dists which will be skipped
 --only DISTS                 : specify dists to be installed (no others will
                                be installed)
 --skip-test                  : specify whether to skip tests
 --only-test                  : just test (run t/test)
 --flags FLAGS                : specify flags
 --name NAME                  : specify the name of the project
 --perl PATH                  : specify the path of perl that run the commands
                                in scripts/
 --with name=source,...       : don't build the dist of the name in repo,
                                use the one specified here instead.


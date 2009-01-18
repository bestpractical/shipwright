package Shipwright::Script::List;

use strict;
use warnings;
use Carp;

use base qw/App::CLI::Command Class::Accessor::Fast Shipwright::Script/;
__PACKAGE__->mk_accessors(qw/with_latest_version only_update/);

use Shipwright;

sub options {
    (
        'with-latest-version' => 'with_latest_version',
        'only-update'         => 'only_update',
    );
}

sub run {
    my $self = shift;
    my $name = shift;

    my $shipwright = Shipwright->new( repository => $self->repository, );

    my $versions = $shipwright->backend->version;
    my $source   = $shipwright->backend->source;
    my $refs     = $shipwright->backend->refs || {};
    my $branches;

    if ( $shipwright->backend->has_branch_support ) {
        $branches = $shipwright->backend->branches;
    }

    my $latest_version = {};

    # only_update option implies with_latest_version
    $self->with_latest_version(1) if $self->only_update;

    if ( $self->with_latest_version ) {
        my $map = $shipwright->backend->map;

        if ($name) {
            if ( $name =~ /^cpan-/ && !$source->{$name} ) {
                my %reversed = reverse %$map;
                my $module   = $reversed{$name};
                $latest_version->{$name} =
                  $self->_latest_version( name => $module );
            }
            else {
                $latest_version->{$name} =
                  $self->_latest_version( url => $source->{$name} );
            }
        }
        else {

            for my $module ( keys %$map ) {
                next if exists $latest_version->{ $map->{$module} };
                $latest_version->{ $map->{$module} } =
                  $self->_latest_version( name => $module );
            }

            for my $name ( keys %$source ) {
                next if exists $latest_version->{$name};
                if ( $source->{$name} =~ m{^(sv[nk]|shipwright):} ) {
                    for my $branch ( keys %{ $source->{$name} } ) {
                        $latest_version->{$name}{$branch} =
                          $self->_latest_version(
                            url => $source->{$name}{$branch} );
                    }
                }
            }
        }
    }

    if ($name) {
        my $new_versions = {};
        $new_versions->{$name} = $versions->{$name}
          if exists $versions->{$name};
        $versions = $new_versions;
    }
    for my $name ( sort keys %$versions ) {
        my $flip = 1;

        if ( $self->only_update ) {
            $flip = 0;
            if ( $latest_version->{$name} ) {
                require version;
                my $latest = version->new( $latest_version->{$name} );
                if ( ref $versions->{$name} ) {

                  # we show this dist if at least one of the branches has update
                    for my $branch ( keys %{ $versions->{$name} } ) {
                        if ( $latest gt $versions->{$name}{$branch} ) {
                            $flip = 1;
                            last;
                        }
                    }
                }
                elsif ( $latest gt $versions->{$name} ) {
                    $flip = 1;
                }
            }
        }

        if ($flip) {
            print $name, ': ', "\n";
            print ' ' x 4 . 'version: ';
            if ( ref $versions->{$name} ) {

                if ( $name =~ /^cpan-/ ) {
                    print $versions->{$name}{'vendor'}, "\n";
                }
                else {
                    print "\n";
                    for my $branch ( keys %{ $versions->{$name} } ) {
                        print ' ' x 8, $branch, ': ',
                          $versions->{$name}{$branch} || '', "\n";
                    }
                }
            }
            else {
                print $versions->{$name} || '', "\n";
            }

            print ' ' x 4 . 'from: ';
            if ( ref $source->{$name} ) {
                print "\n";
                for my $branch ( keys %{ $source->{$name} } ) {
                    print ' ' x 8, $branch, ': ',
                      $source->{$name}{$branch} || '', "\n";
                }
            }
            else {
                print $source->{$name} || 'CPAN', "\n",;
            }

            print ' ' x 4 . 'references: ',
              defined $refs->{$name} ? $refs->{$name} : 'unknown', "\n";

            if ( $self->with_latest_version ) {
                print ' ' x 4, 'latest_version: ';
                if ( ref $source->{$name} ) {
                    print "\n";
                    for my $branch ( keys %{ $source->{$name} } ) {
                        print ' ' x 8, $branch, ': ',
                          $latest_version->{$name}{$branch} || 'unknown', "\n";
                    }
                }
                else {
                    print $latest_version->{$name} || 'unknown', "\n";
                }
            }

            if ($branches && $name !~ /^cpan-/) {
                print ' ' x 4 . 'branches: ',
                  join( ', ', @{ $branches->{$name} } ), "\n";
            }
        }
    }

    if ( $name && keys %$versions == 0 ) {
        print $name, " doesn't exist\n";
    }
}

sub _latest_version {
    my $self = shift;
    my %args = @_;
    if ( $args{url} ) {

        my ( $cmd, $out );

        # XXX TODO we need a better latest_version for shipwright source
        # using the source shipwright repo's whole version seems lame
        if ( $args{url} =~ s/^shipwright:// ) {
            $args{url} =~ s!/[^/]+$!!;
        }

        # has url, meaning svn or svk
        if ( $args{url} =~ /^svn[:+]/ ) {
            $args{url} =~ s{^svn:(?!//)}{};
            $cmd = [ $ENV{'SHIPWRIGHT_SVN'}, 'info', $args{url} ];
        }
        elsif ( $args{url} =~ m{^(svk:|//)} ) {
            $args{url} =~ s/^svk://;
            $cmd = [ $ENV{'SHIPWRIGHT_SVK'}, 'info', $args{url} ];
        }

        ($out) = Shipwright::Util->run( $cmd, 1 );    # ignore failure
        if ( $out =~ /^Revision:\s*(\d+)/m ) {
            return $1;
        }
    }
    elsif ( $args{name} ) {

        # cpan
        require CPAN;
        require CPAN::DistnameInfo;

        Shipwright::Util->select('cpan');

        my $module = CPAN::Shell->expand( 'Module', $args{name} );

        Shipwright::Util->select('stdout');

        my $info    = CPAN::DistnameInfo->new( $module->cpan_file );
        my $version = $info->version;
        $version =~ s/^v//;    # we don't want the leading 'v'
        return $version;
    }
    return;
}

1;

__END__

=head1 NAME

Shipwright::Script::List - List dists of a project

=head1 SYNOPSIS

 list NAME

=head1 OPTIONS
   -r [--repository] REPOSITORY    : specify the repository of our project
   -l [--log-level] LOGLEVEL       : specify the log level
   --log-file FILENAME             : specify the log file
                                     (info, debug, warn, error, or fatal)
   --with-latest-version           : show the latest version if possible
   --only-update                   : only show the dists that can be updated

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2009 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


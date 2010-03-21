package Shipwright::Source;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;
use File::Temp qw/tempdir/;
use File::Spec::Functions qw/catfile catdir/;
use Shipwright::Util;
use File::Path qw/make_path/;

=head1 NAME

Shipwright::Source - Source

=head1 SYNOPSIS

    shipwright import -r ... cpan:XML::LibXML

    use Shipwright::Source;

=head1 SUPPORTED SOURCES

Currently, the supported sources are L<CPAN|Shipwright::SOURCE::CPAN>, L<Compressed|Shipwright::SOURCE::Compressed>, L<Directory|Shipwright::SOURCE::Directory>, L<FTP|Shipwright::SOURCE::FTP>, L<Git|Shipwright::SOURCE::Git>, L<HTTP|Shipwright::SOURCE::HTTP>, L<SVK|Shipwright::SOURCE::SVK>, L<SVN|Shipwright::SOURCE::SVN> and L<Shipwright|Shipwright::SOURCE::Shipwright>.

=head1 METHODS

=head2 new

=cut

$ENV{SHIPWRIGHT_SOURCE_ROOT} ||=
  tempdir( 'shipwright_source_XXXXXX', CLEANUP => 1, TMPDIR => 1 );

sub new {
    my $class = shift;
    my %args = (
        follow => 1,
        directory => $ENV{SHIPWRIGHT_SOURCE_ROOT},
        @_,
    );

    $args{download_directory} ||=
      catdir( shipwright_user_root(), 'downloads' );

    $args{scripts_directory} ||= catdir( $args{directory}, '__scripts' );
    $args{map_path}      ||= catfile( $args{directory}, 'map.yml' );
    $args{url_path}      ||= catfile( $args{directory}, 'url.yml' );
    $args{version_path}  ||= catfile( $args{directory}, 'version.yml' );
    $args{branches_path} ||= catfile( $args{directory}, 'branches.yml' );

    for (qw/map_path url_path version_path branches_path/) {
        next if -e $args{$_};
        open my $fh, '>', $args{$_} or confess "can't write to $args{$_}: $!";
        close $fh;
    }

    confess "need source arg" unless exists $args{source};

    for my $dir (qw/directory download_directory scripts_directory/) {
        make_path( $args{$dir} ) unless -e $args{$dir};
    }

    my $type = type( \$args{source} );

    confess "invalid source: $args{source}" unless $type;

    my $module = 'Shipwright::Source::' . $type;
    $module->require;
    return $module->new(%args);
}

=head2 type

=cut

sub type {
    my $source = shift;

    _translate_source($source);

    # prefix that can't be omitted
    if ( $$source =~ /^file:.*\.(tar\.gz|tgz|tar\.bz2)$/ ) {
        $$source =~ s/^file://i;
        return 'Compressed';
    }

    return 'Directory'  if $$source =~ s/^dir(ectory)?://i;
    return 'Shipwright' if $$source =~ s/^shipwright://i;

    if ( $$source =~ s/^cpan://i ) {

        # if it's not a distribution name, like
        # 'S/SU/SUNNAVY/IP-QQWry-v0.0.15.tar.gz', convert '-' to '::'.
        $$source =~ s/-/::/g unless $$source =~ /\.tar\.gz$/;
        return 'CPAN';
    }

    # prefix that can be omitted
    for my $type (qw/svn http ftp git/) {
        if ( $$source =~ /^$type:/i ) {
            $$source =~ s{^$type:(?!//)}{}i;
            return $type eq 'git' ? 'Git' : uc $type;
        }
    }

    if ( $$source =~ m{^(//|svk:)}i ) {
        $$source =~ s/^svk://i;
        return 'SVK';
    }

}

sub _translate_source {
    my $source = shift;
    if ( $$source =~ /^(file|dir(ectory)?|shipwright):~/i ) {

        # replace prefix ~ with real home dir
        $$source =~ s/~/user_home/e;
    }
}

1;

__END__

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


package Shipwright::Source;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;
use Hash::Merge qw/merge/;
use File::Temp qw/tempdir/;
use File::Spec::Functions qw/catfile catdir/;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

our %DEFAULT = ( follow => 1, );

$DEFAULT{directory} =
  tempdir( 'shipwright_source_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
$DEFAULT{scripts_directory}  = catdir( $DEFAULT{directory}, '__scripts' );
$DEFAULT{download_directory} = catdir( $DEFAULT{directory}, '__download' );
$DEFAULT{map_path}           = catfile( $DEFAULT{directory}, 'map.yml' );
$DEFAULT{url_path}           = catfile( $DEFAULT{directory}, 'url.yml' );
$DEFAULT{version_path}       = catfile( $DEFAULT{directory}, 'version.yml' );
$DEFAULT{branches_path}      = catfile( $DEFAULT{directory}, 'branches.yml' );

for (qw/map_path url_path version_path branches_path/) {
    open my $fh, '>', $DEFAULT{$_} or confess "can't write to $DEFAULT{$_}: $!";
    close $fh;
}

=head1 NAME

Shipwright::Source - Source

=head1 SYNOPSIS

    use Shipwright::Source;

=head1 METHODS

=head2 new

=cut

sub new {
    my $class = shift;
    my %args = %{ merge( \%DEFAULT, {@_} ) };

    croak "need source arg" unless exists $args{source};

    for my $dir (qw/directory download_directory scripts_directory/) {
        mkdir $args{$dir} unless -e $args{$dir};
    }

    my $type = type( \$args{source} );

    croak "invalid source: $args{source}" unless $type;

    my $module = 'Shipwright::Source::' . $type;
    $module->require;
    return $module->new(%args);
}

=head2 type

=cut

sub type {
    my $source = shift;

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

1;

__END__

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2009 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


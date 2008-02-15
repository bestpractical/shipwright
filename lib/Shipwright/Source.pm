package Shipwright::Source;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;
use Hash::Merge qw/merge/;
use File::Temp qw/tempdir/;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

our %DEFAULT = (
    follow            => 1,
);

$DEFAULT{directory} = tempdir( CLEANUP => 0 );
$DEFAULT{download_directory} =
  File::Spec->catfile( $DEFAULT{directory}, 'download' );
$DEFAULT{map_path} = File::Spec->catfile( $DEFAULT{directory}, 'map.yml' );
$DEFAULT{url_path} = File::Spec->catfile( $DEFAULT{directory}, 'url.yml' );

for ( qw/map_path url_path/ ) {
    open my $fh, '>', $DEFAULT{$_} or die "can't write to $DEFAULT{$_}: $!";
    close $fh;
}

=head2 new

=cut

sub new {
    my $class = shift;
    my %args = %{ merge( \%DEFAULT, {@_} ) };

    my $type = delete $args{type} || type( $args{source} );

    croak "need source option" unless $args{source};

    my $module = 'Shipwright::Source::' . $type;
    $module->require or die $@;
    return $module->new(%args);
}

=head2 type

=cut

sub type {
    my $source = shift;

    if ( -e $source ) {
        if ( -d $source ) {
            return 'Directory';
        }
        elsif ( -f $source && $source =~ /\.(tgz|tar\.(gz|bz2))$/ ) {
            return 'Compressed';
        }
        else {
            croak
"only support directory and compressed file which contains only one directory";
        }
    }
    elsif ( $source =~ m{^\s*http://} ) {
        return 'HTTP';
    }
    elsif ( $source =~ m{^\s*ftp://} ) {
        return 'FTP';
    }
    elsif ( $source =~ m{^\s*svn[:+]} ) {
        return 'SVN';
    }
    elsif ( $source =~ m{^\s*(svk:|//)} ) {
        return 'SVK';
    }
    else {
        return 'CPAN';
    }
}

1;

__END__

=head1 NAME

Shipwright::Source - source part


=head1 SYNOPSIS

    use Shipwright::Source;

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


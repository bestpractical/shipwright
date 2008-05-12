package Shipwright::Source;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;
use Hash::Merge qw/merge/;
use File::Temp qw/tempdir/;

Hash::Merge::set_behavior('RIGHT_PRECEDENT');

our %DEFAULT = ( follow => 1, );

$DEFAULT{directory} = tempdir( CLEANUP => 0 );
$DEFAULT{download_directory} =
  File::Spec->catfile( $DEFAULT{directory}, 'download' );
$DEFAULT{map_path} = File::Spec->catfile( $DEFAULT{directory}, 'map.yml' );
$DEFAULT{url_path} = File::Spec->catfile( $DEFAULT{directory}, 'url.yml' );
$DEFAULT{version_path} =
  File::Spec->catfile( $DEFAULT{directory}, 'version.yml' );

for (qw/map_path url_path version_path/) {
    open my $fh, '>', $DEFAULT{$_} or die "can't write to $DEFAULT{$_}: $!";
    close $fh;
}

=head2 new

=cut

sub new {
    my $class = shift;
    my %args = %{ merge( \%DEFAULT, {@_} ) };

    croak "need source option" unless $args{source};

    my $type = type( \$args{source} );

    croak "invalid source $args{source}" unless $type;

    my $module = 'Shipwright::Source::' . $type;
    $module->require or die $@;
    return $module->new(%args);
}

=head2 type

=cut

sub type {
    my $source = shift;

    # prefix that can't be omitted
    return 'Compressed' if $$source =~ s/^file://i;
    return 'Directory'  if $$source =~ s/^dir(ectory)?://i;
    return 'CPAN'       if $$source =~ s/^cpan://i;

    # prefix that can be omitted
    for my $type (qw/svk svn http ftp/) {
        if ( $$source =~ /^$type:/i ) {
            $$source =~ s{^$type:(?!//)}{}i;
            return uc $type;
        }
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


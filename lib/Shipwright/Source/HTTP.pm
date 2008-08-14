package Shipwright::Source::HTTP;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile catdir/;
use Shipwright::Source::Compressed;

use base qw/Shipwright::Source::Base/;

=head2 run

=cut

sub run {
    my $self = shift;

    $self->log->info( "prepare to run source: " . $self->source );

    if ( $self->_run ) {
        my $compressed =
          Shipwright::Source::Compressed->new( %$self, _no_update_url => 1 );
        $compressed->run();
    }
}

=head2 _run

=cut

sub _run {
    my $self   = shift;
    my $source = $self->source;
    my $file;
    if ( $source =~ m{.*/(.+\.(tar\.gz|tgz|tar\.bz2))$} ) {
        $file = $1;
        $self->_update_url( $self->just_name($file), $source );

        my $src_dir = $self->download_directory;
        mkdir $src_dir unless -e $src_dir;
        $self->source( catfile( $src_dir, $file ) );

        require LWP::UserAgent;
        my $ua = LWP::UserAgent->new;
        $ua->timeout(1200);

        my $response = $ua->get($source);

        if ( $response->is_success ) {
            open my $fh, '>', $self->source
              or die "can't open file " . $self->source . ": $!";
            print $fh $response->content;
        }
        else {
            croak "failed to get $source: " . $response->status_line;
        }
    }
    else {
        croak "invalid source: $source";
    }
    return 1;
}

1;

__END__

=head1 NAME

Shipwright::Source::HTTP - http source


=head1 DESCRIPTION


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

package Shipwright::Source::Compressed;

use warnings;
use strict;
use Carp;
use File::Spec;

use base qw/Shipwright::Source::Base/;

=head2 run

=cut

sub run {
    my $self = shift;

    $self->name( $self->just_name( $self->path ) ) unless $self->name;
    $self->log->info( 'run source ' . $self->name . ': ' . $self->source );

    $self->_update_url( $self->name, $self->source )
      unless $self->{_no_update_url};

    my $ret = $self->SUPER::run(@_);
    $self->_follow( File::Spec->catfile( $self->directory, $self->name ) )
      if $self->follow;
    return File::Spec->catfile( $self->directory, $self->name );
}

=head2 path

the decompressed source path

=cut

sub path {
    my $self   = shift;
    my $source = $self->source;
    my ($out) = Shipwright::Util->run( [ 'tar', '-t', '-f', $source ] );
    my $sep = $/;
    my @contents = split /$sep/, $out;
    my %path;

    for (@contents) {
        $path{$1} = 1 if m{^(.+?)/};
    }

    my @paths = keys %path;
    croak 'only support compressed file which contains only one directory'
      unless @paths == 1;
    return $paths[0];
}

sub _cmd {
    my $self = shift;
    my $arg;

    if ( $self->source =~ /\.(tar\.|t)gz$/ ) {
        $arg = 'xfz';
    }
    elsif ( $self->source =~ /\.tar\.bz2$/ ) {
        $arg = 'xfj';
    }
    else {
        croak "I've no idea what the cmd is";
    }

    my @cmds;
    push @cmds, [ 'tar', $arg, $self->source, '-C', $self->directory ];

    if ( $self->name && $self->name ne $self->path ) {
        if ( -e File::Spec->catfile( $self->directory, $self->name ) ) {
            push @cmds,
              [
                'rm', '-rf',
                File::Spec->catfile( $self->directory, $self->path )
              ],

        }
        else {
            push @cmds,
              [
                'mv',
                File::Spec->catfile( $self->directory, $self->path ),
                File::Spec->catfile( $self->directory, $self->name )
              ];
        }
    }
    else {
        push @cmds,
          [
            'mv',
            File::Spec->catfile( $self->directory, $self->path ),
            File::Spec->catfile(
                $self->directory, $self->just_name( $self->path )
            )
          ];
    }

    return @cmds;
}

1;

__END__

=head1 NAME

Shipwright::Source::Compressed - compressed source


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

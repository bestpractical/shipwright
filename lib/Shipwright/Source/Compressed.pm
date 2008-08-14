package Shipwright::Source::Compressed;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile catdir/;

use base qw/Shipwright::Source::Base/;

=head2 run

=cut

sub run {
    my $self = shift;

    $self->name( $self->just_name( $self->path ) ) unless $self->name;
    $self->version( $self->just_version( $self->path ) ) unless $self->version;
    $self->log->info( 'run source ' . $self->name . ': ' . $self->source );

    $self->_update_version( $self->name, $self->version );

    $self->_update_url( $self->name, 'file:' . $self->source )
      unless $self->{_no_update_url};

    my $newer = $self->_cmd; # if we really get something new

    my $ret = $self->SUPER::run(@_);
    # follow only if --follow and we really added new stuff.
    $self->_follow( catfile( $self->directory, $self->name ) )
      if $self->follow && $newer;
    return catfile( $self->directory, $self->name );
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


    my ( $from, $to );
    $from = catfile( $self->directory, $self->path );
    $to = catfile( $self->directory, $self->name );

# if it already exists, assuming we have processed it already, don't do it
# again
    return if -e $to; 

    my @cmds;
    push @cmds, [ 'tar', $arg, $self->source, '-C', $self->directory ];
    
    if ( $from ne $to ) {
        push @cmds,
          [
            'mv',
            $from,
            $to,
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

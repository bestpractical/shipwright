package Shipwright::Source::Git;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catdir/;

use base qw/Shipwright::Source::Base/;

=head2 new

=cut

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    $self->name( $self->just_name( $self->source ) ) unless $self->name;
    return $self;
}

=head2 run

=cut

sub run {
    my $self = shift;
    $self->log->info( "prepare to run source: " . $self->source );
    $self->_update_url( $self->name, 'git:' . $self->source );

    $self->_run();
    my $s;
    if ( $self->is_compressed ) {
        require Shipwright::Source::Compressed;
        $s = Shipwright::Source::Compressed->new( %$self, _no_update_url => 1 );
    }
    else {
        require Shipwright::Source::Directory;
        $s = Shipwright::Source::Directory->new( %$self, _no_update_url => 1 );
    }
    $s->run(@_);
}

=head2 _run

=cut

sub _run {
    my $self   = shift;
    my $source = $self->source;

    my @cmds = (
        [
            $ENV{'SHIPWRIGHT_GIT'}, 'clone', $self->source,
            catdir( $self->download_directory, $self->name ),
        ],
    );

# TODO handle the version stuff

    push @cmds,
    [
        'rm', '-rf',
        catdir( $self->download_directory, $self->name, '.git' ),
    ];

    $self->source( catdir( $self->download_directory, $self->name ) );
    Shipwright::Util->run($_) for @cmds;
}

1;

__END__

=head1 NAME

Shipwright::Source::Git - Git source


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

Copyright 2007-2009 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

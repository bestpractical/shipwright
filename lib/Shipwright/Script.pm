package Shipwright::Script;
use strict;
use warnings;
use App::CLI;
use base qw/App::CLI/;

=head2 alias
=cut

sub alias {
    return ( ls => 'list' );
}

=head2 prepare
=cut

sub prepare {
    my $self = shift;
    $ARGV[0] = 'help' unless @ARGV;

    if ( $ARGV[0] =~ /--?h(elp)?/i ) {
        $ARGV[0] = 'help';
    }

    # all the cmds need --repository arg
    if ( $ARGV[0] ne 'help' ) {

        # test some options in advance, so we can exit asap.
        my %args;

        for ( my $i = 1 ; $i <= $#ARGV - 1 ; $i++ ) {
            if ( $ARGV[$i] eq '-r' || $ARGV[$i] eq '--repository' ) {
                if ( $ARGV[ $i + 1 ] =~ /^-/ ) {
                    die 'option repository requires an argument';
                }
                else {
                    $args{repository} = $ARGV[ $i + 1 ];
                }
                $i++;    # skip the argument
            }
            elsif ( $ARGV[$i] eq '-l' || $ARGV[$i] eq '--log-level' ) {
                if ( $ARGV[ $i + 1 ] =~ /^-/ ) {
                    die 'option log-level requires an argument';
                }
                else {
                    $args{log_level} = $ARGV[ $i + 1 ];
                }
                $i++;    # skip the argument
            }
            elsif ( $ARGV[$i] eq '--log-file' ) {
                if ( $ARGV[ $i + 1 ] =~ /^-/ ) {
                    die 'option log-file requires an argument';
                }
                else {
                    $args{log_file} = $ARGV[ $i + 1 ];
                }
                $i++;    # skip the argument
            }

        }

        if ($args{repository}) {

            my $backend =
              Shipwright::Backend->new( repository => $args{repository} );

            # this $shipwright object will do nothing, except for init logging
            my $shipwright = Shipwright->new(
                repository => $args{repository},
                log_level  => $args{log_level},
                log_file   => $args{log_file},
            );

            die "invalid repository: $args{repository}"
              unless $backend->check_repository( action => $ARGV[0] );
        }
        else {
            @ARGV = ( 'help', $ARGV[0] );
        }
    }

    return $self->SUPER::prepare(@_);
}

=head2 log
=cut

sub log {
    my $self = shift;
    Shipwright::Logger->new($self);
    return Log::Log4perl->get_logger( ref $self );
}

1;

__END__

=head1 AUTHOR

sunnavy  C<< <sunnavy@bestpractical.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright 2007 Best Practical Solutions.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


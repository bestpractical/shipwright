package Shipwright::Logger;
use strict;
use warnings;
use Carp;
use Log::Log4perl;

=head2 new

=cut

sub new {
    my $class      = shift;
    my $shipwright = shift;

    my $self = {};
    bless $self, $class;

    if ( not Log::Log4perl->initialized ) {
        $class->_initialize_log4perl($shipwright);
    }
    return $self;
}

sub _initialize_log4perl {
    my $class      = shift;
    my $shipwright = shift;

    my $log_level = uc $shipwright->log_level || 'INFO';
    my %default;

    if ( $shipwright->log_file ) {
        %default = (
            'log4perl.rootLogger'             => "$log_level,File",
            'log4perl.appender.File.filename' => $shipwright->log_file,
            'log4perl.appender.File'        => 'Log::Log4perl::Appender::File',
            'log4perl.appender.File.stderr' => 1,
            'log4perl.appender.File.layout' =>
              'Log::Log4perl::Layout::PatternLayout',
            'log4perl.appender.File.layout.ConversionPattern' =>
              '%d %p> %F{1}:%L %M - %m%n',
        );
    }
    else {
        %default = (
            'log4perl.rootLogger'      => "$log_level,Screen",
            'log4perl.appender.Screen' => 'Log::Log4perl::Appender::Screen',
            'log4perl.appender.Screen.stderr' => 1,
            'log4perl.appender.Screen.layout' =>
              'Log::Log4perl::Layout::PatternLayout',
            'log4perl.appender.Screen.layout.ConversionPattern' =>
              '%d %p> %F{1}:%L %M - %m%n',
        );
    }

    Log::Log4perl->init( \%default );
}

1;

__END__

=head1 NAME

Shipwright::Logger - 


=head1 SYNOPSIS

    use Shipwright::Logger;

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



package Shipwright::Source::CPAN;

use warnings;
use strict;
use Carp;
use File::Spec;
use Shipwright::Source::Compressed;
use CPAN;
use Data::Dumper;
use File::Temp qw/tempdir/;
use File::Spec;
use File::Slurp;
use UNIVERSAL::require;
use CPAN::DistnameInfo;

use base qw/Shipwright::Source::Base/;

my $cpan_dir = tempdir( CLEANUP => 0 );
unshift @INC, $cpan_dir;

=head2 new

=cut

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    CPAN::Config->use;

    mkdir File::Spec->catfile( $cpan_dir, 'CPAN' );
    my $config_file = File::Spec->catfile( $cpan_dir, 'CPAN', 'MyConfig.pm' );

    unless ( -f $config_file ) {
        $CPAN::Config->{cpan_home} = File::Spec->catfile($cpan_dir);
        $CPAN::Config->{build_dir} = File::Spec->catfile( $cpan_dir, 'build' );
        $CPAN::Config->{histfile} =
          File::Spec->catfile( $cpan_dir, 'histfile' );
        $CPAN::Config->{keep_source_where} =
          File::Spec->catfile( $cpan_dir, 'sources' );
        $CPAN::Config->{prefs_dir} = File::Spec->catfile( $cpan_dir, 'prefs' );
        $CPAN::Config->{prerequisites_policy} = 'follow';
        $CPAN::Config->{urllist} ||= [];
        write_file( $config_file,
            Data::Dumper->Dump( [$CPAN::Config], ['$CPAN::Config'] ) );

    }
    require CPAN::MyConfig;
    return $self;
}

=head2 run

=cut

sub run {
    my $self = shift;
    $self->log->info( "prepare to run source: " . $self->source );
    if ( $self->_run ) {
        my $compressed =
          Shipwright::Source::Compressed->new( %$self, _no_update_url => 1 );
        $compressed->run(@_);
    }
}

sub _run {
    my $self = shift;
    return if $self->source eq 'perl';    # don't expand perl itself;

    my $module = CPAN::Shell->expand( 'Module', $self->source );

    unless ($module) {
        $self->log->warn( "can't find "
              . $self->source
              . ' on CPAN, assuming you will manually fix it. good luck!' );
        return;
    }

    $module->distribution->get;

    my $dist = CPAN::DistnameInfo->new( $module->cpan_file )->dist;
    $self->name( 'cpan-' . $dist );
    $self->_update_map( $self->source, 'cpan-' . $dist );

    $self->source(
        File::Spec->catfile(
            $CPAN::Config->{keep_source_where}, 'authors',
            'id',                               $module->cpan_file
        )
    );
    return 1;
}

1;

__END__

=head1 NAME

Shipwright::Source::CPAN - CPAN source


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

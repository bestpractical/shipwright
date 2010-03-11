package Shipwright::Source::CPAN;

use warnings;
use strict;
use Carp;
use File::Spec::Functions qw/catfile catdir rootdir/;
use Shipwright::Source::Compressed;
use CPAN;
use Data::Dumper;
use File::Temp qw/tempdir/;
use File::Slurp;
use CPAN::DistnameInfo;

use base qw/Shipwright::Source::Base/;

my $cpan_dir = tempdir( 'shipwright_cpan_XXXXXX', CLEANUP => 1, TMPDIR => 1 );
unshift @INC, $cpan_dir;

=head1 NAME

Shipwright::Source::CPAN - CPAN source

=head1 DESCRIPTION

=head2 new

=cut

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);

    require Module::Info;
    if ( Module::Info->new_from_module('CPAN::Config') ) {

        # keep original CPAN::Config info
        require CPAN::Config;
    }

    unshift @INC, catdir( $ENV{'HOME'}, '.cpan' );
    if ( Module::Info->new_from_module('CPAN::MyConfig') ) {

        # keep user's CPAN::MyConfig too
        require CPAN::MyConfig;
    }
    shift @INC;


    mkdir catdir( $cpan_dir, 'CPAN' );
    my $config_file = catfile( $cpan_dir, 'CPAN', 'MyConfig.pm' );

    unless ( -f $config_file ) {

        # hack $CPAN::Config, mostly to make cpan stuff temporary
        $CPAN::Config->{cpan_home} = catdir($cpan_dir);
        $CPAN::Config->{build_dir} = catdir( $cpan_dir, 'build' );
        $CPAN::Config->{histfile}  = catfile( $cpan_dir, 'histfile' );

        # be careful, if you use minicpan, then the source won't be copied to
        # $CPAN::Config->{keep_source_where}
        $CPAN::Config->{keep_source_where} =
          catdir( $self->download_directory, 'cpan' );
        $CPAN::Config->{prefs_dir}         = catdir( $cpan_dir, 'prefs' );
        $CPAN::Config->{prerequisites_policy} = 'follow';
        unless ( $CPAN::Config->{urllist} && @{ $CPAN::Config->{urllist} } ) {
            $CPAN::Config->{urllist} = ['http://search.cpan.org/CPAN'];
        }
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

    my $result = $self->_run;
    if ( $result && $result == 1) {
        my $compressed =
          Shipwright::Source::Compressed->new( %$self, _no_update_url => 1 );
        $compressed->run(@_);
    }
    elsif ( !$result &&  $self->source =~ /\S/ ) {
        my $error = q{invalid source: can't find '} . $self->source . q{'};
        if ( $self->version ) {
            $error .= ' version ' . $self->version;
        }
        $error .= ' in your CPAN mirror(s)' . " [@{$CPAN::Config->{urllist}}].";
        chdir rootdir(); #< chdir to root dir in case CPAN has chdir'd
                         #into one of the temp dirs, preventing its
                         #deletion
        confess $error;
    } else {
            $self->log->warn("Removing source ".$self->source);
            return;
    }
}

sub _run {
    my $self = shift;
    return if $self->source eq 'perl';    # don't expand perl itself;

    my ( $source, $distribution );

    Shipwright::Util->select('cpan');

    if ( $self->source =~ /\.tar\.gz$/ ) {

        # it's a disribution
        $distribution = CPAN::Shell->expand( 'Distribution', $self->source );

        unless ($distribution) {
            $self->log->warn( "can't find "
                  . $self->source
                  . ' on CPAN, assuming you will manually fix it. good luck!' );
            return;
        }

        # distribution source isn't good for shipwright, convert it to a
        # module name it contains
        $self->source( ( $distribution->containsmods )[0] );

        $source = $distribution->{ID};
    }
    else {

        # it's a module
        my $type = $self->source =~ /^Bundle/ ? 'Bundle' : 'Module';
        my $module = CPAN::Shell->expand( $type, $self->source );

        unless ($module) {
            $self->log->warn( "can't find "
                  . $self->source
                  . ' on CPAN, assuming you will manually fix it. good luck!' );
            return;
        }

        $source = $module->cpan_file;

        $distribution = $module->distribution;

        my $info = CPAN::DistnameInfo->new( $module->cpan_file );

        if ( $self->version ) {
            my $latest_version = $info->version;
            my $version        = $self->version;
            if ( $latest_version =~ /^v/ && $version !~ /^v/ ) {
                $version = 'v' . $version;
            }
            $distribution->{ID} =~ s/$latest_version/$version/;
            $source =~ s/$latest_version/$version/;
        }
    }

    my $name = CPAN::DistnameInfo->new( $distribution->{ID} )->dist;

    if ( $name eq 'perl' ) {
        $self->log->warn( 'perl itself contains ' . $self->source . ', will not process');
        return -1;
    } 
    if (!$name ) {
        $self->log->warn("You asked to install ".$self->source. " but it isn't on the CPAN. Skipping");
        return -1;
    }

    Shipwright::Util->select('stdout');

    $self->name( 'cpan-' . $name );
    $self->_update_map( $self->source, 'cpan-' . $name );

    my ($file) = catfile( $CPAN::Config->{keep_source_where},
        "authors", "id", split /\//, $distribution->id );

    if ( -e $file && -s $file ) {
        $self->source($file);
    }
    else {
        $self->source($distribution->get_file_onto_local_disk);
    }
    return 1;
}

1;

__END__

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2010 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


package Shipwright::Backend;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;
use Cwd qw/abs_path/;

sub new {
    my $class = shift;
    my %args  = @_;

    my $module;

    croak 'need repository arg' unless exists $args{repository};

    if ( $args{repository} =~ m{^\s*(svk:|//)} ) {
        $args{repository} =~ s{^\s*svk:}{};
        $module = 'Shipwright::Backend::SVK';
    }
    elsif ( $args{repository} =~ m{^\s*svn[:+]} ) {
        $args{repository} =~ s{^\s*svn:(?!//)}{};
        $module = 'Shipwright::Backend::SVN';
    }
    elsif ( $args{repository} =~ m{^\s*fs:} ) {
        $args{repository} =~ s{^\s*fs:}{};
        my $abs_path = abs_path($args{repository});
        $args{repository} = $abs_path if $abs_path;
        $module = 'Shipwright::Backend::FS';
    }
    else {
        croak "invalid repository: $args{repository}\n";
    }

    $module->require;

    return $module->new(%args);
}

1;

__END__

=head1 NAME

Shipwright::Backend - Backend

=head1 SYNOPSIS

use Shipwright::Backend;
$backend = Shipwright::Backend->new(repository => $args{repository});

=head1 METHODS

=over

=item new

returns the Backend object that corresponds to the type in
$args{repository}.

Currently, the supported backends are FS, SVN and SVK.

=item initialize

=item import

=item export

=item checkout

=item commit

=item update_order

=item order

=item map

=item source

=item delete

=item info

=item test_script

=item requires

=item flags

=item version

=item check_repository

=item update

=back

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2009 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

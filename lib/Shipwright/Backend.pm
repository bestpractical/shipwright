package Shipwright::Backend;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;

sub new {
    my $class = shift;
    my %args  = @_;

    my $module;

    if ( $args{repository} =~ m{^\s*(svk:|//)} ) {
        $args{repository} =~ s{^\s*svk:}{};
        $module = 'Shipwright::Backend::SVK';
    }
    elsif ( $args{repository} =~ m{^\s*svn[:+]} ) {
        $args{repository} =~ s{^\s*svn:(?!//)}{};
        $module = 'Shipwright::Backend::SVN';
    }
    else {
        croak "invalid repository: $args{repository}\n";
    }

    $module->require or die $@;

    return $module->new(%args);
}

1;

__END__

=head1 NAME

Shipwright::Backend - VCS repository backends

=head1 SYNOPSIS

use Shipwright::Backend;
$backend = Shipwright::Backend->new (repository => $args{repository});

=head1 INTERFACE

A backend must support the following methods:

=head2 initialize

=head2 import

=head2 export

=head2 checkout

=head2 commit

=head2 update_order

=head2 order

=head2 map

=head2 source

=head2 delete

=head2 info

=head2 propset

=head2 test_script

=head2 requires

=head2 flags

=head2 version

=head2 check_repository

=head2 update

=head1 CONSTRUCTOR

The constructor returns the Backend object that corresponds to the type in
$args{repository}.

Currently, the only supported backends are SVN and SVK.

=cut

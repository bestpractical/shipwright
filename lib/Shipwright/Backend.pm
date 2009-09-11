package Shipwright::Backend;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;
use File::Spec::Functions qw/rel2abs/;
use Shipwright::Util;

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
        $args{repository} =~ s/^~/Shipwright::Util->user_home/e;
        my $abs_path = rel2abs($args{repository});
        $args{repository} = $abs_path if $abs_path;
        $module = 'Shipwright::Backend::FS';
    }
    elsif ( $args{repository} =~ m{^\s*git:} ) {
        $args{repository} =~ s{^\s*git:}{};
        $module = 'Shipwright::Backend::Git';
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

    # shipwright some_command -r backend_type:path
    shipwright create -r svn:file:///svnrepo/shipwright/my_proj

    use Shipwright::Backend;
    $backend = Shipwright::Backend->new(repository => $args{repository});

=head1 DESCRIPTION

See <Shipwright::Manual::Glossary/repository> to understand concept. Look
at list of </SUPPORTED BACKENDS> and L<IMPLEMENTING BACKENDS> if you want
add a new one.

=head1 SUPPORTED BACKENDS

Currently, the supported backends are L<FS|Shipwright::BACKEND::FS>, L<Git|Shipwright::BACKEND::Git>, L<SVK|Shipwright::BACKEND::SVK> and L<SVN|Shipwright::BACKEND::SVN>.

=head1 IMPLEMENTING BACKENDS

Each implementation of a backend is a subclass of L<Shipwright::Backend::Base>.

=head1 METHODS

This is a tiny class with only one method C<new> that loads
particular implementation class and returns instance of that
class.

=head2 new repository => "type:path"

Returns the backend object that corresponds to the type
defined in the repository argument.

=head1 AUTHORS

sunnavy  C<< <sunnavy@bestpractical.com> >>

=head1 LICENCE AND COPYRIGHT

Shipwright is Copyright 2007-2009 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

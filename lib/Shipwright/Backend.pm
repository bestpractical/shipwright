package Shipwright::Backend;

use warnings;
use strict;
use Carp;
use UNIVERSAL::require;
use Shipwright::Util;

sub new {
    my $class = shift;
    my %args  = @_;

    confess 'need repository arg' unless exists $args{repository};

    $args{repository} =~ s/^\s+//;
    $args{repository} =~ s/\s+$//;

    # exception for svk repos, they can start with //
    if ( $args{repository} =~ m{^//} ) {
        $args{repository} = 'svk:'. $args{repository};
    }

    my ($backend, $subtype);
    if ( $args{repository} =~ /^([a-z]+)(?:\+([a-z]+))?:/ ) {
        ($backend, $subtype) = ($1, $2);
    } else {
        confess "invalid repository, doesn't start from xxx: or xxx+yyy:";
    }

    my $module = Shipwright::Util->find_module(__PACKAGE__, $backend);
    unless ( $module ) {
        confess "Couldn't find backend implementing '$backend'";
    }

    $module->require
        or confess "Couldn't load module '$module'"
            ." implementing backend '$backend': $@";
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
at list of </SUPPORTED BACKENDS> or L<IMPLEMENTING BACKENDS> if you want
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

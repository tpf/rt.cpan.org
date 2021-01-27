use 5.008003;
use strict;
use warnings;

package RT::Authen::Bitcard;

our $VERSION = '0.04_01';

use Authen::Bitcard 0.86;

=head1 NAME

RT::Authen::Bitcard - allows RT to do authentication via a service which supports the Bitcard API

=head1 SYNOPSIS

    # in RT_SiteConfig.pm:
    Set( @Plugins, qw(
        RT::Authen::Bitcard
        ... other plugins ...
    ) );
    Set( %Bitcard,
        Token          => 'you need a token for bitcard authentication to work',
        Required       => ['email'],
        Optional       => ['name'],
        UseUsername    => 0,
        NewUserOptions => {
            Privileged => 1,
        },
    );

=head1 DESCRIPTION

Authenticate users in RT using L<Authen::Bitcard>.

=head1 CONFIGURATION

=cut

my %RT2BC = (
    Name         => 'username',
    EmailAddress => 'email',
    RealName     => 'name',
);
my %BC2RT = reverse %RT2BC;

require RT::Config;
unless (exists $RT::Config::META{'ReferrerWhitelist'}) {  # future RT versions will fix this
    $RT::Config::META{'ReferrerWhitelist'} = { Type => 'ARRAY' };
}
RT->Config->Set('ReferrerWhitelist',('www.bitcard.org:443',RT->Config->Get('ReferrerWhitelist')));

sub Handler {
    my $self = shift;

    my $token = RT->Config->Get('Bitcard')->{'Token'};
    die 'No Bitcard auth token provided as Token key part of %Bitcard option'
        .' in the RT configuration file on this server.'
            unless $token;

    my $bc = Authen::Bitcard->new;
    $bc->token( $token );
    $bc->info_required( $self->RequiredFields );
    $bc->info_optional( $self->OptionalFields );
    return $bc;
}

sub RequiredFields {
    return RT->Config->Get('Bitcard')->{'Required'} || ['email'];
}

sub OptionalFields {
    return RT->Config->Get('Bitcard')->{'Optional'} || ['username', 'name'];
}

sub CreateUser {
    my $self = shift;
    my %args = (@_);

    my $user = $args{'BitcardUser'};

    my $config = RT->Config->Get('Bitcard');
    my $required = $self->RequiredFields;

    my $use_username = grep $_ eq 'username', @$required;
    if ( $use_username && !$config->{'UseUsername'} ) {
        $use_username = 0;
    }
  
    # first of all check if username is free then create a new user
    my $login_is_free = 0;
    if ( $use_username ) {
        my $UserObj = RT::User->new( $RT::SystemUser );
        $UserObj->Load( $user->{'username'} );
        $login_is_free = $UserObj->id? 0 : 1;
    }

    my $additional = $config->{'NewUserOptions'} || { Privileged => 1 };

    my $UserObj = RT::User->new( $RT::SystemUser );
    my ($id, $msg) = $UserObj->Create(
        %$additional,
        Name         => $login_is_free? $user->{'username'}: $user->{'email'},
        RealName     => $user->{'name'} || (!$use_username? $user->{'username'} : undef),
        EmailAddress => $user->{'email'},
    );
    unless ( $id ) {
        return (undef, $msg);
    }
    return $UserObj;
}

1;

=head1 AUTHOR

Kevin Riggle E<lt>kevinr@bestpractical.comE<gt>

=head1 COPYRIGHT

This extension is Copyright (C) 2005-2012 Best Practical Solutions, LLC.

It is freely redistributable under the terms of version 2 of the GNU GPL.

=cut


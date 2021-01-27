package RT::Authen::OpenID;

use 5.008;
use strict;
use warnings;

our $VERSION = '0.04';

require RT::Interface::Web;
$RT::Interface::Web::is_whitelisted_component{'/NoAuth/openid'} = 1;

=head1 NAME

RT::Authen::OpenID - Allows RT to do authentication via a service which supports the OpenID API

=head1 INSTALLATION

    perl Makefile.PL
    make
    make install

Enable in the config

    Set($EnableOpenId, 1);

=cut

1;

=head1 AUTHORS

Artur Bergman E<lt>sky@crucially.netE<gt>, Jesse Vincent E<lt>jesse@bestpractical.comE<gt>

=head1 COPYRIGHT

This extension is Copyright (C) 2005,2007-2009 Best Practical Solutions, LLC.
Portions of this extension are Copyright (C) 2006 Artur Bergman

It is freely redistributable under the terms of version 2 of the GNU GPL.

=cut


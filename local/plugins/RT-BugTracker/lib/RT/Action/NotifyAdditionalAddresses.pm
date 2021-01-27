package RT::Action::NotifyAdditionalAddresses;

use strict;
use warnings;
use base qw(RT::Action::Notify);

=head1 NAME

RT::Action::NotifyAdditionalAddresses - sends notifications to additional addresses defined for the distribution

=head1 DESCRIPTION

Either maintainer or user with the AdminQueue right can define additional
addresses for notifications. This is a subclass of L<RT::Action::Notify> that
notifies those recipients.

=cut

sub SetRecipients {
    my $self = shift;
    my $addresses = $self->TicketObj->QueueObj->NotifyAddresses;
    return unless $addresses && @$addresses;
    $self->{'To'} = [ @$addresses ];
}

1;

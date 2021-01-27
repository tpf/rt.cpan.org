use strict;
use warnings;

package RT::Condition::Status;
use base 'RT::Condition';

=head1 NAME

RT::Condition::Status - Scrip condition on a ticket status matching the provided Argument

=head1 DESCRIPTION

The Argument passed to the condition should be a comma-separated list of
statuses to match on.  The special values C<initial>, C<active>, and
C<inactive> may be used to match any status in those status sets (as defined in
the applicable Lifecycle).

=cut

sub IsApplicable {
    my $self     = shift;
    my $status   = $self->TicketObj->Status;
    my @statuses = $self->ProcessArgument($self->Argument);
    return 1 if grep { lc($status) eq lc($_) } @statuses;
    return 0;
}

sub ProcessArgument {
    my $self = shift;
    my $arg  = shift || "";
    my $lifecycle = $self->TicketObj->QueueObj->Lifecycle;
    my @statuses;

    for my $status (split /\s*,\s*/, $arg) {
        next unless defined $status and length $status;

        if ($status =~ /^(initial|active|inactive)$/i) {
            push @statuses, $lifecycle->Valid(lc $1);
        } else {
            push @statuses, $status;
        }
    }
    return @statuses;
}

1;

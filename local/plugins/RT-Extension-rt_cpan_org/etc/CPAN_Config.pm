# This is an RT configuration file, loaded when the RT::Extension::rt_cpan_org
# plugin is loaded.

Set( $Organization, "rt.cpan.org" );

# Logo
Set( $LogoURL, '/NoAuth/images/cpan.png' );
Set( $LogoLinkURL, $WebURL );
Set( $LogoAltText, "CPAN" );

# Reminders add much complexity for not much value.
Set( $EnableReminders, 0 );

# There are too many potential owners when not limited to a specific ticket/queue.
Set( $AutocompleteOwnersForSearch, 1 );

# This username format is forced and spam-protects email addresses.
Set( $UsernameFormat, 'public' );

# Email defaults; queues get their own dynamic addresses too
Set( $CorrespondAddress, 'bugs@rt.cpan.org' );
Set( $CommentAddress,    'comments@rt.cpan.org' );

# The old $rtname used to be "cpan"; accept it.
# See also BugTracker_Config.pm which extends this variable.
Set( $EmailSubjectTagRegex, qr/(?:\Q$rtname\E|cpan)/i );

# Too many deep links into rt.cpan.org.
Set( $RestrictReferrer, 0 );

# Don't require ModifyTicket for _both_ tickets, so bugs can be linked cross-queues.
Set( $StrictLinkACL, 0 );

# The internet expects formatting preserved and links clickable.
Set( $PlainTextMono, 1 );
Set( @Active_MakeClicky, qw(httpurl_overwrite) );

# Fancy-pants WYSIWYG usually mangles pasted terminal and log output.
Set( $MessageBoxRichText, 0 );

# The "more about requestors" is generally very useful
Set($ShowMoreAboutPrivilegedUsers, 1);

# Show severity, broken in, and fixed in by default.
Set( $DefaultSearchResultFormat, <<'EOT');
'<a href="__WebPath__/Ticket/Display.html?id=__id__">__id__</a>/TITLE:ID',
'<b><a href="__WebPath__/Ticket/Display.html?id=__id__">__Subject__</a></b>/TITLE:Subject',
'__Status__',
'__CustomField.{Severity}__',
'<small>__LastUpdatedRelative__</small>',
'__CustomField.{Broken in}__',
'__CustomField.{Fixed in}__'
EOT

# Allow unauth'd access to robots.txt.
Set( $WebNoAuthRegex, qr{(?: $WebNoAuthRegex | ^/+robots\.txt$ )}x );

# Development mode should always be off for production.
Set( $DevelMode, 0 );

# Add "patched" to the default lifecycle.
Set( %Lifecycles,
    cpan => {
        initial         => [ 'new' ],
        active          => [ 'open', 'stalled', 'patched' ],
        inactive        => [ 'resolved', 'rejected', 'deleted' ],

        defaults => {
            on_create => 'new',
            on_merge  => 'resolved',
            approved  => 'open',
            denied    => 'rejected',
            reminder_on_open     => 'open',
            reminder_on_resolve  => 'resolved',
        },

        transitions => {
            ''       => [qw(new open resolved)],

            # from   => [ to list ],
            new      => [qw(open stalled patched resolved rejected deleted)],
            open     => [qw(new stalled patched resolved rejected deleted)],
            stalled  => [qw(new open patched rejected resolved deleted)],
            patched  => [qw(new open stalled rejected resolved deleted)],
            resolved => [qw(new open stalled patched rejected deleted)],
            rejected => [qw(new open stalled patched resolved deleted)],
            deleted  => [qw(new open stalled patched rejected resolved)],
        },
        rights => {
            '* -> open'     => 'OpenTicket',
            '* -> deleted'  => 'DeleteTicket',
            '* -> *'        => 'ModifyTicket',
        },
        actions => [
            'new -> open'      => {
                label  => 'Open It', # loc
                update => 'Respond',
            },
            'new -> resolved'  => {
                label  => 'Resolve', # loc
                update => 'Respond',
            },
            'new -> rejected'  => {
                label  => 'Reject', # loc
                update => 'Respond',
            },
            'new -> deleted'   => {
                label  => 'Delete', # loc
            },

            'open -> stalled'  => {
                label  => 'Stall', # loc
                update => 'Respond',
            },
            'open -> resolved' => {
                label  => 'Resolve', # loc
                update => 'Respond',
            },
            'open -> rejected' => {
                label  => 'Reject', # loc
                update => 'Respond',
            },

            'stalled -> open'  => {
                label  => 'Open It', # loc
            },
            'patched -> open'  => {
                label   => 'Re-open',
                update  => 'Respond',
            },
            'patched -> resolved' => {
                label   => 'Resolve',
                update  => 'Respond',
            },
            'resolved -> open' => {
                label  => 'Re-open', # loc
                update => 'Respond',
            },
            'rejected -> open' => {
                label  => 'Re-open', # loc
                update => 'Respond',
            },
            'deleted -> open'  => {
                label  => 'Undelete', # loc
            },
        ],
    },
);

# Horrible horrible hack to keep the lifecycles overriding in this config
# instead of RT_SiteConfig.pm.  Relies on internals of RT::Config.
my %lifecycles = RT->Config->Get("Lifecycles");
%{ $lifecycles{default} } = %{ $lifecycles{cpan} };

# SQL for ACLs is good for perf and accurate counts, and rt.cpan.org's ACL
# model is pretty simple.
Set($UseSQLForACLChecks, 1);

# Useful forced content types based on usage.
# Requires RT::Extension::CustomizeContentType.
Set(%ContentTypes,
    (map { $_ => "text/x-perl" } qw( pm pl t psgi pmc )),
    (map { $_ => "text/x-diff" } qw( diff patch )),
    (map { $_ => "text/x-yaml" } qw( yaml yml )),
    "json"  => "text/x-json",
    "xs"    => "text/x-csrc",
    "c"     => "text/x-csrc",
    "h"     => "text/x-chdr",
    "pod"   => "text/x-pod",
);

# Easy linking to rt.perl.org tickets
Set(%RemoteLinks,
    perl => 'https://rt.perl.org/rt3',
);

1;

my $DEV = $ENV{PLACK_ENV} =~ /dev/i ? 1 : 0;

Set( $rtname, 'rt.cpan.org' );

Set($DatabaseHost, '');
Set($DatabaseRTHost, 'localhost');
Set($DatabaseUser, 'rt_user');
Set($DatabasePassword, 'password');
Set($DatabaseName, 'rt_cpan_org');

Set( $LogToSyslog, undef );
Set( $LogToScreen, $ENV{RT_LOG_LEVEL} || ($DEV ? "info" : undef) );
Set( $LogToFile, "warn" );
Set( $LogStackTraces, "crit" );

Set( $WebDomain, $DEV ? 'localhost' : 'rt.cpan.org');
Set( $WebPort,   $DEV ? 8008        : 443 );
Set( $CanonicalizeRedirectURLs, 1 );

Set($SetOutgoingMailFrom, 'rt-cpan-org-return@perl.org');

Set( %Bitcard,
    Token          => ($DEV
        ? 'testing'      # testing
        : 'production'),    # production
    Required       => ['email'],
    Optional       => ['name'],
    UseUsername    => 0,
    NewUserOptions => {
        Privileged => 1,
    },
);

# Use the system's list of certs, which we can modify, unlike Mozilla::CA
$ENV{PERL_LWP_SSL_CA_FILE}="/etc/ssl/certs/ca-bundle.crt";
Set( $EnableOpenId, 1 );

Set( $WebPublicUser, 'guest' );

# lexicon is too heave weight for this server
# we can not do this unless RT stops failing
# for users whos preferences are set
#Set( @LexiconLanguages, qw(en));

Set(@Plugins,
    "RT::Extension::rt_cpan_org",

    "RT::Authen::PAUSE",
    "RT::Authen::Bitcard",
    "RT::Authen::OpenID",
    "RT::Authen::OAuth2",

    "RT::Extension::MergeUsers",

    "RT::BugTracker",
    "RT::BugTracker::Public",

    "RT::Extension::ReportSpam",
    "RT::Extension::QuickDelete",
    "RT::Extension::CustomizeContentType",

    "RTx::GoogleAnalytics",
    "RTx::RemoteLinks",
);

Set(%GoogleAnalytics,
    TrackingID  => '',
    Method      => 'universal',
);

Set($JSMinPath, "/home/rtcpan/rt/bin/jsmin");

Set($SpamAutoDeleteThreshold, 2);

=pod

Set($EnableOAuth2, 1);
Set($OAuthIDP, 'auth0');


Set(%OAuthIDPSecrets,
    'google' => {
      'client_id' => '',
      'client_secret' => '',
    },
    'auth0' => {
      'client_id' => '',
      'client_secret'=> '',
    },
    );

Set($Auth0Host, "perl.auth0.com");
Set($OAuthCreateNewUser, 1);

=cut

1;

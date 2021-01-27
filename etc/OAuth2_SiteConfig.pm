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

1;


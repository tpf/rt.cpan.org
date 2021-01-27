use warnings;
use strict;

package RT::Extension::CustomizeContentType;

our $VERSION = "0.04";
use RT::Attachment;

package RT::Attachment;

my $new = sub {
    my $self         = shift;
    my $content_type = shift;

    return $content_type
      unless $self->Filename && $self->Filename =~ /\.(\w+)$/;
    my $ext = lc $1;

    my $config = RT->Config->Get('ContentTypes') or return $content_type;
    return $config->{$ext} || $content_type;
};

my $old = __PACKAGE__->can('ContentType');
if ($old) {
    no warnings 'redefine';
    *ContentType = sub {
        my $self = shift;
        my $content_type = $old->( $self, @_ );
        return $content_type unless defined $content_type;
        return $new->( $self, $content_type );
    };
}
else {
    *ContentType = sub {
        my $self         = shift;
        my $content_type = $self->_Value('ContentType');
        return $content_type unless defined $content_type;
        return $new->( $self, $content_type );
    };
}

1;
__END__

=head1 NAME

RT::Extension::CustomizeContentType - Customize Attachments' ContentType

=head1 INSTALLATION

To install this module, run the following commands:

    perl Makefile.PL
    make
    make install

add RT::Extension::CustomizeContentType to @Plugins in RT's etc/RT_SiteConfig.pm:

    Set( @Plugins, qw(... RT::Extension::CustomizeContentType) );
    Set(
        %ContentTypes,
        (
            't'    => 'text/x-perl-script',
            'psgi' => 'text/x-perl-script',
        )
    );

=head1 EXAMPLE CONFIGURATIONS

=head2 Microsoft Office

Older versions of IE often upload newer Microsoft Office documents with the
generic C<application/octet-stream> MIME type instead of something more
appropriate.  This causes RT to offer the file for download using the generic
content type, which confuses users and doesn't launch Office for them.  You can
fix that by L<installing this extension|/INSTALLATION> and using the
configuration below:

    Set(%ContentTypes,
        'docm' => 'application/vnd.ms-word.document.macroEnabled.12',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'dotm' => 'application/vnd.ms-word.template.macroEnabled.12',
        'dotx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.template',
        'potm' => 'application/vnd.ms-powerpoint.template.macroEnabled.12',
        'potx' => 'application/vnd.openxmlformats-officedocument.presentationml.template',
        'ppam' => 'application/vnd.ms-powerpoint.addin.macroEnabled.12',
        'ppsm' => 'application/vnd.ms-powerpoint.slideshow.macroEnabled.12',
        'ppsx' => 'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
        'pptm' => 'application/vnd.ms-powerpoint.presentation.macroEnabled.12',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'xlam' => 'application/vnd.ms-excel.addin.macroEnabled.12',
        'xlsb' => 'application/vnd.ms-excel.sheet.binary.macroEnabled.12',
        'xlsm' => 'application/vnd.ms-excel.sheet.macroEnabled.12',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'xltm' => 'application/vnd.ms-excel.template.macroEnabled.12',
        'xltx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.template',
    );

Config contributed by Nathan March.

=head1 AUTHOR

sunnavy, <sunnavy at bestpractical.com>

Thomas Sibley <trs@bestpractical.com>


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Best Practical Solutions, LLC.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


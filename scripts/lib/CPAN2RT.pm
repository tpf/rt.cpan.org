package CPAN2RT;

=head1 NAME

CPAN2RT - CPAN to RT converter for rt.cpan.org service

=head1 DESCRIPTION

An utility and module with functions to import and update metadata
about CPAN distributions into RT DB using files available from each
CPAN mirror.

Comes with `cpan2rt` script.

=cut

use v5.8.3;
use strict;
use warnings;

our $VERSION = '0.03';

use Email::Address;
use List::Compare;
use CPAN::DistnameInfo;
use List::MoreUtils qw(uniq);

our $DEBUG = 0;
sub debug(&);

=head1 METHODS

=head2 new

Simple constructor that creates a hash based object and stores all
passed arguments inside it. Then L</init> is called.

=head3 options

=over 8

=item home - RT home dir, RTHOME is checked if empty and defaults to
"/opt/rt3".

=item debug - turn on ddebug output to STDERR.

=item mirror - CPAN mirror to fetch files from.

=back

=cut

sub new {
    my $proto = shift;
    my $self = bless { @_ }, ref($proto) || $proto;
    $self->init();
    return $self;
}

=head2 init

Called right after constructor, changes @INC, loads RT and initilize it.

See options in description of L</new>.

=cut

sub init {
    my $self = shift;

    die "datadir ($self->{datadir}) doesn't exist!\n"
        if $self->{datadir} and not -d $self->{datadir};

    my $home = ($self->{'home'} ||= $ENV{'RTHOME'} || '/opt/rt3');
    unshift @INC, File::Spec->catdir( $home, 'lib' );
    unshift @INC, File::Spec->catdir( $home, 'local', 'lib' );

    $DEBUG = $self->{'debug'};

    require RT;
    RT::LoadConfig();
    if ( $DEBUG ) {
        $RT::LogToScreen = 'debug';
    } else {
        $RT::LogToScreen = 'warning';
    }
    RT::Init();
}

sub sync_files {
    my $self = shift;
    my $mirror = shift || $self->{'mirror'} || 'ftp://ftp.funet.fi/pub/CPAN';

    debug { "Syncing files from '$mirror'\n" };

    my @files = qw(
        indices/find-ls.gz
        authors/00whois.xml
        modules/06perms.txt.gz
        modules/02packages.details.txt.gz
    );

    foreach my $file ( @files ) {
        $self->fetch_file( $mirror, $file );
    }
}

sub fetch_file {
    my $self = shift;
    my $mirror = shift;
    my $file = shift;
    my $tries = shift || 3;

    require LWP::UserAgent;
    my $ua = new LWP::UserAgent;
    $ua->timeout( 10 );

    my $store = $self->file_path( $file );
    $self->backup_file( $store );
    my $url = "$mirror/$file";

    debug { "Fetching '$file' from '$url'\n" };
    my $response = $ua->get( $url, ':content_file' => $store );
    unless ( $response->is_success ) {
        print STDERR "Request to '$url' failed. Server response:\n". $response->status_line ."\n";
        return $self->fetch_file( $mirror, $file, $tries) if --$tries;

        print STDERR "Failed several attempts to fetch '$url'\n";
        return undef;
    }
    debug { "Fetched '$file' -> '$store'\n" };

    if ( $store =~ /(.*)\.gz$/ ) {
        $self->backup_file( $1 );
        `gunzip -f $store`;
        $store =~ s/\.gz$//;
        debug { "Unzipped '$store'\n" };
    }

    my $mtime = $response->header('Last-Modified');
    if ( $mtime ) {
        require HTTP::Date;
        $mtime = HTTP::Date::str2time( $mtime );
        utime $mtime, $mtime, $store if $mtime;
        debug { "Last modified: $mtime\n" };
    }
    return 1;
}

{ my $cache;
sub authors {
    my $self = shift;
    $cache = $self->_authors unless $cache;
    return $cache;
} }

sub _authors {
    my $self = shift;
    my $file = '00whois.xml';
    debug { "Parsing $file...\n" };
    my $path = $self->file_path( $file );

    use XML::SAX::ParserFactory;
    my $handler = CPAN2RT::UsersSAXParser->new();
    my $p = XML::SAX::ParserFactory->parser(Handler => $handler);

    open my $fh, "<:raw", $path or die "Couldn't open '$path': $!";
    my $res = $p->parse_file( $fh );
    close $fh;

    return $res;
}

{ my $cache;
sub permissions {
    my $self = shift;
    $cache = $self->_permissions unless $cache;
    return $cache;
} }

sub _permissions {
    my $self = shift;
    my $file = '06perms.txt';
    debug { "Parsing $file...\n" };
    my $path = $self->file_path( $file );
    open my $fh, "<:utf8", $path or die "Couldn't open '$path': $!";

    $self->skip_header( $fh );

    my %res;
    while ( my $str = <$fh> ) {
        chomp $str;

        my ($module, $cpanid, $permission) = (split /\s*,\s*/, $str);
        unless ( $module && $cpanid ) {
            debug { "couldn't parse '$str' from '$file'\n" };
            next;
        }
        $res{ $module } ||= [];
        push @{ $res{ $module } }, $cpanid;
    }
    close $fh;

    return \%res;
}

{ my $cache;
sub module2file {
    my $self = shift;
    $cache = $self->_module2file() unless $cache;
    return $cache;
} }

sub _module2file {
    my $self = shift;

    my %res;
    $self->for_mapped_distributions( sub { $res{ $_[0] } = $_[2] } );
    return \%res;
}

sub for_mapped_distributions {
    my $self = shift;
    my $callback = shift;

    my $file = '02packages.details.txt';
    debug { "Parsing $file...\n" };
    my $path = $self->file_path( $file );
    open my $fh, "<:utf8", $path or die "Couldn't open '$path': $!";

    $self->skip_header( $fh );

    while ( my $str = <$fh> ) {
        chomp $str;

        my ($module, $mver, $file) = split /\s+/, $str;
        unless ( $module && $file ) {
            debug { "couldn't parse '$str' in '$file'" };
            next;
        }
        $callback->( $module, $mver, $file );
    }
    close $fh;
}

sub for_all_distributions {
    my $self = shift;
    my $callback = shift;

    my $file = 'find-ls';
    debug { "Parsing $file...\n" };
    my $path = $self->file_path( $file );
    open my $fh, "<:utf8", $path or die "Couldn't open '$path': $!";

    while ( my $str = <$fh> ) {
        next if $str =~ /^\d+\s+0\s+l\s+1/; # skip symbolic links
        chomp $str;

        my ($mode, $file) = (split /\s+/, $str)[2, -1];
        next if index($mode, 'x') >= 0; # skip executables (dirs)
        # we're only interested in files in authors/id/ dir
        next unless index($file, "authors/id/") == 0;
        next unless $file =~ /\.(bz2|zip|tgz|tar\.gz)$/i;

        my $info = $self->file2distinfo( $file )
            or next;

        $callback->( $info );
    }
    close $fh;
}

sub sync_authors {
    my $self = shift;
    my $force = shift;
    if ( !$force && !$self->is_new_file( '00whois.xml' ) ) {
        debug { "Skip syncing, file's not changed\n" };
        return (1);
    }

    my ($i, @errors) = (0);
    my $authors = $self->authors;
    while ( my ($cpanid, $meta) = each %$authors ) {
        my ($user, @msg) = $self->load_or_create_user( $cpanid, @{ $meta }{qw(fullname email)} );
        push @errors, @msg unless $user;

        DBIx::SearchBuilder::Record::Cachable->FlushCache unless ++$i % 100;
    }
    return (undef, @errors) if @errors;
    return (1);
}

sub sync_bugtracker {
    my $self = shift;

    debug { "Syncing alternate bug trackers\n" };

    my $has_bugtracker = $self->_sync_bugtracker_cpan2rt();

    $self->_sync_bugtracker_rt2cpan( $has_bugtracker );
}

=head2 _sync_bugtracker_cpan2rt

Sync DistributionBugtracker info from CPAN to RT.
This updates and adds to existing queues.

=cut

sub _sync_bugtracker_cpan2rt {
    my $self = shift;

    require ElasticSearch;
    my $es = ElasticSearch->new(
        servers     => 'fastapi.metacpan.org',
        no_refresh  => 1,
        transport   => 'http',
    );
    $es->transport->client->agent(join "/", __PACKAGE__, $VERSION);

    # Ian Norton wrote:
    # > Thomas Sibley wrote:
    # >> 2) Is it feasible to further limit returned [MetaCPAN] results to those where
    # >> .web or .mailto lacks "rt.cpan.org"?
    # > 
    # > Spoke to the metacpan guys on irc and seemingly it would be expensive to
    # > do this server side.  Request submitted to have the fields added as full
    # > text searchable - https://github.com/CPAN-API/cpan-api/issues/238
    # > following a chat with clintongormley.  Once that's done then we can
    # > improve this.

    # Pull the details of distribution bugtrackers
    my $scroller = $es->scrolled_search(
        query       => { match_all => {} },
        size        => 100,
        search_type => 'scan',
        scroll      => '5m',
        index       => 'v1',
        type        => 'release',
        fields  => [ "distribution" , "resources.bugtracker" ],
        filter  => {
            and => [{
                or => [
                    {
                        and => [
                            { exists => { field => "resources.bugtracker.mailto" }},
                            { not    => { query => { wildcard => { "resources.bugtracker.mailto" => '*rt.cpan.org*' }}}},
                        ],
                    },{
                        and => [
                            { exists => { field => "resources.bugtracker.web" }},
                            { not    => { query => { wildcard => { "resources.bugtracker.web" => '*://rt.cpan.org*' }}}},
                        ],
                    }
                ]},
                { term => { "release.status"   => "latest" }},
                { term => { "release.maturity" => "released" }},
            ],
        },
    );

    unless ( defined($scroller) ) {
        die("Request to api.metacpan.org failed.\n");
    }

    debug { "Requested data from api.metacpan.org\n" };

    my @has_bugtracker;

    # Iterate the results from MetaCPAN
    while ( my $result = $scroller->next ) {
        my $bugtracker = {};

        # Record data
        my $dist   = $result->{"fields"}->{"distribution"};
        my $mailto = $result->{"fields"}->{"resources.bugtracker"}->{"mailto"};
        my $web    = $result->{"fields"}->{"resources.bugtracker"}->{"web"};

        if (!$dist) {
            #debug { "Result without distribution: " . Data::Dumper::Dumper($result) };
            next;
        }

        debug { "Got '$dist' ($mailto, $web)" };

        # Email based alternative - we don't care if this is rt.cpan.org
        if(defined($mailto) && !($mailto =~ m/rt\.cpan\.org/)) {
            $bugtracker->{"mailto"} = $mailto;
        }

        # Web based alternative - we don't care if this is rt.cpan.org
        if(defined($web) && !($web =~ m/rt\.cpan\.org/)) {
            $bugtracker->{"web"} = $web;
        }

        unless (keys %$bugtracker) {
            debug { "Got '$dist' from metacpan, but no alternate bugtracker found" };
            next;
        }

        # Fetch the queue
        my $queue = $self->load_queue( $dist );
        unless( $queue ) {
            debug { "No queue for dist '$dist'" };
            next;
        }

        push @has_bugtracker, $queue->id;

        # Get the existing bugtracker from the queue and log if it's changing
        my $attr = $queue->DistributionBugtracker();

        # Set this if we need to update when we're done
        my $update = 0;

        # If the attr is defined, then check it hasn't changed.
        if(defined($attr)) {

            debug { "Bugtracker set for distribution '$dist'.  Has it changed?\n" };

            foreach my $method (keys(%{$bugtracker})) {

                if(ref($attr) eq "HASH") {
                    # If this method has changed, log it
                    if(defined($attr->{$method}) && $attr->{$method} ne $bugtracker->{$method}) {
                        debug { "Changing DistributionBugtracker for $dist from '" . $attr->{$method} . "' to '" . $bugtracker->{$method} . "'\n" };
                        $update = 1;
                    } else {
                        debug { "Bugtracker $method for $dist is the same.  Skipping.\n" };
                    }
                }

                else {
                    # Hmm, something odd happened.  Data in the db is wrong, fix it.
                    debug { "Bugtracker data in database looks corrupt?  Updating." };
                    $update = 1;
                }
            }
        }

        else {
            debug { "Setting DistributionBugtracker for $dist from nothing\n" };
            $update = 1;
        }


        if($update) {
            # Set the queue bugtracker
            $queue->SetDistributionBugtracker( $bugtracker );
        }
    }

    return \@has_bugtracker;
}

=head2 _sync_bugtracker_rt2cpan

Sync DistributionBugtracker info from RT to CPAN.
This deletes records that are no longer needed or missing in the source.

=cut

sub _sync_bugtracker_rt2cpan {
    my $self = shift;
    my $has_bugtracker = shift;
    my $name = "DistributionBugtracker";

    # Find queues with a DistributionBugtracker attribute
    my $queues = RT::Queues->new( $RT::SystemUser );
    $queues->Limit(
        FIELD       => 'id',
        OPERATOR    => 'NOT IN',
        VALUE       => $has_bugtracker,
    );

    my $attributes = $queues->Join(
        ALIAS1 => 'main',
        FIELD1 => 'id',
        TABLE2 => 'Attributes',
        FIELD2 => 'ObjectId',
    );
    $queues->Limit(
        ALIAS   => $attributes,
        FIELD   => "ObjectType",
        VALUE   => "RT::Queue",
    );
    $queues->Limit(
        ALIAS   => $attributes,
        FIELD   => "Name",
        VALUE   => $name,
    );

    # Iterate over queues from RT
    while(my $queue = $queues->Next()) {
        # Delete the attribute, it's no longer needed.
        debug { "Deleting alternate bugtracker attribute for " . $queue->Name };
        $queue->DeleteAttribute( $name );
    }
}

sub sync_distributions {
    my $self = shift;
    my $force = shift;
    if ( !$force && !$self->is_new_file( '02packages.details.txt' ) ) {
        debug { "Skip syncing, file's not changed\n" };
        return (1);
    }

    my @errors;

    my $last = ''; my $i = 0;
    my $syncer = sub {
        my $file = $_[2];
        return if $last eq $file;

        $last = $file;

        my $info = $self->file2distinfo( "authors/id/$file" )
            or return;

        my ($queue, @msg) = $self->load_or_create_queue( $info->dist );
        push @errors, @msg unless $queue;

        # we don't sync version here as sync_versions does this better

        DBIx::SearchBuilder::Record::Cachable->FlushCache unless ++$i % 100;
    };
    $self->for_mapped_distributions( $syncer );

    return (undef, @errors) if @errors;
    return (1);
}

sub sync_versions {
    my $self = shift;
    my $force = shift;
    if ( !$force && !$self->is_new_file( '02packages.details.txt' ) ) {
        debug { "Skip syncing, file's not changed\n" };
        return (1);
    }

    my $i = 0;
    my @errors;
    my ($last_dist, @last_versions) = ('');
    my $syncer = sub {
        return unless $last_dist && @last_versions;

        my $queue = $self->load_queue( $last_dist );
        unless ( $queue ) {
            debug { "No queue for dist '$last_dist'" };
            return;
        }

        my ($status, @msg) = $self->add_versions( $queue, @last_versions );
        push @errors, @msg unless $status;

        DBIx::SearchBuilder::Record::Cachable->FlushCache unless ++$i % 100;
    };
    my $collector = sub {
        my $info = shift;

        my $dist = $info->dist;
        if ( $dist ne $last_dist ) {
            $syncer->();
            $last_dist = $dist;
            @last_versions = ();
        }

        push @last_versions, $info->version;
    };

    $self->for_all_distributions( $collector );
    $syncer->(); # last portion

    return (undef, @errors) if @errors;
    return (1);
}

sub sync_maintainers {
    my $self = shift;
    my $force = shift;
    if ( !$force && !$self->is_new_file( '06perms.txt' ) ) {
        debug { "Skip syncing, file's not changed\n" };
        return (1);
    }

    my $m2f = $self->module2file;
    my $perm = $self->permissions;

    my %res;
    while ( my ($module, $maint) = each %$perm ) {
        my $file = $m2f->{ $module };
        next unless $file;

        my $info = $self->file2distinfo( "authors/id/$file" )
            or next;

        push @{ $res{ $info->dist } ||= [] }, @$maint;
    }

    my $i = 0;
    my @errors = ();
    while ( my ($dist, $maint) = each %res ) {
        my ($queue, @msg) = $self->load_or_create_queue( $dist );
        unless ( $queue ) {
            push @errors, @msg;
            next;
        }

        my $status;
        ($status, @msg) = $self->set_maintainers( $queue, @$maint );
        push @errors, @msg unless $status;

        DBIx::SearchBuilder::Record::Cachable->FlushCache unless ++$i % 100;
    }
    %res = ();
    return (undef, @errors) if @errors;
    return (1);
}

sub current_maintainers {
    my $self = shift;
    my $queue = shift;

    my $users = $queue->AdminCc->UserMembersObj;
    $users->OrderByCols;
    return map uc $_->Name, @{ $users->ItemsArrayRef };
}

sub filter_maintainers {
    my $self = shift;
    my $authors = $self->authors;
    return grep { ($authors->{$_}{'type'}||'') eq 'author' } @_;
}

sub set_maintainers {
    my $self = shift;
    my $queue   = shift;

    my @maints  = $self->filter_maintainers( @_ );
    my @current = $self->current_maintainers( $queue );

    my @errors;

    my $set = List::Compare->new( '--unsorted', \@current, \@maints );
    foreach ( $set->get_unique ) {
        debug { "Going to delete $_ from maintainers of ". $queue->Name };
        my ($status, @msg) = $self->del_maintainer( $queue, $_, 'force' );
        push @errors, @msg unless $status;
    }
    foreach ( $set->get_complement ) {
        debug { "Going to add $_ as maintainer of ". $queue->Name };
        my ($status, @msg) = $self->add_maintainer( $queue, $_, 'force' );
        push @errors, @msg unless $status;
    }

    return (undef, @errors) if @errors;
    return (1);
}

sub add_maintainer {
    my $self = shift;
    my $queue = shift;
    my $user  = shift;
    my $force = shift || 0;

    unless ( ref $user ) {
        my $tmp = RT::User->new( $RT::SystemUser );
        $tmp->LoadByCols( Name => $user );
        return (undef, "Couldn't load user '$user'")
            unless $tmp->id;

        $user = $tmp;
    }
    unless ( $user->id ) {
        return (undef, "Empty user object");
    }

    if ( !$force && $queue->IsAdminCc( $user->PrincipalId ) ) {
        debug {  $user->Name ." is already maintainer of '". $queue->Name ."'\n"  };
        return (1);
    }

    my ($status, $msg) = $queue->AddWatcher(
        Type        => 'AdminCc',
        PrincipalId => $user->PrincipalId,
    );
    unless ( $status ) {
        $msg = "Couldn't add ". $user->Name ." as AdminCc for ". $queue->Name .": $msg\n";
        return (undef, $msg);
    } else {
        debug { "Added ". $user->Name ." as maintainer of '". $queue->Name ."'\n" };
    }
    return (1);
}

sub del_maintainer {
    my $self = shift;
    my $queue = shift;
    my $user  = shift;
    my $force = shift;

    unless ( ref $user ) {
        my $tmp = RT::User->new( $RT::SystemUser );
        $tmp->LoadByCols( Name => $user );
        return (undef, "Couldn't load user '$user'")
            unless $tmp->id;

        $user = $tmp;
    }
    unless ( $user->id ) {
        return (undef, "Empty user object");
    }

    if ( !$force && !$queue->IsAdminCc( $user->PrincipalId ) ) {
        debug {  $user->Name ." is not maintainer of '". $queue->Name ."'. Skipping...\n"  };
        return (1);
    }

    my ($status, $msg) = $queue->DeleteWatcher(
        Type        => 'AdminCc',
        PrincipalId => $user->PrincipalId,
    );
    unless ( $status ) {
        $msg = "Couldn't delete ". $user->Name
            ." from AdminCc list of '". $queue->Name ."': $msg\n";
        return (undef, $msg);
    } else {
        debug { "Deleted ". $user->Name ." from maintainers of '". $queue->Name ."'\n" };
    }
    return (1);
}

sub add_versions {
    my $self = shift;
    my ($queue, @versions) = @_;
    @versions = uniq grep defined && length, @versions;

    my @errors;
    foreach my $name ( "Broken in", "Fixed in" ) {
        my ($cf, $msg) = $self->load_or_create_version_cf( $queue, $name );
        unless ( $cf ) {
            push @errors, $msg;
            next;
        }

        # Unless it's a new value, don't add it
        my %old = map { $_->Name => 1 } @{ $cf->Values->ItemsArrayRef };
        foreach my $version ( @versions ) {
            if ( exists $old{$version} ) {
                debug { "Version '$version' exists (not adding)\n" };
                next;
            }

            my ($val, $msg) = $cf->AddValue(
                Name          => $version,
                Description   => "Version $version",
                SortOrder     => 0,
            );
            unless ( $val ) {
                $msg = "Failed to add value '$version' to CF $name"
                    ." for queue ". $queue->Name .": $msg";
                debug {  $msg  };
                push @errors, $msg;
            }
            else {
                debug { "Added version '$version' into '$name' list for queue '". $queue->Name ."'\n" };
            }
        }
    }
    return (undef, @errors) if @errors;
    return (1);
}

sub load_or_create_user {
    my $self = shift;
    my ($cpanid, $realname, $email) = @_;

    my $bycpanid = RT::User->new($RT::SystemUser);
    $bycpanid->LoadByCol( Name => $cpanid );

    # WARNING: when MergeUser extension is used then the same user records
    # will be loaded even when there are multiple records in the DB
    $email = $self->parse_email_address( $email ) || "$cpanid\@cpan.org";
    my $byemail = RT::User->new( $RT::SystemUser );
    $byemail->LoadByEmail( $email );

    if ( $bycpanid->id && (($byemail->id && $bycpanid->id == $byemail->id) || !$byemail->id) ) {
        # the same users, both cpanid and email...
        # or email change, so no user with new email...
        #
        # XXX: as we have no way to detect email changes on PAUSE
        # then we set email to the public version from PAUSE only when
        # user in RT has no email. The same applies to name.
        $bycpanid->SetEmailAddress( $email )
            unless $bycpanid->EmailAddress;
        $bycpanid->SetRealName( $realname )
            unless $bycpanid->RealName;
        return $bycpanid;
    }
    elsif ( $bycpanid->id && $byemail->id ) {
        # both exist, but different
        # XXX: merge them
        debug {
            sprintf "WARNING: Two RT users for the same PAUSE author: %s (%d) and %s (%d)\n",
                    $bycpanid->Name, $bycpanid->id, $byemail->EmailAddress, $byemail->id
        };
        return $bycpanid;
    }
    elsif ( $byemail->id ) {
        # there is already user with that address, but different CPANID
        my ($new, $msg) = $self->create_user( $cpanid, $realname );
        return ($new, $msg) unless $new;

        if ( $new->can('MergeInto') ) {
            debug { "Merging user @{[$new->Name]} into @{[$byemail->Name]}...\n" };
            my ($ok, $msg) = $new->MergeInto( $byemail );
            if ($ok) {
                $byemail->SetPrivileged(1);
            } else {
                debug { "Couldn't merge user @{[$new->id]} into @{[$byemail->id]}: $msg" };
            }
        } else {
            debug {
                "WARNING: Couldn't merge user @{[$new->Name]} into @{[$byemail->Name]}."
                ." Extension is not installed.\n" };
        }
        return ($new);
    }

    return $self->create_user($cpanid, $realname, $email);
}

sub create_user {
    my $self = shift;
    my ($username, $realname, $email) = @_;

    my $user = RT::User->new( $RT::SystemUser );
    my ($val, $msg) = $user->Create(
        Name          => $username,
        RealName      => $realname,
        EmailAddress  => $email,
        Privileged    => 1
    );

    unless ( $val ) {
        $msg = "Failed to create user $username: $msg";
        debug { "FAILED! $msg\n" };
        return (undef, $msg);
    }
    else {
        debug { "Created user $username... " };
    }

    return ($user)
}

sub load_queue {
    my $self = shift;
    my $dist = shift;

    my $queue = RT::Queue->new( $RT::SystemUser );
    $queue->Load( $dist );
    return undef unless $queue->id;

    debug { "Found queue #". $queue->id ." for dist ". $queue->Name ."\n" };
    return $queue;
}

sub load_or_create_queue {
    my $self = shift;
    my $dist = shift;

    my $queue = $self->load_queue( $dist );
    return $queue if $queue;

    $queue = RT::Queue->new( $RT::SystemUser );
    my ($status, $msg) = $queue->Create(
        Name               => $dist,
        Description        => "Bugs in $dist",
        CorrespondAddress  => "bug-$dist\@rt.cpan.org",
        CommentAddress     => "comment-$dist\@rt.cpan.org",
    );
    unless ( $status ) {
        return (undef, "Couldn't create queue '$dist': $msg\n");
    }
    debug { "Created queue #". $queue->id ." for dist ". $queue->Name ."\n" };
    return $queue;
}

sub load_or_create_version_cf {
    my $self = shift;
    my ($queue, $name) = @_;

    my $cfs = RT::CustomFields->new( $RT::SystemUser );
    $cfs->Limit( FIELD => 'Name', VALUE => $name );
    $cfs->LimitToQueue( $queue->id );
    $cfs->{'find_disabled_rows'} = 0;   # This is why we don't simply do a LoadByName
    $cfs->OrderByCols; # don't sort things
    $cfs->RowsPerPage( 1 );

    my $cf = $cfs->First;
    unless ( $cf && $cf->id ) {
        return $self->create_version_cf( $queue, $name );
    }

    return ($cf);
}

sub create_version_cf {
    my $self = shift;
    my ($queue, $name) = @_;

    my $cf = RT::CustomField->new( $RT::SystemUser );
    debug { "creating custom field $name..." };
    my ($val, $msg) = $cf->Create(
        Name            => $name,
        TypeComposite   => 'Select-0',    
        # This is a much clearer way of associating a CF
        # with a queue, except that it's not as efficient
        # as the method below...
        # 
        #Queue           => $queue->Id,
        #
        # So instead we're going to set the lookup type here...
        #
        LookupType   => 'RT::Queue-RT::Ticket',
    );
    unless ( $val ) {
        debug { "FAILED!  $msg\n" };
        return (undef, "Failed to create CF $name for queue "
                        . $queue->Name
                        . ": $msg");
    }
    else {
        debug { "ok\n" };
    }

    #
    # ... and associate with the queue down here.
    #
    # This is the other way of associating a CF with a queue.  Unlike
    # the much more clear method above, it doesn't have to fetch the
    # queue object again.  And since this is an import, we do kinda
    # care about that stuff...
    #
    ($val, $msg) = $cf->AddToObject( $queue );
    unless ( $val ) {
        $msg = "Failed to link CF $name with queue " . $queue->Name . ": $msg";
        debug { $msg };
        $cf->Delete;
        return (undef, $msg);
    }
    return ($cf);
}

sub parse_email_address {
    my $self = shift;
    my $string = shift;
    return undef unless defined $string && length $string;
    return undef if uc($string) eq 'CENSORED';

    my $address = (grep defined, Email::Address->parse( $string || '' ))[0];
    return undef unless defined $address;
    return $address->address;
}

sub file2distinfo {
    my $self = shift;
    my $file = shift or return undef;

    my $info = CPAN::DistnameInfo->new( $file );
    my $dist = $info->dist;
    unless ( $dist ) {
        debug { "Couldn't parse distribution name from '$file'\n" };
        return undef;
    }
    if ( $dist =~ /^(parrot|perl)$/i ) {
        debug { "Skipping $dist as it's hard coded to be skipped." };
        return undef;
    }
    return $info;
}

sub file_path {
    my $self = shift;
    my $file = shift;
    my $res = $file;
    $res =~ s/.*\///; # strip leading dirs
    if ( my $dir = $self->{'datadir'} ) {
        require File::Spec;
        $res = File::Spec->catfile( $dir, $res );
    }
    return $res;
}

sub is_new_file {
    my $self = shift;
    my $new = $self->file_path( shift );
    my $old = $new .'.old';
    return 1 unless -e $old; 
    return (stat $new)[9] > (stat $old)[9]? 1 : 0;
}

sub backup_file {
    my $self = shift;
    my $old = shift;
    my $new = $old .'.old';
    rename $old, $new if -e $old;
}

sub skip_header {
    my $self = shift;
    my $fh = shift;
    while ( my $str = <$fh> ) {
        return if $str =~ /^\s*$/;
    }
}

sub debug(&) {
    return unless $DEBUG;
    print STDERR map { /\n$/? $_ : $_."\n" } $_[0]->();
}

1;

package CPAN2RT::UsersSAXParser;
use base qw(XML::SAX::Base);

sub start_document {
    my ($self, $doc) = @_;
    $self->{'res'} = {};
}

sub start_element {
    my ($self, $el) = @_;
    my $name = $el->{LocalName};
    return if $name ne 'cpanid' && !$self->{inside};

    if ( $name eq 'cpanid' ) {
        $self->{inside} = 1;
        $self->{tmp} = [];
        return;
    } else {
        $self->{inside_prop} = 1;
    }

    push @{ $self->{'tmp'} }, $name, '';
}

sub characters {
    my ($self, $el) = @_;
    $self->{'tmp'}[-1] .= $el->{Data} if $self->{inside_prop};
}

sub end_element {
    my ($self, $el) = @_;
    $self->{inside_prop} = 0;

    my $name = $el->{LocalName};

    if ( $name eq 'cpanid' ) {
        $self->{inside} = 0;
        my %rec = map Encode::decode_utf8($_), @{ delete $self->{'tmp'} };
        $self->{'res'}{ delete $rec{'id'} } = \%rec;
    }
}

sub end_document {
    my ($self) = @_;
    return $self->{'res'};
}

1;

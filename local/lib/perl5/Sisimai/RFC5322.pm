package Sisimai::RFC5322;
use feature ':5.10';
use strict;
use warnings;

# Regular expression of valid RFC-5322 email address(<addr-spec>)
my $Re = { 'rfc5322' => undef, 'ignored' => undef, 'domain' => undef, };

BUILD_REGULAR_EXPRESSIONS: {
    # See http://www.ietf.org/rfc/rfc5322.txt
    #  or http://www.ex-parrot.com/pdw/Mail-RFC822-Address.html ...
    #   addr-spec       = local-part "@" domain
    #   local-part      = dot-atom / quoted-string / obs-local-part
    #   domain          = dot-atom / domain-literal / obs-domain
    #   domain-literal  = [CFWS] "[" *([FWS] dcontent) [FWS] "]" [CFWS]
    #   dcontent        = dtext / quoted-pair
    #   dtext           = NO-WS-CTL /     ; Non white space controls
    #                     %d33-90 /       ; The rest of the US-ASCII
    #                     %d94-126        ;  characters not including "[",
    #                                     ;  "]", or "\"
    my $atom           = qr;[a-zA-Z0-9_!#\$\%&'*+/=?\^`{}~|\-]+;o;
    my $quoted_string  = qr/"(?:\\[^\r\n]|[^\\"])*"/o;
    my $domain_literal = qr/\[(?:\\[\x01-\x09\x0B-\x0c\x0e-\x7f]|[\x21-\x5a\x5e-\x7e])*\]/o;
    my $dot_atom       = qr/$atom(?:[.]$atom)*/o;
    my $local_part     = qr/(?:$dot_atom|$quoted_string)/o;
    my $domain         = qr/(?:$dot_atom|$domain_literal)/o;

    $Re->{'rfc5322'} = qr/$local_part[@]$domain/o;
    $Re->{'ignored'} = qr/$local_part[.]*[@]$domain/o;
    $Re->{'domain'}  = qr/$domain/o;
}

my $LONGHEADERS = __PACKAGE__->LONGFIELDS;
my $HEADERINDEX = {};
my $HEADERTABLE = {
    'messageid' => ['Message-Id'],
    'subject'   => ['Subject'],
    'listid'    => ['List-Id'],
    'date'      => ['Date', 'Posted-Date', 'Posted', 'Resent-Date'],
    'addresser' => [
        'From', 'Return-Path', 'Reply-To', 'Errors-To', 'Reverse-Path', 
        'X-Postfix-Sender', 'Envelope-From', 'X-Envelope-From',
    ],
    'recipient' => [
        'To', 'Delivered-To', 'Forward-Path', 'Envelope-To',
        'X-Envelope-To', 'Resent-To', 'Apparently-To'
    ],
};

BUILD_FLATTEN_RFC822HEADER_LIST: {
    # Convert $HEADER: hash reference to flatten hash reference for being
    # called from Sisimai::MTA::*
    for my $v ( values %$HEADERTABLE ) {
        $HEADERINDEX->{ lc $_ } = 1 for @$v;
    }
}

sub HEADERFIELDS {
    # Grouped RFC822 headers
    # @param    [String] group  RFC822 Header group name
    # @return   [Array,Hash]    RFC822 Header list
    my $class = shift;
    my $group = shift || return $HEADERINDEX;
    return $HEADERTABLE->{ $group } if exists $HEADERTABLE->{ $group };
    return $HEADERTABLE;
}

sub LONGFIELDS {
    # Fields that might be long
    # @return   [Hash] Long filed(email header) list
    return { 'to' => 1, 'from' => 1, 'subject' => 1, 'message-id' => 1 };
}

sub is_emailaddress {
    # Check that the argument is an email address or not
    # @param    [String] email  Email address string
    # @return   [Integer]       0: Not email address
    #                           1: Email address
    my $class = shift;
    my $email = shift // return 0;

    return 0 if $email =~ m/(?:[\x00-\x1f]|\x1f)/;
    return 1 if $email =~ $Re->{'ignored'};
    return 0;
}

sub is_domainpart {
    # Check that the argument is an domain part of email address or not
    # @param    [String] dpart  Domain part of the email address
    # @return   [Integer]       0: Not domain part
    #                           1: Valid domain part
    my $class = shift;
    my $dpart = shift // return 0;

    return 0 if $dpart =~ m/(?:[\x00-\x1f]|\x1f)/;
    return 0 if $dpart =~ m/[@]/;
    return 1 if $dpart =~ $Re->{'domain'};
    return 0;
}

sub is_mailerdaemon {
    # Check that the argument is mailer-daemon or not
    # @param    [String] email  Email address
    # @return   [Integer]       0: Not mailer-daemon
    #                           1: Mailer-daemon
    my $class = shift;
    my $email = shift // return 0;
    my $rxmds = qr{(?>
         (?:mailer-daemon|postmaster)[@]
        |[<(](?:mailer-daemon|postmaster)[)>]
        |\A(?:mailer-daemon|postmaster)\z
        |[ ]?mailer-daemon[ ]
        )
    }xi;
    return 1 if $email =~ $rxmds;
    return 0;
}

sub received {
    # Convert Received headers to a structured data
    # @param    [String] argv1  Received header
    # @return   [Array]         Received header as a structured data
    my $class = shift;
    my $argv1 = shift || return [];
    my $hosts = [];
    my $value = {
        'from' => '',
        'by'   => '',
    };

    # Received: (qmail 10000 invoked by uid 999); 24 Apr 2013 00:00:00 +0900
    return [] if $argv1 =~ m/qmail[ \t]+.+invoked[ \t]+/;

    if( $argv1 =~ m/\Afrom[ \t]+(.+)[ \t]+by[ \t]+([^ ]+)/ ) {
        # Received: from localhost (localhost)
        #   by nijo.example.jp (V8/cf) id s1QB5ma0018057;
        #   Wed, 26 Feb 2014 06:05:48 -0500
        $value->{'from'} = $1;
        $value->{'by'}   = $2;

    } elsif( $argv1 =~ m/\bby[ \t]+([^ ]+)(.+)/ ) {
        # Received: by 10.70.22.98 with SMTP id c2mr1838265pdf.3; Fri, 18 Jul 2014
        #   00:31:02 -0700 (PDT)
        $value->{'from'} = $1.$2;
        $value->{'by'}   = $1;
    }

    if( $value->{'from'} =~ m/ / ) {
        # Received: from [10.22.22.222] (smtp-gateway.kyoto.ocn.ne.jp [192.0.2.222])
        #   (authenticated bits=0)
        #   by nijo.example.jp (V8/cf) with ESMTP id s1QB5ka0018055;
        #   Wed, 26 Feb 2014 06:05:47 -0500
        my @received = split(' ', $value->{'from'});
        my @namelist = ();
        my @addrlist = ();
        my $hostname = '';
        my $hostaddr = '';

        for my $e ( @received ) {
            # Received: from [10.22.22.222] (smtp-gateway.kyoto.ocn.ne.jp [192.0.2.222])
            if( $e =~ m/\A[(\[]\d+[.]\d+[.]\d+[.]\d+[)\]]\z/ ) {
                # [192.0.2.1] or (192.0.2.1)
                $e =~ y/[]()//d;
                push @addrlist, $e;

            } else {
                # hostname
                $e =~ y/()//d;
                push @namelist, $e;
            }
        }

        for my $e ( @namelist ) {
            # 1. Hostname takes priority over all other IP addresses
            next unless $e =~ m/[.]/;
            $hostname = $e;
            last;
        }

        if( length($hostname) == 0 ) {
            # 2. Use IP address as a remote host name
            for my $e ( @addrlist ) {
                # Skip if the address is a private address
                next if $e =~ m/\A(?:10|127)[.]/;
                next if $e =~ m/\A172[.](?:1[6-9]|2[0-9]|3[0-1])[.]/;
                next if $e =~ m/\A192[.]168[.]/;
                $hostaddr = $e;
                last;
            }
        }

        $value->{'from'} = $hostname || $hostaddr || $addrlist[-1];
    }

    for my $e ( 'from', 'by' ) {
        # Copy entries into $hosts
        next unless defined $value->{ $e };
        $value->{ $e } =~ y/()[];?//d;
        push @$hosts, $value->{ $e };
    }
    return $hosts;
}

sub weedout {
    # Weed out rfc822/message header fields excepct necessary fields
    # @param    [Array] argv1  each line divided message/rc822 part
    # @return   [String]       Selected fields
    my $class = shift;
    my $argv1 = shift // return undef;
    return undef unless ref $argv1 eq 'ARRAY';

    my $rfc822next = { 'from' => 0, 'to' => 0, 'subject' => 0 };
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $previousfn = '';    # (String) Previous field name

    for my $e ( @$argv1 ) {
        # After "message/rfc822"
        if( $e =~ m/\A([-0-9A-Za-z]+?)[:][ ]*.+/ ) {
            # Get required headers
            my $lhs = lc $1;
            $previousfn = '';
            next unless exists $HEADERINDEX->{ $lhs };

            $previousfn  = $lhs;
            $rfc822part .= $e."\n";

        } elsif( $e =~ m/\A[ \t]+/ ) {
            # Continued line from the previous line
            next if $rfc822next->{ $previousfn };
            $rfc822part .= $e."\n" if exists $LONGHEADERS->{ $previousfn };

        } else {
            # Check the end of headers in rfc822 part
            next unless exists $LONGHEADERS->{ $previousfn };
            next if length $e;
            $rfc822next->{ $previousfn } = 1;
        }
    }
    return \$rfc822part;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::RFC5322 - Email address related utilities

=head1 SYNOPSIS

    use Sisimai::RFC5322;

    print Sisimai::RFC5322->is_emailaddress('neko@example.jp');    # 1
    print Sisimai::RFC5322->is_domainpart('example.jp');           # 1
    print Sisimai::RFC5322->is_mailerdaemon('neko@example.jp');    # 0

=head1 DESCRIPTION

Sisimai::RFC5322 provide methods for checking email address.

=head1 CLASS METHODS

=head2 C<B<is_emailaddress(I<email address>)>>

C<is_emailaddress()> checks the argument is valid email address or not.

    print Sisimai::RFC5322->is_emailaddress('neko@example.jp');  # 1
    print Sisimai::RFC5322->is_emailaddress('neko%example.jp');  # 0

    my $addr_with_name = [
        'Stray cat <neko@example.jp',
        '=?UTF-8?B?55m954yr?= <shironeko@example.co.jp>',
    ];
    for my $e ( @$addr_with_name ) {
        print Sisimai::RFC5322->is_emailaddress($e); # 1
    }

=head2 C<B<is_domainpart(I<Domain>)>>

C<is_domainpart()> checks the argument is valid domain part of a email address
or not.

    print Sisimai::RFC5322->is_domainpart('neko@example.jp');  # 0
    print Sisimai::RFC5322->is_domainpart('neko.example.jp');  # 1

=head2 C<B<is_domainpart(I<Domain>)>>

C<is_mailerdaemon()> checks the argument is mailer-daemon or not.

    print Sisimai::RFC5322->is_mailerdaemon('neko@example.jp');          # 0
    print Sisimai::RFC5322->is_mailerdaemon('mailer-daemon@example.jp'); # 1

=head2 C<B<received(I<String>)>>

C<received()> returns array reference which include host names in the Received
header.

    my $v = 'from mx.example.org (c1.example.net [192.0.2.1]) by mx.example.jp';
    my $r = Sisimai::RFC5322->received($v);

    warn Dumper $r; 
    $VAR1 = [
        'mx.example.org',
        'mx.example.jp'
    ];

=head2 C<B<weedout(I<Array>)>>

C<weedout()> returns string including only necessary fields from message/rfc822
part. This method is called from only Sisimai::MTA/MSP modules.

    my $v = <<'EOM';
    From: postmaster@nyaan.example.org
    To: kijitora@example.jp
    Subject: Delivery failure
    X-Mailer: Neko mailer v2.22
    EOM

    my $r = Sisimai::RFC5322->weedout([split("\n", $v)]);
    print $$r;

    From: postmaster@nyaan.example.org
    To: kijitora@example.jp
    Subject: Delivery failure

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2016 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut

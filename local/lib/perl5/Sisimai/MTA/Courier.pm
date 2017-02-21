package Sisimai::MTA::Courier;
use parent 'Sisimai::MTA';
use feature ':5.10';
use strict;
use warnings;

# http://www.courier-mta.org/courierdsn.html
# courier/module.dsn/dsn*.txt
my $Re0 = {
    'from'       => qr/Courier mail server at /,
    'subject'    => qr{(?:
         NOTICE:[ ]mail[ ]delivery[ ]status[.]
        |WARNING:[ ]delayed[ ]mail[.]
        )
    }x,
    'message-id' => qr/\A[<]courier[.][0-9A-F]+[.]/,
};
my $Re1 = {
    'begin'  => qr{(?:
         DELAYS[ ]IN[ ]DELIVERING[ ]YOUR[ ]MESSAGE
        |UNDELIVERABLE[ ]MAIL
        )
    }x,
    'rfc822' => qr{\AContent-Type:[ ]*(?:
         message/rfc822
        |text/rfc822-headers
        )\z
    }x,
    'endof'  => qr/\A__END_OF_EMAIL_MESSAGE__\z/,
};
my $ReFailure = {
    # courier/module.esmtp/esmtpclient.c:526| hard_error(del, ctf, "No such domain.");
    'hostunknown' => qr{
        \ANo[ ]such[ ]domain[.]\z
    }x,
    # courier/module.esmtp/esmtpclient.c:531| hard_error(del, ctf,
    # courier/module.esmtp/esmtpclient.c:532|  "This domain's DNS violates RFC 1035.");
    'systemerror' => qr{
        \AThis[ ]domain's[ ]DNS[ ]violates[ ]RFC[ ]1035[.]\z
    }x,
};
my $ReDelayed = {
    # courier/module.esmtp/esmtpclient.c:535| soft_error(del, ctf, "DNS lookup failed.");
    'networkerror' => qr/\ADNS[ ]lookup[ ]failed[.]\z/,
};
my $Indicators = __PACKAGE__->INDICATORS;

sub pattern     { return $Re0 }
sub description { 'Courier MTA' }

sub scan {
    # Detect an error from Courier MTA
    # @param         [Hash] mhead       Message header of a bounce email
    # @options mhead [String] from      From header
    # @options mhead [String] date      Date header
    # @options mhead [String] subject   Subject header
    # @options mhead [Array]  received  Received headers
    # @options mhead [String] others    Other required headers
    # @param         [String] mbody     Message body of a bounce email
    # @return        [Hash, Undef]      Bounce data list and message/rfc822 part
    #                                   or Undef if it failed to parse or the
    #                                   arguments are missing
    # @since v4.0.0
    my $class = shift;
    my $mhead = shift // return undef;
    my $mbody = shift // return undef;
    my $match = 0;

    $match ||= 1 if $mhead->{'from'}    =~ $Re0->{'from'};
    $match ||= 1 if $mhead->{'subject'} =~ $Re0->{'subject'};
    if( defined $mhead->{'message-id'} ) {
        # Message-ID: <courier.4D025E3A.00001792@5jo.example.org>
        $match ||= 1 if $mhead->{'message-id'} =~ $Re0->{'message-id'};
    }
    return undef unless $match;

    my $dscontents = [__PACKAGE__->DELIVERYSTATUS];
    my @hasdivided = split("\n", $$mbody);
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $rfc822list = [];    # (Array) Each line in message/rfc822 part string
    my $blanklines = 0;     # (Integer) The number of blank lines
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $commandtxt = '';    # (String) SMTP Command name begin with the string '>>>'
    my $connvalues = 0;     # (Integer) Flag, 1 if all the value of $connheader have been set
    my $connheader = {
        'date'    => '',    # The value of Arrival-Date header
        'rhost'   => '',    # The value of Reporting-MTA header
        'lhost'   => '',    # The value of Received-From-MTA header
    };

    my $v = undef;
    my $p = '';

    for my $e ( @hasdivided ) {
        # Read each line between $Re1->{'begin'} and $Re1->{'rfc822'}.
        unless( $readcursor ) {
            # Beginning of the bounce message or delivery status part
            if( $e =~ $Re1->{'begin'} ) {
                $readcursor |= $Indicators->{'deliverystatus'};
                next;
            }
        }

        unless( $readcursor & $Indicators->{'message-rfc822'} ) {
            # Beginning of the original message part
            if( $e =~ $Re1->{'rfc822'} ) {
                $readcursor |= $Indicators->{'message-rfc822'};
                next;
            }
        }

        if( $readcursor & $Indicators->{'message-rfc822'} ) {
            # After "message/rfc822"
            unless( length $e ) {
                $blanklines++;
                last if $blanklines > 1;
                next;
            }
            push @$rfc822list, $e;

        } else {
            # Before "message/rfc822"
            next unless $readcursor & $Indicators->{'deliverystatus'};
            next unless length $e;

            if( $connvalues == scalar(keys %$connheader) ) {
                # Final-Recipient: rfc822; kijitora@example.co.jp
                # Action: failed
                # Status: 5.0.0
                # Remote-MTA: dns; mx.example.co.jp [192.0.2.95]
                # Diagnostic-Code: smtp; 550 5.1.1 <kijitora@example.co.jp>... User Unknown
                $v = $dscontents->[-1];

                if( $e =~ m/\A[Ff]inal-[Rr]ecipient:[ ]*(?:RFC|rfc)822;[ ]*([^ ]+)\z/ ) {
                    # Final-Recipient: rfc822; kijitora@example.co.jp
                    if( length $v->{'recipient'} ) {
                        # There are multiple recipient addresses in the message body.
                        push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                        $v = $dscontents->[-1];
                    }
                    $v->{'recipient'} = $1;
                    $recipients++;

                } elsif( $e =~ m/\A[Xx]-[Aa]ctual-[Rr]ecipient:[ ]*(?:RFC|rfc)822;[ ]*([^ ]+)\z/ ) {
                    # X-Actual-Recipient: RFC822; kijitora@example.co.jp
                    $v->{'alias'} = $1;

                } elsif( $e =~ m/\A[Aa]ction:[ ]*(.+)\z/ ) {
                    # Action: failed
                    $v->{'action'} = lc $1;

                } elsif( $e =~ m/\A[Ss]tatus:[ ]*(\d[.]\d+[.]\d+)/ ) {
                    # Status: 5.1.1
                    # Status:5.2.0
                    # Status: 5.1.0 (permanent failure)
                    $v->{'status'} = $1;

                } elsif( $e =~ m/\A[Rr]emote-MTA:[ ]*(?:DNS|dns);[ ]*(.+)\z/ ) {
                    # Remote-MTA: DNS; mx.example.jp
                    $v->{'rhost'} = lc $1;
                    if( $v->{'rhost'} =~ m/ / ) {
                        # Get the first element
                        $v->{'rhost'} = (split(' ', $v->{'rhost'}))[0];
                    }

                } elsif( $e =~ m/\A[Ll]ast-[Aa]ttempt-[Dd]ate:[ ]*(.+)\z/ ) {
                    # Last-Attempt-Date: Fri, 14 Feb 2014 12:30:08 -0500
                    $v->{'date'} = $1;

                } else {

                    if( $e =~ m/\A[Dd]iagnostic-[Cc]ode:[ ]*(.+?);[ ]*(.+)\z/ ) {
                        # Diagnostic-Code: SMTP; 550 5.1.1 <userunknown@example.jp>... User Unknown
                        $v->{'spec'} = uc $1;
                        $v->{'diagnosis'} = $2;

                    } elsif( $p =~ m/\A[Dd]iagnostic-[Cc]ode:[ ]*/ && $e =~ m/\A[ \t]+(.+)\z/ ) {
                        # Continued line of the value of Diagnostic-Code header
                        $v->{'diagnosis'} .= ' '.$1;
                        $e = 'Diagnostic-Code: '.$e;
                    }
                }
            } else {
                # This is a delivery status notification from marutamachi.example.org,
                # running the Courier mail server, version 0.65.2.
                #
                # The original message was received on Sat, 11 Dec 2010 12:19:57 +0900
                # from [127.0.0.1] (c10920.example.com [192.0.2.20])
                # 
                # ---------------------------------------------------------------------------
                #
                #                           UNDELIVERABLE MAIL
                #
                # Your message to the following recipients cannot be delivered:
                #
                # <kijitora@example.co.jp>:
                #    mx.example.co.jp [74.207.247.95]:
                # >>> RCPT TO:<kijitora@example.co.jp>
                # <<< 550 5.1.1 <kijitora@example.co.jp>... User Unknown
                #
                # ---------------------------------------------------------------------------
                if( $e =~ m/\A[>]{3}[ ]+([A-Z]{4})[ ]?/ ) {
                    # >>> DATA
                    next if $commandtxt;
                    $commandtxt = $1;

                } elsif( $e =~ m/\A[Rr]eporting-MTA:[ ]*(?:DNS|dns);[ ]*(.+)\z/ ) {
                    # Reporting-MTA: dns; mx.example.jp
                    next if $connheader->{'rhost'};
                    $connheader->{'rhost'} = lc $1;
                    $connvalues++;

                } elsif( $e =~ m/\A[Rr]eceived-[Ff]rom-MTA:[ ]*(?:DNS|dns);[ ]*(.+)\z/ ) {
                    # Received-From-MTA: DNS; x1x2x3x4.dhcp.example.ne.jp
                    next if $connheader->{'lhost'};
                    $connheader->{'lhost'} = lc $1;
                    $connvalues++;

                } elsif( $e =~ m/\A[Aa]rrival-[Dd]ate:[ ]*(.+)\z/ ) {
                    # Arrival-Date: Wed, 29 Apr 2009 16:03:18 +0900
                    next if $connheader->{'date'};
                    $connheader->{'date'} = $1;
                    $connvalues++;
                }
            }
        } # End of if: rfc822

    } continue {
        # Save the current line for the next loop
        $p = $e;
    }

    return undef unless $recipients;
    require Sisimai::String;

    for my $e ( @$dscontents ) {
        # Set default values if each value is empty.
        map { $e->{ $_ } ||= $connheader->{ $_ } || '' } keys %$connheader;
        $e->{'diagnosis'} = Sisimai::String->sweep($e->{'diagnosis'});

        HARD_E: for my $r ( keys %$ReFailure ) {
            # Verify each regular expression of session errors
            next unless $e->{'diagnosis'} =~ $ReFailure->{ $r };
            $e->{'reason'} = $r;
            last;
        }

        unless( $e->{'reason'} ) {
            for my $r ( keys %$ReDelayed ) {
                # Verify each regular expression of session errors
                next unless $e->{'diagnosis'} =~ $ReDelayed->{ $r };
                $e->{'reason'} = $r;
                last;
            }
        }
        $e->{'agent'}     = __PACKAGE__->smtpagent;
        $e->{'command'} ||= $commandtxt || '';
    }

    $rfc822part = Sisimai::RFC5322->weedout($rfc822list);
    return { 'ds' => $dscontents, 'rfc822' => $$rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::MTA::Courier - bounce mail parser class for C<Courier MTA>.

=head1 SYNOPSIS

    use Sisimai::MTA::Courier;

=head1 DESCRIPTION

Sisimai::MTA::Courier parses a bounce email which created by C<Courier MTA>.
Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::MTA::Courier->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MTA name.

    print Sisimai::MTA::Courier->smtpagent;

=head2 C<B<scan(I<header data>, I<reference to body string>)>>

C<scan()> method parses a bounced email and return results as a array reference.
See Sisimai::Message for more details.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2016 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut

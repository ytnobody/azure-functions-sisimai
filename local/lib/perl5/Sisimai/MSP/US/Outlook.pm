package Sisimai::MSP::US::Outlook;
use parent 'Sisimai::MSP';
use feature ':5.10';
use strict;
use warnings;

my $Re0 = {
    'from'     => qr/postmaster[@]/,
    'subject'  => qr/Delivery Status Notification/,
    'received' => qr/.+[.]hotmail[.]com\b/,
};
my $Re1 = {
    'begin'  => qr/\AThis is an automatically generated Delivery Status Notification/,
    'error'  => qr/\A[.]+ while talking to .+[:]\z/,
    'rfc822' => qr|\AContent-Type: message/rfc822\z|,
    'endof'  => qr/\A__END_OF_EMAIL_MESSAGE__\z/,
};
my $ReFailure = {
    'hostunknown' => qr/The mail could not be delivered to the recipient because the domain is not reachable/,
    'userunknown' => qr/Requested action not taken: mailbox unavailable/,
};
my $Indicators = __PACKAGE__->INDICATORS;

# X-Message-Delivery: Vj0xLjE7RD0wO0dEPTA7U0NMPTk7bD0xO3VzPTE=
# X-Message-Info: AuEzbeVr9u5fkDpn2vR5iCu5wb6HBeY4iruBjnutBzpStnUabbM...
sub headerlist  { return ['X-Message-Delivery', 'X-Message-Info'] }
sub pattern     { return $Re0 }
sub description { 'Microsoft Outlook.com: https://www.outlook.com/' }

sub scan {
    # Detect an error from Microsoft Outlook.com
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
    # @since v4.1.3
    my $class = shift;
    my $mhead = shift // return undef;
    my $mbody = shift // return undef;
    my $match = 0;

    $match++ if $mhead->{'subject'} =~ $Re0->{'subject'};
    $match++ if $mhead->{'x-message-delivery'};
    $match++ if $mhead->{'x-message-info'};
    $match++ if grep { $_ =~ $Re0->{'received'} } @{ $mhead->{'received'} };
    return undef if $match < 2;

    my $dscontents = [__PACKAGE__->DELIVERYSTATUS];
    my @hasdivided = split("\n", $$mbody);
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $rfc822list = [];    # (Array) Each line in message/rfc822 part string
    my $blanklines = 0;     # (Integer) The number of blank lines
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $connvalues = 0;     # (Integer) Flag, 1 if all the value of $connheader have been set
    my $connheader = {
        'date'  => '',      # The value of Arrival-Date header
        'lhost' => '',      # The value of Reporting-MTA header
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
                # This is an automatically generated Delivery Status Notification.
                #
                # Delivery to the following recipients failed.
                #
                #      kijitora@example.jp
                #
                # Final-Recipient: rfc822;kijitora@example.jp
                # Action: failed
                # Status: 5.2.2
                # Diagnostic-Code: smtp;550 5.2.2 <kijitora@example.jp>... Mailbox Full
                $v = $dscontents->[-1];

                if( $e =~ m/\A[Ff]inal-[Rr]ecipient:[ ]*(?:RFC|rfc)822;[ ]*([^ ]+)\z/ ) {
                    # Final-Recipient: rfc822;kijitora@example.jp
                    if( length $v->{'recipient'} ) {
                        # There are multiple recipient addresses in the message body.
                        push @$dscontents, __PACKAGE__->DELIVERYSTATUS;
                        $v = $dscontents->[-1];
                    }
                    $v->{'recipient'} = $1;
                    $recipients++;

                } elsif( $e =~ m/\A[Aa]ction:[ ]*(.+)\z/ ) {
                    # Action: failed
                    $v->{'action'} = lc $1;

                } elsif( $e =~ m/\A[Ss]tatus:[ ]*(\d[.]\d+[.]\d+)/ ) {
                    # Status:5.2.0
                    $v->{'status'} = $1;

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
                # Reporting-MTA: dns;BLU004-OMC3S13.hotmail.example.com
                # Received-From-MTA: dns;BLU436-SMTP66
                # Arrival-Date: Fri, 21 Nov 2014 14:17:34 -0800
                if( $e =~ m/\A[Rr]eporting-MTA:[ ]*(?:DNS|dns);[ ]*(.+)\z/ ) {
                    # Reporting-MTA: dns;BLU004-OMC3S13.hotmail.example.com
                    next if length $connheader->{'lhost'};
                    $connheader->{'lhost'} = lc $1;
                    $connvalues++;

                } elsif( $e =~ m/\A[Aa]rrival-[Dd]ate:[ ]*(.+)\z/ ) {
                    # Arrival-Date: Wed, 29 Apr 2009 16:03:18 +0900
                    next if length $connheader->{'date'};
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

        $e->{'agent'}     = __PACKAGE__->smtpagent;
        $e->{'diagnosis'} = Sisimai::String->sweep($e->{'diagnosis'});

        if( length $e->{'diagnosis'} == 0 ) {
            # No message in 'diagnosis'
            if( $e->{'action'} eq 'delayed' ) {
                # Set pseudo diagnostic code message for delaying
                $e->{'diagnosis'} = 'Delivery to the following recipients has been delayed.';

            } else {
                # Set pseudo diagnostic code message
                $e->{'diagnosis'}  = 'Unable to deliver message to the following recipients, ';
                $e->{'diagnosis'} .= 'due to being unable to connect successfully to the destination mail server.';
            }
        }

        SESSION: for my $r ( keys %$ReFailure ) {
            # Verify each regular expression of session errors
            next unless $e->{'diagnosis'} =~ $ReFailure->{ $r };
            $e->{'reason'} = $r;
            last;
        }
    }
    $rfc822part = Sisimai::RFC5322->weedout($rfc822list);
    return { 'ds' => $dscontents, 'rfc822' => $$rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::MSP::US::Outlook - bounce mail parser class for C<Outlook.com>.

=head1 SYNOPSIS

    use Sisimai::MSP::US::Outlook;

=head1 DESCRIPTION

Sisimai::MSP::US::Outlook parses a bounce email which created by C<Microsoft 
Outlook.com>. Methods in the module are called from only Sisimai::Message.

=head1 CLASS METHODS

=head2 C<B<description()>>

C<description()> returns description string of this module.

    print Sisimai::MSP::US::Outlook->description;

=head2 C<B<smtpagent()>>

C<smtpagent()> returns MSP name.

    print Sisimai::MSP::US::Outlook->smtpagent;

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


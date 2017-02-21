package Sisimai::Reason::Filtered;
use feature ':5.10';
use strict;
use warnings;

sub text  { 'filtered' }
sub description { 'Email rejected due to a header content after SMTP DATA command' } 
sub match {
    # Try to match that the given text and regular expressions
    # @param    [String] argv1  String to be matched with regular expressions
    # @return   [Integer]       0: Did not match
    #                           1: Matched
    # @since v4.0.0
    my $class = shift;
    my $argv1 = shift // return undef;
    my $regex = qr{(?>
         because[ ]the[ ]recipient[ ]is[ ]only[ ]accepting[ ]mail[ ]from[ ]
            specific[ ]email[ ]addresses    # AOL Phoenix
        |Bounced[ ]Address  # SendGrid|a message to an address has previously been Bounced.
        |due[ ]to[ ]extended[ ]inactivity[ ]new[ ]mail[ ]is[ ]not[ ]currently[ ]
            being[ ]accepted[ ]for[ ]this[ ]mailbox
        |has[ ]restricted[ ]SMS[ ]e-mail    # AT&T
        |http://postmaster[.]facebook[.]com/.+refused[ ]due[ ]to[ ]recipient[ ]preferences # Facebook
        |IS[ ]NOT[ ]ACCEPTING[ ]ANY[ ]MAIL
        |permanent[ ]failure[ ]for[ ]one[ ]or[ ]more[ ]recipients[ ][(].+:blocked[)]
        |RESOLVER[.]RST[.]NotAuthorized # Microsoft Exchange
        |This[ ]account[ ]is[ ]protected[ ]by
        |user[ ](?:
             not[ ]found  # Filter on MAIL.RU
            |reject
            )
        |we[ ]failed[ ]to[ ]deliver[ ]mail[ ]because[ ]the[ ]following[ ]address
            [ ]recipient[ ]id[ ]refuse[ ]to[ ]receive[ ]mail    # Willcom
        )
    }ix;

    return 1 if $argv1 =~ $regex;
    return 0;
}

sub true {
    # Rejected by domain or address filter ?
    # @param    [Sisimai::Data] argvs   Object to be detected the reason
    # @return   [Integer]               1: is filtered
    #                                   0: is not filtered
    # @since v4.0.0
    # @see http://www.ietf.org/rfc/rfc2822.txt
    my $class = shift;
    my $argvs = shift // return undef;

    return undef unless ref $argvs eq 'Sisimai::Data';
    return 1 if $argvs->reason eq __PACKAGE__->text;

    require Sisimai::SMTP::Status;
    require Sisimai::Reason::UserUnknown;
    my $commandtxt = $argvs->smtpcommand // '';
    my $statuscode = $argvs->deliverystatus // '';
    my $diagnostic = $argvs->diagnosticcode // '';
    my $tempreason = Sisimai::SMTP::Status->name($statuscode);
    my $reasontext = __PACKAGE__->text;
    my $v = 0;

    return 0 if $tempreason eq 'suspend';

    if( $tempreason eq $reasontext ) {
        # Delivery status code points "filtered".
        if( Sisimai::Reason::UserUnknown->match($diagnostic) ||
            __PACKAGE__->match($diagnostic) ) {

            $v = 1 
        }
    } else {
        # Check the value of Diagnostic-Code and the last SMTP command
        if( $commandtxt ne 'RCPT' && $commandtxt ne 'MAIL' ) {
            # Check the last SMTP command of the session. 
            if( __PACKAGE__->match($diagnostic) ) {
                # Matched with a pattern in this class
                $v = 1;

            } else {
                # Did not match with patterns in this class,
                # Check the value of "Diagnostic-Code" with other error patterns.
                $v = 1 if Sisimai::Reason::UserUnknown->match($diagnostic);
            }
        }
    }

    return $v;
}


1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Reason::Filtered - Bounce reason is C<filtered> or not.

=head1 SYNOPSIS

    use Sisimai::Reason::Filtered;
    print Sisimai::Reason::Filtered->match('550 5.1.2 User reject');   # 1

=head1 DESCRIPTION

Sisimai::Reason::Filtered checks the bounce reason is C<filtered> or not. This
class is called only Sisimai::Reason class.

This is the error that an email has been rejected by a header content after 
SMTP DATA command. 
In Japanese cellular phones, the error will incur that a sender's email address
or a domain is rejected by recipient's email configuration. Sisimai will set 
C<filtered> to the reason of email bounce if the value of Status: field in a 
bounce email is C<5.2.0> or C<5.2.1>. 

This error reason is almost the same as UserUnknown.

    ... while talking to mfsmax.ntt.example.ne.jp.:
    >>> DATA
    <<< 550 Unknown user kijitora@ntt.example.ne.jp
    554 5.0.0 Service unavailable

=head1 CLASS METHODS

=head2 C<B<text()>>

C<text()> returns string: C<filtered>.

    print Sisimai::Reason::Filtered->text;  # filtered

=head2 C<B<match(I<string>)>>

C<match()> returns 1 if the argument matched with patterns defined in this class.

    print Sisimai::Reason::Filtered->match('550 5.1.2 User reject');   # 1

=head2 C<B<true(I<Sisimai::Data>)>>

C<true()> returns 1 if the bounce reason is C<filtered>. The argument must be
Sisimai::Data object and this method is called only from Sisimai::Reason class.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2016 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut

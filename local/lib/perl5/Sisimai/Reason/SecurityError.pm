package Sisimai::Reason::SecurityError;
use feature ':5.10';
use strict;
use warnings;

sub text  { 'securityerror' }
sub description { 'Email rejected due to security violation was detected on a destination host' }
sub match {
    # Try to match that the given text and regular expressions
    # @param    [String] argv1  String to be matched with regular expressions
    # @return   [Integer]       0: Did not match
    #                           1: Matched
    # @since v4.0.0
    my $class = shift;
    my $argv1 = shift // return undef;
    my $regex = qr{(?>
         authentication[ ](?:
             failed;[ ]server[ ].+[ ]said:  # Postfix
            |turned[ ]on[ ]in[ ]your[ ]email[ ]client
            )
        |\d+[ ]denied[ ]\[[a-z]+\][ ].+[(]Mode:[ ].+[)]
        |because[ ](?>
             the[ ]recipient[ ]is[ ]not[ ]accepting[ ]mail[ ]with[ ](?:
                 attachments        # AOL Phoenix
                |embedded[ ]images  # AOL Phoenix
                )
            )
        |domain[ ].+[ ]is[ ]a[ ]dead[ ]domain
        |email[ ](?:
             not[ ]accepted[ ]for[ ]policy[ ]reasons
            # http://kb.mimecast.com/Mimecast_Knowledge_Base/Administration_Console/Monitoring/Mimecast_SMTP_Error_Codes#554
            |rejected[ ]due[ ]to[ ]security[ ]policies
            )
        |Executable[ ]files[ ]are[ ]not[ ]allowed[ ]in[ ]compressed[ ]files
        |insecure[ ]mail[ ]relay
        |sorry,[ ]you[ ]don'?t[ ]authenticate[ ]or[ ]the[ ]domain[ ]isn'?t[ ]in[ ]
                my[ ]list[ ]of[ ]allowed[ ]rcpthosts
        |the[ ]message[ ]was[ ]rejected[ ]because[ ]it[ ]contains[ ]prohibited[ ]
            virus[ ]or[ ]spam[ ]content
        |TLS[ ]required[ ]but[ ]not[ ]supported # SendGrid:the recipient mailserver does not support TLS or have a valid certificate
        |you[ ]are[ ]not[ ]authorized[ ]to[ ]send[ ]mail,[ ]authentication[ ]is[ ]required
        |You[ ]have[ ]exceeded[ ]the[ ]the[ ]allowable[ ]number[ ]of[ ]posts[ ]
            without[ ]solving[ ]a[ ]captcha
        |verification[ ]failure
        )
    }ix;

    return 1 if $argv1 =~ $regex;
    return 0;
}

sub true {
    # The bounce reason is security error or not
    # @param    [Sisimai::Data] argvs   Object to be detected the reason
    # @return   [Integer]               1: is security error
    #                                   0: is not security error
    # @see http://www.ietf.org/rfc/rfc2822.txt
    return undef;
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::Reason::SecurityError - Bounce reason is C<securityerror> or not.

=head1 SYNOPSIS

    use Sisimai::Reason::SecurityError;
    print Sisimai::Reason::SecurityError->match('5.7.1 Email not accept');   # 1

=head1 DESCRIPTION

Sisimai::Reason::SecurityError checks the bounce reason is C<securityerror> or 
not. This class is called only Sisimai::Reason class.

This is the error that a security violation was detected on a destination mail 
server. Depends on the security policy on the server, there is any virus in the
email, a sender's email address is camouflaged address. Sisimai will set
C<securityerror> to the reason of email bounce if the value of Status: field in
a bounce email is C<5.7.*>.

    Status: 5.7.0
    Remote-MTA: DNS; gmail-smtp-in.l.google.com
    Diagnostic-Code: SMTP; 552-5.7.0 Our system detected an illegal attachment on your message. Please

=head1 CLASS METHODS

=head2 C<B<text()>>

C<text()> returns string: C<securityerror>.

    print Sisimai::Reason::SecurityError->text;  # securityerror

=head2 C<B<match(I<string>)>>

C<match()> returns 1 if the argument matched with patterns defined in this class.

    print Sisimai::Reason::SecurityError->match('5.7.1 Email not accept');   # 1

=head2 C<B<true(I<Sisimai::Data>)>>

C<true()> returns 1 if the bounce reason is C<securityerror>. The argument must be
Sisimai::Data object and this method is called only from Sisimai::Reason class.

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2016 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut

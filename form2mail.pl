#!/usr/bin/perl
#***************************************************************************#
# Form2Mail v1.4 for Win32 and Unix                                         #
# created Oct 09, 1996, this version Aug 04, 1999                           #
# Copyright 1997-99 by Eric T. Wienke and Liquid Silver, all Rights reserved#
# eric@liquidsilver.com     http://www.liquidsilver.com/scripts             #
#***************************************************************************#
# This script may be copied and used under the Artistic License,            #
# which is included in this distribution. If your copy didn't come with a   #
# license, you may find a copy online at                                    #
# http://www.perl.com/CPAN/doc/manual/html/READMEs/Artistic                 #
#                                                                           #
# By using this script you agree to indemnify Liquid Silver from any        #
# liability that might arise from its use.                                  #
#***************************************************************************#
# Refer to the file "usage.htm" for instructions on how to write forms      #
#                                                                           #
# Note: The similarity to Matt Wright's formmail program is on purpose so   #
# that you can use existing forms if you migrate to the win32 platform.     #
# This script however is NOT a port, I ended up rewriting the whole thing.  #
# Anyway, credits go to Matt Wright for writing the fine Unix script        #
# FormMail, which inspired me to do it better. He wrote a lot of other      #
# scripts which can be found at http://www.worldwidemart.com/scripts        #
#***************************************************************************#
# History:                                                                  #
#   v1.4  08/04/99 - now using the Artistic License                         #
#                  - minor cleanups                                         #
#   v1.3  12/22/97 - decided to make use of Sockets.pm for much better      #
#                    compatibility. This also means you must at least have  #
#                    Perl version 5.002 or greater now.(Build 300 or greater#
#                    if you use the ActiveWare/ActiveState distribution)    #
#                  - improved errorhandling during SMTP communication.      #
#                    Debug mode results in a more usable errorlog.          #
#                  - Commandline mode for quick testing without writing a   #
#                    form first. Just execute the script and you'll see.    #
#   v1.2  07/07/97 - now works with most unix servers too                   #
#                  - added support for PerlIS.dll (used by MS IIS)          #
#                  - more detailed error reports                            #
#                  - debug logging option added, set doLog to 2             #
#                  - syntax fixes in SMTP communication                     #
#                  - better error trapping during smtp communication        #
#   v1.11 03/05/97 - added field "hide_blanks". Set the value to "1" if     #
#                    you want empty fields of your form to be suppressed    #
#                    in the email body.                                     #
#   v1.1  03/04/97 - now no longer needs CGI.pm                             #
#                  - now directly uses sockets to communicate with          #
#                    a SMTP server, no external mailprogram needed          #
#                  - now allows multiple recipients. Just add more          #
#                    addresses in the hidden Form tag 'recipients'          #
#                    seperated with commas                                  #
#                  - Redirections to a secure server now work correctly     #
#                  - added sort field for specifying the order in which     #
#                    the fields are printed in the email body.              #
#                  - logging restricted to errors                           #
#                  - some minor improvements and bug fixes                  #
#                  - finally uses strict :)                                 #
#   v1.0  10/09/96 - Initial release                                        #
#***************************************************************************#
require 5.002; # needed for Socket.pm
#use strict;   # only used during development
use Socket qw(:DEFAULT :crlf);
             
my $date = localtime;
my $version = '1.4';
my ($smtpserver,$port,@referer,$return_addr,$doLog,$maillogfile,@hidden,%query);

##############################################################################
# USER DEFINEABLE VARIABLES

# Set this to your SMTP server
$smtpserver = 'mail.webwarp.com';
# Mail port of the SMTP server. Usually 25
$port = 25;
# hosts allowed accessing this cgi
@referer = ('webwarp.com','mail.webwarp.com','localhost','127.0.0.1');

# this is the default Return address if no email was submitted by the form
$return_addr = 'http://www.webwarp.com/tt/contactproblem.com';

# logging. set to 0 for no logging, 1 for logging errors and 2 for debugging
# (debugging logs all SMTP server replies)
$doLog = 0;
# location of logfile. 
# Only used if $doLog is set to 1 or 2 or from the commandline
$maillogfile = 'smtp-error.log';

# END OF USER DEFINEABLE VARIABLES
##############################################################################

# These fields will not be send with the mail
@hidden = ('recipient','redirect','bgcolor','background','subject',
           'link_color','vlink_color','alink_color','text_color','title',
           'env_report','return_link_title','return_link_url','required',
           'no_table','font_face','font_size','sort','hide_blanks');

# Check if running from commandline
my $clmode = 0;
if (!$ENV{'REQUEST_METHOD'}) {
    $clmode = 1;
    &commandline_mode;
}

# Get the Form input
%query = &read_input;

# Check Referring URL
&check_referer;

# Check Required Fields
&check_required;

# Send E-Mail
&sendmail;

# Return HTML Page or Redirect User
&return_html;


sub commandline_mode {
    my $yesno;
    print "Commandline mode. Answers in brackets are default values.\n",
          "Do you wish to send a test email? ([y]/n) ";
    chomp ($yesno = <STDIN>);
    if ($yesno =~ /^n/i) {
        print "\n"; exit;
    }
    print "Enter recipient(s): [",$return_addr,"] ";
    chomp ($query{recipient} = <STDIN>);
    $query{recipient} ||= $return_addr;
    print "Ok, trying to connect...\n";
    &sendmail;
    print "\n"; exit;
}

sub check_referer {
    my ($allowed_referer,$referer_OK);
    if ($ENV{'HTTP_REFERER'}) {
        foreach $allowed_referer (@referer) {
            if ($ENV{'HTTP_REFERER'} =~ /$allowed_referer/i) {
                $referer_OK = 1;
                last;
            }
        }
    }
    else {
        $referer_OK = 1;
    }

    if (!$referer_OK) {
    &error('Bad Referer');
    }
}

sub check_required {
    my ($require,@required,@ERROR);
    @required = split(/,/,$query{'required'});
    foreach $require (@required) {

        if (!($query{$require}) || $query{$require} eq ' ') {
            push(@ERROR,$require);
        }
       }

    if (@ERROR) {
    &error('Blank Fields', @ERROR);
    }

}

sub return_html {
    my $title = $query{'title'} || "Thank you";
    my @TO = split(/,/,$query{'recipient'});

    if ($query{'redirect'} =~ /http(s)?\:\/\/.*\..*/) {
        print "HTTP/1.0 303 See Other\r\n" if $ENV{PERLXS} eq "PerlIS"; # for perlIS.dll
        print "Location: $query{'redirect'}\n\n";
    }

    else {
        &build_body("$title");
        print "<center>\n";
        my $font = &check_font;
        print "<H1>$title</H1>\n<P><HR size=7 width=\"75\%\">\n";

        # check whether using a table or not. default is yes.
        if (!$query{'no_table'}) {
            print "<TABLE width=\"75\%\">\n<TR><TD>\n";
            &check_font;
        }
        print "Below is what you submitted to $TO[0] on $date\n<p>\n";

        print "<UL>\n";
        my ($key,$value,@sorted);
        my $sort = $query{'sort'};
        if ($sort eq 'alphabetic') {
            foreach $key (sort keys %query) {
                print "<LI>$key: $query{$key}</LI>\n"
                  unless ((grep {$_ eq $key} @hidden)||(!$query{$key}));
            }
        }
        elsif ($sort =~ /^order:.+,.+/) {
            $sort =~ s/order://;
            @sorted = split(/,/, $sort);
            foreach $key (@sorted) {
                if ($query{$key}) {
                    print "<LI>$key: $query{$key}</LI>\n"
                      unless ((grep {$_ eq $key} @hidden)||(!$query{$key}));
                }
            }
        }
        else {
            while (($key,$value) = each %query) {
                print "<LI>$key: $value</LI>\n"
                  unless ((grep {$_ eq $key} @hidden)||(!$value));
            }
        }
        print "</UL>\n";

        # check if closing Table tags are needed
        if (!$query{'no_table'}) {
            print "</FONT>\n" if $font;
            print "</TD></TR>\n</TABLE>\n";
        }

        print "<P><HR width=\"75\%\" size=7>\n";

        # Check for a Return Link
        if ($query{'return_link_url'} =~ /http\:\/\/.*\..*/) {
            print "<UL>\n<LI><A href=\"$query{'return_link_url'}\">";
            print $query{'return_link_title'} || $query{'return_link_url'};
            print "</A></LI>\n</UL>\n";
        }
        print "</CENTER><P><HR></P>\n<P align=\"right\"><FONT size=-1>\n",
              "Created with Form2Mail v$version by <A href=\"",
              "http://www.liquidsilver.com/scripts/\">Liquid Silver</A></P>\n";

        print "</FONT>\n" if $font;
        print "</BODY>\n</HTML>\n";
    }

}

sub sendmail {
    my ($iaddr, $paddr, $proto, $a, $i);
    my $debug = ($doLog == 2 or $clmode);
    my $subject = $query{'subject'} || "WWW Form Submission";
    my $from = $query{'email'} || "$return_addr";
    my $retaddr = $from;
    if ($query{'realname'}) {
        $retaddr = '"'.$query{'realname'}.'"'." <$from>";
    }
    &error("No recipient!") unless $query{'recipient'};
    my @TO = split(/,/,$query{'recipient'});

    $port ||= 25;
    $port = getservbyname($port,'tcp') if $port =~ /\D/;
    error("Port not valid.") unless $port;    
    
    print "Resolving hostname for $smtpserver..." if $clmode;
    $iaddr = inet_aton($smtpserver);
    error("Can not resolve hostname $smtpserver") unless $iaddr;
    print "ok\n" if $clmode;
    $paddr = sockaddr_in($port, $iaddr);
    $proto = getprotobyname('tcp');
    my $ipstring = inet_ntoa((unpack_sockaddr_in($paddr))[1]);
    print "Connecting to $ipstring..." if $clmode;
    socket(S, PF_INET, SOCK_STREAM, $proto) or error("socket call failed: $!");
    connect(S, $paddr) or error("Unable to connect to $ipstring on port $port: $! (possibly no route to host or connection refused by host)");
    print "ok\n" if $clmode;
    select(S); $| = 1; select(STDOUT);
    
    # session is initiated
    print "SMTP session initiated. Debug mode is on.\nCheck $maillogfile for",
          " details of session.\n" if $clmode;
    if ($debug) {
      open LOG, ">>$maillogfile" or error("Could not open logfile $maillogfile: $!");
      print LOG '='x79,"\n$date SMTP session with $ipstring on port $port\n",'='x79,"\n";
    }
    $a=<S>; print LOG strip($a) if $debug;
    error("SMTP error: $a") if $a !~ /^2/;
    
    print S "HELO localhost$CRLF";
    print LOG "HELO localhost\n" if $debug;
    $a=<S>; print LOG strip($a) if $debug;
    error("SMTP error: $a") if $a !~ /^2/;
    
    print S "MAIL FROM:$from$CRLF";
    print LOG "MAIL FROM:$from\n" if $debug;
    $a=<S>; print LOG strip($a) if $debug;    
    error("SMTP error: $a") if $a !~ /^2/;
    
    foreach $i(@TO) {
        print S "RCPT TO:<$i>$CRLF";
        print LOG "RCPT TO:<$i>\n";
        $a=<S>; print LOG strip($a) if $debug;
        error("SMTP error: $a") if $a !~ /^2/;
    }
    
    # send message body
    print S "DATA \n";
    print LOG "DATA \n";
    $a=<S>; print LOG strip($a) if $debug;
    error("SMTP error: $a") if $a !~ /^3/;
    
    print LOG "Sending messagebody...\n" if $debug;
    print S "From: $retaddr$CRLF";
    print S "To: $TO[0]";
    for ($i = 1; $i < @TO; $i++) {
        print S ",$TO[$i]";
    }
    print S "$CRLF";
    print S "Subject: $subject$CRLF";
    print S "Reply-To: $from$CRLF";
    print S "X-Mailer: Form2Mail v$version by Liquid Silver$CRLF";
    print S "Below is the result of your email form.$CRLF";
    print S "Submitted by $from$CRLF";
    print S "$CRLF";

    # sort fields
    my ($key,$value,@sorted);
    my $sort = $query{'sort'} || '';
    if ($sort eq 'alphabetic') {
        foreach $key (sort keys %query) {
            next if grep {$_ eq $key} @hidden;
            next if (!$query{$key} && $query{'hide_blanks'});
            print S "$key: $query{$key}\n";
        }
    }
    elsif ($sort =~ /^order:.+,.+/) {
        $sort =~ s/order://;
        @sorted = split(/,/, $sort);
        foreach $key (@sorted) {
            if ($query{$key} || !$query{'hide_blanks'}) {
                print S "$key: $query{$key}\n"
                  unless (grep {$_ eq $key} @hidden);
            }
        }
    }
    else {
        while (($key,$value) = each %query) {
            print S "$key: $value\n"
              unless ((grep {$_ eq $key} @hidden)||(!$value && $query{'hide_blanks'}));
        }
    }
    print S "$CRLF$CRLF";

    # Send Environment variables
    my @env_report = split(/,/,$query{'env_report'} || '');
    my $env;
    foreach $env (@env_report) {
        print S "$env: $ENV{$env}$CRLF";
    }
    print S ".$CRLF";
    $a=<S>; print LOG strip($a) if $debug;
    print S "QUIT$CRLF";
    print LOG "QUIT\n\n\n" if $debug;
    close LOG if $debug;
    print "Mail transmitted.\n" if $clmode;
}

sub strip {
    $_ = $_[0];
    s/(\r|\n)//g;
    return "$_\n";
}

sub error {

    my ($error,@error_fields) = @_;
    my $missing_field;
    
    &build_body("Mail Error") unless $clmode;

    if ($error =~ /Bad Referer/) {
        print "<H1>Bad Referer - Access Denied</H1>\n",
              "Sorry, but you are requesting <A href=\"",
              "http://www.liquidsilver.com/scripts/\">Form2mail</A>\n",
              "from $ENV{'HTTP_REFERER'}, who is not allowed to access this CGI script.\n";
    }

    elsif ($error =~ /Blank Fields/) {
        print "<CENTER>\n<H1>Error: Blank Fields</H1>\n";
        print "<TABLE width=\"75\%\">\n<TR><TD>\n" unless $query{'no_table'};

        my $font = &check_font;
        print "Sorry, but the following fields were left blank in your submission form:\n<P>\n";

        # Print Out Missing Fields in a List.
        print "<DD><UL>\n";
        foreach $missing_field (@error_fields) {
            print "<LI>$missing_field</LI>\n";
        }
        print "</UL>\n<P><HR size=7>\nThese fields must be filled out before you can ",
              "successfully submit the form.\nPlease return to the <A href=\"",
              "$ENV{'HTTP_REFERER'}\">Submission Form</A> and try again.\n</P>\n";

        print "</FONT>" if $font;
        print "</TD></TR>\n</TABLE>\n" unless $query{'no_table'};
        print "</CENTER>\n";
    }
    else {
        my @recipients = split/,/,$query{'recipient'};
        print "<H2>Sorry, an error occured and your mail was not transmitted.</H2>\n",
              "Please send email directly to <A href=\"mailto:$recipients[0]\">",
              "$recipients[0]</A>.\nThank you.\n<P>Error message: $error</P>";
        if ($doLog) {
            if (open FILE,">>$maillogfile") {
                print FILE "$date $error\n";
                print FILE "***form2mail v$version, Perl v$], OS: $^O***\n" if $doLog == 2;
                close FILE;
            }
        }
    }
    
    print "</BODY></HTML>\n" unless $clmode;;
    
    exit;
}

sub build_body {
    my $title = $_[0] || "Thank you.";
    my ($bgcolor,$background,$link_color,$vlink_color,$alink_color,$text_color) =
    ( $query{'bgcolor'} || "#FFFFFF",
      $query{'background'},
      $query{'link_color'} || "#0000FF",
      $query{'vlink_color'} || "#660099",
      $query{'alink_color'} || "#FF0000",
      $query{'text_color'} || "#000000"
    );
    undef $background if $background !~ /^http(s)?\:\/\//i;
    
    print "HTTP/1.0 200 OK\r\n" if $ENV{PERLXS} eq "PerlIS"; # for perlIS.dll
    print "Content-type: text/html\n\n<HTML>\n<HEAD>\n  <TITLE>$title</TITLE>\n",
          "  <META name=\"generator\" content=\"Form2mail v$version\">\n",
          "  <META name=\"copyright\" content=\"copyright 1996,1997 by",
          "Liquid Silver, all rights reserved.\">\n</HEAD>\n<BODY ",
          "bgcolor=\"$bgcolor\" text=\"$text_color\" link=\"$link_color\"",
          "vlink=\"$vlink_color\" alink=\"$alink_color\"";
    print " background=\"$background\"" if $background;
    print ">\n";  
}

sub check_font {
    my $font = 0;
    if ($query{'font_face'} && ($query{'font_face'} ne ' ')) {
        print "<FONT face=\"$query{'font_face'}\"";
        if ($query{'font_size'} && ($query{'font_size'} ne ' ')) {
            print " size=\"$query{'font_size'}";
        }
        print "\">\n";
        $font = 1;
    }
    return $font;
}

sub read_input {
    my ($buffer, @pairs, $pair, $name, $value, %FORM);
    # Read in text
    $ENV{'REQUEST_METHOD'} =~ tr/a-z/A-Z/;
    if ($ENV{'REQUEST_METHOD'} eq "POST") {
        read(STDIN, $buffer, $ENV{'CONTENT_LENGTH'});
    } else {
        $buffer = $ENV{'QUERY_STRING'};
    }
    # Split information into name/value pairs
    @pairs = split(/&/, $buffer);
    foreach $pair (@pairs) {
        ($name, $value) = split(/=/, $pair);
        $value =~ tr/+/ /;
        $value =~ s/%(..)/pack("C", hex($1))/eg;
        # remove potentially dangerous commands
        $value =~ s/<!--(.|\n)*-->//g;
        $value =~ s/<([^>]|\n)*>//g;
        $FORM{$name} = $value;
    }
    %FORM;
}

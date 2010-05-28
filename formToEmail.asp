<%@ Page Language="C#" ContentType="text/html" ResponseEncoding="utf-8" %>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>Untitled Document</title>
</head>
<body>


<% 
Set mailer = Server.CreateObject("CDONTS.NewMail") 
recipient = Request.Form("recipient") 
sender = Request.Form("sender") 
subject = Request.Form("subject") 
message = Request.Form("messageline1") 
message = message & vbCRLF 
message = message & vbCRLF 
message = message & Request.Form("messageline2") 
' insert your mail server here 
mailserver = "your.mailserver.com" 
result = mailer.SendMail(mailserver, recipient, sender, subject, message) 
%> 
<% If "" = result Then %> 
Mail has been sent. 
<% Else %> 
Mail was not sent, error message is 
<H2> 
<%= result %> 
</H2> 
<% End If %>


</body>
</html>

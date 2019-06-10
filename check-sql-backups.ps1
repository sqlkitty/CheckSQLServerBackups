$QueryPath= "E:\check-backups\sql-script.sql"
$OutputFile = "E:\check-backups\failed-backups.txt"


if (Test-Path $OutputFile)
{
Remove-Item -Path $OutputFile -Force
}

$ExecuteQuery= Get-Content -path $QueryPath | out-string


FOREACH($server in GC "E:\check-backups\server-list.txt")
 {
	$server 

	invoke-sqlcmd -ServerInstance $server -query $ExecuteQuery -querytimeout 65534 | ft -autosize | out-string -width 4096 >> $OutputFile
 }


if (Test-Path $OutputFile) 
{ 
    #to remove blank lines 
    ( Get-Content $OutputFile ) | Where { $_ } | Set-Content $OutputFile

    #to find word in file to ensure that the file isn't empty 
    $wordToFind = 'database_name'
    
    #to put the content of the file in the body of the email 
    $body = Get-Content -Path $OutputFile -Raw

    #send email with failed backup info 
    if(Get-Item $OutputFile | Select-String $wordToFind)
    {
    $smtpServer = "smtp1.server.com"
    Send-MailMessage -To "email@email.com" -From "email@email.com" -Subject "Failed SQL Server Backups" <#-Attachments $OutputFile#> -SmtpServer $smtpServer -Body $body
    }
}



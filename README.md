# Check SQL Server Backups
http://sqlkitty.com/?p=942

WHEN WAS YOUR LAST BACKUP? AND EMAIL NOTIFICATION IF IT WAS “TOO LONG” AGO

We have a monitoring tool that tells us when a backup fails. This only works if the agent is running. If the agent isn’t running, then you don’t get an email that a job failed since the job didn’t run, and the monitoring tool doesn’t send an email for missed jobs. So, basically when the agent isn’t running, it’s as if the job ran successfully (or so you think it did). This became especially problematic on production db servers where you need regular backups.

I implemented a powershell check to run queries against the sql servers, which sends an email if any results are found. I have this running in a scheduled task daily. 

The parts and pieces of this powershell check include:
a powershell file to run the check loops through the sql server list and runs the query to see when the last backup was run
sends email if results are output to file
a file to hold the query
a file to hold the results
a file to hold a list of sql servers
Powershell file to run with scheduled task 
Set the query path and output file path  
$QueryPath= “E:\ExecBackupsCheckMultiServer\2012-and-higher-sql-servers\2012-and-higher-check-backups-script.sql”
$OutputFile = “E:\ExecBackupsCheckMultiServer\2012-and-higher-sql-servers\FailedBackups2012andHigherVersions.txt”

Test if the output file already exists, and if it does, delete it 
if (Test-Path $OutputFile)
{
Remove-Item -Path $OutputFile -Force
}

Execute query on each server in the servers.txt file 
$ExecuteQuery= Get-Content -path $QueryPath | out-string

FOREACH($server in GC “E:\ExecBackupsCheckMultiServer\2012-and-higher-sql-servers\2012-and-higher-servers.txt”)
{
$server

invoke-sqlcmd -ServerInstance $server -query $ExecuteQuery -querytimeout 65534 | ft -autosize | out-string -width 4096 >> $OutputFile
}

Send email based on output file contents 
if (Test-Path $OutputFile) 
{ 
#to remove blank lines 
( Get-Content $OutputFile ) | Where { $_ } | Set-Content $OutputFile

#to find word in file to ensure that the file isn’t empty 
$wordToFind = ‘database_name’

#to put the content of the file in the body of the email 
$body = Get-Content -Path $OutputFile -Raw

#send email with failed backup info 
if(Get-Item $OutputFile | Select-String $wordToFind)
{
$smtpServer = “smtp1.genscape.com”
Send-MailMessage -To “email@email.com” -From “email@email.com” -Subject “Failed SQL Server Backups for 2012 and higher versions” <#-Attachments $OutputFile#> -SmtpServer $smtpServer -Body $body
}
}

sql query that is run on each server 
–works on version 2012 and higher 
–declares ISAG variable
DECLARE @ISAG AS sql_variant

–sets it to the serverproperty – which 1 for enabled and 0 for disabled 
SELECT @ISAG = SERVERPROPERTY (‘IsHadrEnabled’)

–cte pivots the full, diffs, log backups from msdb 
;with BackupPivot as (
select [database_name]
, [D] as [LastFull]
, [I] as [LastDiff]
, [L] as [LastLog]
from
(
select [database_name], [type], backup_finish_date
from msdb.dbo.backupset 
) x
pivot
(
max(backup_finish_date)
for [type] in([D], [L], [I])
)p
)

–selects the dbs in full mode from AGs where the node is primary – this would be all user dbs in the AG 
select distinct @@SERVERNAME as ServerName, bp.[database_name], bp.LastFull, DATEDIFF(hh, bp.LastFull, GETDATE()) AS [Full Backup Age (Hours)], 
bp.LastDiff, DATEDIFF(hh, bp.LastDiff, GETDATE()) AS [Diff Backup Age (Hours)], 
bp.LastLog, DATEDIFF(hh, bp.LastLog, GETDATE()) AS [Log Backup Age (Hours)], 
bs.recovery_model
from BackupPivot bp
inner join msdb.dbo.backupset bs
on bp.database_name = bs.database_name
right join master.sys.databases d 
on d.name = bs.database_name
where ([LastFull] < DATEADD(hh, – 168, GETDATE()) 
or [LastDiff] < DATEADD(hh, – 48, GETDATE())
or [LastLog] < DATEADD(hh, – 4, GETDATE()))
and d.recovery_model_desc = ‘Full’
and @ISAG = 1
and exists (select database_name, role_desc, * from master.sys.dm_hadr_database_replica_cluster_states AS dbrs
inner join master.sys.dm_hadr_availability_replica_states rs
on rs.replica_id = dbrs.replica_id
where role_desc = ‘PRIMARY’)

union

–selects the dbs in full mode from non AGs 
select distinct @@SERVERNAME as ServerName, bp.[database_name], bp.LastFull, DATEDIFF(hh, bp.LastFull, GETDATE()) AS [Full Backup Age (Hours)], 
bp.LastDiff, DATEDIFF(hh, bp.LastDiff, GETDATE()) AS [Diff Backup Age (Hours)], 
bp.LastLog, DATEDIFF(hh, bp.LastLog, GETDATE()) AS [Log Backup Age (Hours)], 
bs.recovery_model 
from BackupPivot bp
inner join msdb.dbo.backupset bs
on bp.database_name = bs.database_name
right join master.sys.databases d 
on d.name = bs.database_name
where ([LastFull] < DATEADD(hh, – 168, GETDATE()) 
or [LastDiff] < DATEADD(hh, – 48, GETDATE())
or [LastLog] < DATEADD(hh, – 4, GETDATE()))
and d.recovery_model_desc = ‘Full’
and @ISAG = 0

union

–selects the dbs in simple mode from all db servers 
select distinct @@SERVERNAME as ServerName, bp.[database_name], bp.LastFull, DATEDIFF(hh, bp.LastFull, GETDATE()) AS [Full Backup Age (Hours)], 
bp.LastDiff, DATEDIFF(hh, bp.LastDiff, GETDATE()) AS [Diff Backup Age (Hours)], 
bp.LastLog, DATEDIFF(hh, bp.LastLog, GETDATE()) AS [Log Backup Age (Hours)], 
bs.recovery_model 
from BackupPivot bp
inner join msdb.dbo.backupset bs
on bp.database_name = bs.database_name
right join master.sys.databases d 
on d.name = bs.database_name
where [LastFull] < DATEADD(hh, – 168, GETDATE()) 
and d.recovery_model_desc = ‘Simple’
–and @ISAG = 0

union

–selects the dbs that have no backups ever 
SELECT 
@@SERVERNAME as ServerName, 
d.NAME AS database_name, 
NULL AS LastFull, 
9999 AS [Full Backup Age (Hours)],
NULL AS LastDiff, 
9999 AS [Diff Backup Age (Hours)],
NULL AS LastLog,
9999 AS [Log Backup Age (Hours)],
d.recovery_model_desc collate SQL_Latin1_General_CP1_CI_AS

–9999 AS [Backup Age (Hours)] 
FROM 
master.sys.databases d LEFT JOIN msdb.dbo.backupset b
ON d.name = b.database_name 
where b.database_name IS NULL AND d.name <> ‘tempdb’
–and @ISAG = 0
order by [database_name]

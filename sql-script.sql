--works on version 2012 and higher 
--declares ISAG variable
DECLARE @ISAG AS sql_variant

--sets it to the serverproperty - which 1 for enabled and 0 for disabled 
SELECT @ISAG = SERVERPROPERTY ('IsHadrEnabled') 

--cte pivots the full, diffs, log backups from msdb 
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

--selects the dbs in full mode from AGs where the node is primary - this would be all user dbs in the AG 
select distinct @@SERVERNAME as ServerName, bp.[database_name], bp.LastFull, DATEDIFF(hh, bp.LastFull, GETDATE()) AS [Full Backup Age (Hours)], 
bp.LastDiff, DATEDIFF(hh, bp.LastDiff, GETDATE()) AS [Diff Backup Age (Hours)], 
bp.LastLog, DATEDIFF(hh, bp.LastLog, GETDATE()) AS [Log Backup Age (Hours)], 
bs.recovery_model
from BackupPivot bp
inner join msdb.dbo.backupset bs
on bp.database_name = bs.database_name
right join master.sys.databases d 
on d.name = bs.database_name
where ([LastFull] < DATEADD(hh, - 168, GETDATE()) 
		or  [LastDiff] < DATEADD(hh, - 48, GETDATE())
		or [LastLog] < DATEADD(hh, - 4, GETDATE()))
		and d.recovery_model_desc = 'Full'
		and @ISAG = 1
		and exists (select database_name, role_desc, * from master.sys.dm_hadr_database_replica_cluster_states AS dbrs
inner join master.sys.dm_hadr_availability_replica_states rs
on rs.replica_id = dbrs.replica_id
where role_desc = 'PRIMARY')

union 

--selects the dbs in full mode from non AGs  
select distinct @@SERVERNAME as ServerName, bp.[database_name], bp.LastFull, DATEDIFF(hh, bp.LastFull, GETDATE()) AS [Full Backup Age (Hours)], 
bp.LastDiff, DATEDIFF(hh, bp.LastDiff, GETDATE()) AS [Diff Backup Age (Hours)], 
bp.LastLog, DATEDIFF(hh, bp.LastLog, GETDATE()) AS [Log Backup Age (Hours)], 
bs.recovery_model 
from BackupPivot bp
inner join msdb.dbo.backupset bs
on bp.database_name = bs.database_name
right join master.sys.databases d 
on d.name = bs.database_name
where ([LastFull] < DATEADD(hh, - 168, GETDATE()) 
		or  [LastDiff] < DATEADD(hh, - 48, GETDATE())
		or [LastLog] < DATEADD(hh, - 4, GETDATE()))
		and d.recovery_model_desc = 'Full'
		and @ISAG = 0

union

--selects the dbs in simple mode from all db servers 
select distinct @@SERVERNAME as ServerName, bp.[database_name], bp.LastFull, DATEDIFF(hh, bp.LastFull, GETDATE()) AS [Full Backup Age (Hours)], 
bp.LastDiff, DATEDIFF(hh, bp.LastDiff, GETDATE()) AS [Diff Backup Age (Hours)], 
bp.LastLog, DATEDIFF(hh, bp.LastLog, GETDATE()) AS [Log Backup Age (Hours)], 
bs.recovery_model  
from BackupPivot bp
inner join msdb.dbo.backupset bs
on bp.database_name = bs.database_name
right join master.sys.databases d 
on d.name = bs.database_name
where [LastFull] < DATEADD(hh, - 168, GETDATE()) 
		and d.recovery_model_desc = 'Simple'
		--and @ISAG = 0

union

--selects the dbs that have no backups ever 
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
	
	--9999 AS [Backup Age (Hours)]  
FROM 
	master.sys.databases d LEFT JOIN msdb.dbo.backupset b
	ON d.name  = b.database_name 
where b.database_name IS NULL AND d.name <> 'tempdb'
--and @ISAG = 0
order by [database_name]

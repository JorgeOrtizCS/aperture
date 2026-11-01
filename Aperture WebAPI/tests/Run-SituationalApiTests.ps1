param(
 [string]$MySqlBin = 'C:\Program Files\MySQL\MySQL Server 8.0\bin',
 [string]$IisExpress = 'C:\Program Files\IIS Express\iisexpress.exe',
 [string]$Python = 'python'
)
$ErrorActionPreference='Stop'
# All writes go to a disposable local database and site. Never uses Web.config's server.
$mysql=Join-Path $MySqlBin 'mysql.exe'
$mysqld=Join-Path $MySqlBin 'mysqld.exe'
$mysqladmin=Join-Path $MySqlBin 'mysqladmin.exe'
foreach($exe in @($mysql,$mysqld,$mysqladmin,$IisExpress)) {
 if(!(Test-Path -LiteralPath $exe)){throw "Required tool not found: $exe"}
}
function Free-Port {
 $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
 $listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop();return $port
}
$mysqlPort=Free-Port
$apiPort=Free-Port
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('aperture-situational-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$apiProcess=$null;$dbProcess=$null
$apiRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\Aperture WebAPI')).Path
try {
 $data=Join-Path $fixture 'mysql'
 New-Item -ItemType Directory -Path $data | Out-Null
 $initialize=Start-Process -FilePath $mysqld -ArgumentList @('--no-defaults','--initialize-insecure',"--datadir=$data") -Wait -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $fixture 'initialize.log')
 if($initialize.ExitCode -ne 0){throw 'Disposable MySQL initialization failed.'}
 $dbProcess=Start-Process -FilePath $mysqld -ArgumentList @('--no-defaults',"--datadir=$data","--port=$mysqlPort",'--bind-address=127.0.0.1','--mysqlx=0') -PassThru -WindowStyle Hidden
 $ready=$false
 for($attempt=0;$attempt -lt 30;$attempt++) {
  & $mysql --no-defaults --host=127.0.0.1 "--port=$mysqlPort" --user=root --execute='SELECT 1' 2>$null | Out-Null
  if($LASTEXITCODE -eq 0){$ready=$true;break};Start-Sleep -Milliseconds 500
 }
 if(!$ready){throw 'Disposable MySQL did not become ready.'}
 Get-Content (Join-Path $PSScriptRoot '..\..\db\schema.sql') -Raw | & $mysql --no-defaults --host=127.0.0.1 "--port=$mysqlPort" --user=root
 if($LASTEXITCODE -ne 0){throw 'Disposable schema creation failed.'}
 $site=Join-Path $fixture 'site'
 New-Item -ItemType Directory -Path $site | Out-Null
 Copy-Item -LiteralPath (Join-Path $apiRoot 'bin') -Destination $site -Recurse
 Copy-Item -LiteralPath (Join-Path $apiRoot 'Global.asax') -Destination $site
 [xml]$config=Get-Content (Join-Path $apiRoot 'Web.config')
 $config.configuration.connectionStrings.add.SetAttribute('connectionString',"Server=127.0.0.1;Port=$mysqlPort;Database=APERTURE_DB;User ID=root;Password=;SslMode=Disabled;AllowPublicKeyRetrieval=True;")
 $config.Save((Join-Path $site 'Web.config'))
 $apiProcess=Start-Process -FilePath $IisExpress -ArgumentList @("/path:$site","/port:$apiPort",'/systray:false') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $fixture 'iis.log') -RedirectStandardError (Join-Path $fixture 'iis-errors.log')
 & $Python (Join-Path $PSScriptRoot 'situational_api_smoke.py') --port $apiPort --mysql-port $mysqlPort --mysql $mysql
 if($LASTEXITCODE -ne 0){throw 'Situational-awareness HTTP integration tests failed.'}
} catch {
 foreach($log in @('initialize.log','iis-errors.log','iis.log')) {
  $logPath=Join-Path $fixture $log
  if(Test-Path -LiteralPath $logPath){Get-Content -LiteralPath $logPath -Tail 8}
 }
 throw
} finally {
 if($apiProcess -and !$apiProcess.HasExited){Stop-Process -Id $apiProcess.Id -Force;$apiProcess.WaitForExit(5000) | Out-Null}
 if($dbProcess -and !$dbProcess.HasExited){
  & $mysqladmin --no-defaults --host=127.0.0.1 "--port=$mysqlPort" --user=root shutdown 2>$null | Out-Null
  if(!$dbProcess.WaitForExit(5000)){Stop-Process -Id $dbProcess.Id -Force}
 }
 $resolved=[IO.Path]::GetFullPath($fixture)
 $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'aperture-situational-*') {
  # ASP.NET CodeDom may leave its private compiler server alive after IIS exits.
  Get-CimInstance Win32_Process -Filter "Name='VBCSCompiler.exe'" | Where-Object {
   $_.ExecutablePath -and $_.ExecutablePath.StartsWith($resolved+'\',[StringComparison]::OrdinalIgnoreCase)
  } | ForEach-Object {Stop-Process -Id $_.ProcessId -Force}
  Remove-Item -LiteralPath $resolved -Recurse -Force
 }
}

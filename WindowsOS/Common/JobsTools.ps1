# Jobs Windows 工具公共函数；仅供各入口加载，不自动执行业务。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:JobsLog = $null
function Read-JobsText([string]$Prompt, [string]$Default = '') {
    if ([Console]::IsInputRedirected) { throw '需要交互终端；输入重定向或 EOF 时停止。只读检查请传 -Check。' }
    $answer = Read-Host $Prompt
    if ($null -eq $answer) { throw '输入已结束。' }
    if ($answer -eq '' -and $Default -ne '') { return $Default }
    return $answer
}
function Confirm-JobsChange([string]$Message) {
    if ((Read-JobsText "$Message；精确输入 YES 执行，其它输入取消") -cne 'YES') { throw '用户取消，未执行该变更。' }
}
function Write-JobsLog([string]$Message) {
    Write-Host $Message
    if ($script:JobsLog) { Add-Content -LiteralPath $script:JobsLog -Value $Message -Encoding UTF8 }
}
function Invoke-JobsNative([string]$Executable, [string[]]$Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Executable @Arguments 2>&1 | ForEach-Object { Write-JobsLog ([string]$_) }; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "$Executable 执行失败，退出码 $code" }
}
function Require-JobsCommand([string]$Name) {
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$command) { throw "缺少 $Name。请安装后重开终端，或先运行对应安装入口。" }
    return $command.Source
}
function Get-JobsPath([string]$Prompt, [switch]$Directory, [switch]$AllowNew) {
    $raw = (Read-JobsText $Prompt).Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($raw)) { throw '路径不能为空。' }
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($raw))
    $ancestor = $full
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '目标或上层目录是链接，停止。' }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    if (!$AllowNew -and !(Test-Path -LiteralPath $full)) { throw "路径不存在：$full" }
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '拒绝符号链接或目录联接。' }
        if ($Directory -and !$item.PSIsContainer) { throw '需要目录。' }
        if (!$Directory -and $item.PSIsContainer) { throw '需要普通文件。' }
    }
    return $full
}
function Get-JobsFiles([string]$Root) {
    $skip = @('.git','node_modules','Pods','.dart_tool','build','DerivedData')
    $item = Get-Item -LiteralPath $Root -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
    if (!$item.PSIsContainer) { return $item }
    foreach ($child in Get-ChildItem -LiteralPath $Root -Force) {
        if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($child.PSIsContainer) { if ($skip -notcontains $child.Name) { Get-JobsFiles $child.FullName } }
        else { $child }
    }
}
function Backup-JobsFile([string]$Path) {
    $backup = $Path + '.jobs-backup-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,6)
    Copy-Item -LiteralPath $Path -Destination $backup -ErrorAction Stop
    Write-JobsLog "备份：$backup"
    return $backup
}
function Read-JobsUtf8([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes -contains 0) { throw "跳过二进制或 UTF-16 文件：$Path（仅支持严格 UTF-8）" }
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    $offset = 0; if ($hasBom) { $offset = 3 }
    $utf8 = New-Object Text.UTF8Encoding($false,$true)
    return @{ Text = $utf8.GetString($bytes,$offset,$bytes.Length-$offset); Bom = $hasBom }
}
function Write-JobsUtf8([string]$Path,[string]$Text,[bool]$Bom = $false) {
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($Bom)))
}
function Get-JobsState([string]$Name) {
    $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'JobsCommandOthers'
    $path = Join-Path $root $Name
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}
function Show-JobsSource([string]$Object,[string]$Source,[string]$Destination) {
    $safe = $Source
    $uri = $null
    if ([Uri]::TryCreate($Source,[UriKind]::Absolute,[ref]$uri) -and $uri.Host) {
        $builder = New-Object UriBuilder($uri); $builder.UserName='';$builder.Password='';$builder.Query='';$builder.Fragment='';$safe=$builder.Uri.AbsoluteUri
    }
    Write-JobsLog "来源｜$Object`n来源地址：$safe`n目标位置：$Destination"
}
function Install-JobsWinget([string]$Package) {
    $winget = Require-JobsCommand 'winget.exe'
    Show-JobsSource $Package 'https://github.com/microsoft/winget-pkgs' 'Windows 包管理器；最终安装位置由安装器决定'
    Confirm-JobsChange "安装 / 升级 $Package（来源 winget 社区软件目录，实际 URL 由 winget 解析；请先核对软件许可）"
    $mode = Read-JobsText '输入 upgrade 升级；回车安装' 'install'
    if ($mode -notin @('install','upgrade')) { throw '只接受 install 或 upgrade。' }
    Invoke-JobsNative $winget @($mode,'--id',$Package,'--exact','--source','winget')
}
function Require-JobsDocker {
    $docker = Require-JobsCommand 'docker.exe'
    Invoke-JobsNative $docker @('info','--format','{{.OSType}}')
    $type = & $docker info --format '{{.OSType}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or "$type".Trim() -ne 'linux') { throw '需要已运行的 Docker Desktop Linux containers（WSL 2）；先启动引擎。' }
    return $docker
}
function Get-JobsContainer([string]$Docker,[string]$Name,[string]$Owner) {
    $text = & $Docker container ls -a --filter "name=^/$Name`$" --format '{{json .}}'
    if ($LASTEXITCODE -ne 0) { throw '无法查询容器。' }
    if (!$text) { return $null }
    $details = & $Docker inspect $Name
    if ($LASTEXITCODE -ne 0) { throw '无法检查容器。' }
    $item = @($details | ConvertFrom-Json)[0]
    if ($item.Config.Labels.'jobs.owner' -ne $Owner) { throw "同名容器不属于本工具，保留原状：$Name" }
    return $item
}
function Wait-JobsHttp([string]$Url,[int]$Seconds = 45) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try { $r=Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2; if ($r.StatusCode -lt 400) { Write-JobsLog "服务就绪：$Url"; return } } catch { }
        Start-Sleep -Milliseconds 500
    }
    throw "服务未在 $Seconds 秒内就绪：$Url；保留进程与日志供排查。"
}
function Invoke-JobsTimestamp {
    $value = Read-JobsText '输入 Unix 秒 / 毫秒 / 微秒时间戳'
    if ($value -notmatch '^-?\d{1,16}$') { throw '需要 1 至 16 位整数。' }
    $digits=$value.TrimStart('-').Length; $seconds=[decimal]$value
    if ($digits -gt 13) { $seconds/=1000000 } elseif ($digits -gt 10) { $seconds/=1000 }
    $date = [DateTimeOffset]::FromUnixTimeMilliseconds([long]($seconds*1000))
    Write-JobsLog ("本地："+$date.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss.fff zzz'))
    Write-JobsLog ("UTC："+$date.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss.fff'))
}
function Invoke-JobsDecode {
    $value=Read-JobsText '输入 URL 编码文本'
    if ((Read-JobsText '把 + 解析为空格？输入 YES，其它保留') -ceq 'YES') { $value=$value.Replace('+',' ') }
    $decoded=[Uri]::UnescapeDataString($value); Write-Host $decoded
    if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) { Set-Clipboard -Value $decoded }
}
function Invoke-JobsAppend {
    $path=Get-JobsPath '输入目标文本文件（可不存在）' -AllowNew
    $line=Read-JobsText '输入待追加的一行（内容不记日志）'
    if ([string]::IsNullOrWhiteSpace($line)) { throw '内容不能为空。' }
    $existing='';$bom=$false;$originalHash=$null
    $existed=Test-Path -LiteralPath $path
    if ($existed) { $originalHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;$doc=Read-JobsUtf8 $path;$existing=$doc.Text;$bom=$doc.Bom }
    if (@($existing -split '\r?\n' | Where-Object { $_ -notmatch '^\s*#' }) -ccontains $line) { Write-JobsLog '已有相同非注释行，跳过。';return }
    Confirm-JobsChange "向 $path 追加一行"
    if ($existed) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $originalHash) { throw '文件已并发修改，保留现状并停止。' }
    } elseif (Test-Path -LiteralPath $path) { throw '目标已被其它进程创建，保留现状并停止。' }
    if (Test-Path -LiteralPath $path) { $null=Backup-JobsFile $path } else { New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($path)) -Force | Out-Null }
    $separator='';if ($existing -and !$existing.EndsWith("`n")) { $separator="`r`n" }
    Write-JobsUtf8 $path ($existing+$separator+$line+"`r`n") $bom
    Write-JobsLog "已写入：$path"
}
function Invoke-JobsReplace {
    $raw=(Read-JobsText '输入文件或目录路径').Trim().Trim('"');$root=[IO.Path]::GetFullPath($raw)
    $find=Read-JobsText '输入查找文本（字面量）';if ($find -eq '') { throw '查找文本不能为空。' }
    $replace=Read-JobsText '输入替换文本（可为空）'
    $matches=New-Object Collections.ArrayList
    foreach ($file in Get-JobsFiles $root) {
        try { $doc=Read-JobsUtf8 $file.FullName } catch { Write-JobsLog "跳过：$($file.FullName)";continue }
        if ($doc.Text.Contains($find)) { $null=$matches.Add(@{Path=$file.FullName;Doc=$doc;Hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash});Write-JobsLog "命中：$($file.FullName)" }
    }
    if ($matches.Count -eq 0) { Write-JobsLog '无匹配文件。';return }
    Confirm-JobsChange "修改 $($matches.Count) 个文件；每个文件保留独立备份"
    foreach ($item in $matches) {
        if ((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.Hash) { throw "文件已并发修改，停止：$($item.Path)" }
        $null=Backup-JobsFile $item.Path;Write-JobsUtf8 $item.Path ($item.Doc.Text.Replace($find,$replace)) $item.Doc.Bom
    }
    Write-JobsLog "已替换 $($matches.Count) 个文件。"
}
function Get-JobsDirectories([string]$Root) {
    Get-Item -LiteralPath $Root
    foreach($child in Get-ChildItem -LiteralPath $Root -Directory -Force){
        if($child.Name -in @('.git','node_modules','Pods','.dart_tool','build','DerivedData') -or ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
        Get-JobsDirectories $child.FullName
    }
}
function Invoke-JobsCount {
    $root=Get-JobsPath '输入统计目录' -Directory
    $files=@(Get-JobsFiles $root);Write-JobsLog "普通文件：$($files.Count)"
    $counts=@{};foreach($file in $files){if(!$counts.ContainsKey($file.DirectoryName)){$counts[$file.DirectoryName]=0};$counts[$file.DirectoryName]++}
    foreach($directory in Get-JobsDirectories $root){$count=0;if($counts.ContainsKey($directory.FullName)){$count=$counts[$directory.FullName]};Write-JobsLog ("目录："+$directory.FullName+" — "+$count+" 个直接文件")}
    $files | Group-Object Extension | Sort-Object Count -Descending | ForEach-Object { Write-JobsLog ("{0,-15} {1}" -f $_.Name,$_.Count) }
}
function Invoke-JobsHash {
    $path=Get-JobsPath '输入要校验的文件';Write-JobsLog ((Get-FileHash -LiteralPath $path -Algorithm MD5).Hash+'  '+$path)
}
function Invoke-JobsSplit {
    $source=Get-JobsPath '输入源文件';$output=Get-JobsPath '输入新的输出目录' -Directory -AllowNew
    if (Test-Path -LiteralPath $output) { throw '分卷输出目录必须不存在，避免混入旧卷。' }
    $mb=Read-JobsText '每卷 MiB（1 至 2048）' '100';$size=0
    if (![int]::TryParse($mb,[ref]$size) -or $size -lt 1 -or $size -gt 2048) { throw '无效分卷大小。' }
    $compress=(Read-JobsText '输入 gzip 压缩后分卷；回车直接分卷') -ceq 'gzip'
    Confirm-JobsChange "读取 $source 并创建 $output；保留源文件"
    New-Item -ItemType Directory -Path $output | Out-Null
    $payload=$source;$temporary=$null
    try {
        if ($compress) {
            $temporary=Join-Path $output 'payload.gz';$input=[IO.File]::OpenRead($source);$sink=[IO.File]::Create($temporary)
            $gzip=New-Object IO.Compression.GZipStream($sink,[IO.Compression.CompressionMode]::Compress)
            try {$input.CopyTo($gzip)}finally{$gzip.Dispose();$sink.Dispose();$input.Dispose()};$payload=$temporary
        }
        $stream=[IO.File]::OpenRead($payload);$parts=New-Object Collections.ArrayList;$buffer=New-Object byte[] (1024*1024);$index=1
        try {
            while ($stream.Position -lt $stream.Length -or $index -eq 1) {
                $name='part-{0:D6}' -f $index;$path=Join-Path $output $name;$sink=[IO.File]::Open($path,[IO.FileMode]::CreateNew)
                try {$remaining=[long]$size*1024*1024;while ($remaining -gt 0 -and ($read=$stream.Read($buffer,0,[int][Math]::Min($buffer.Length,$remaining))) -gt 0) {$sink.Write($buffer,0,$read);$remaining-=$read}} finally{$sink.Dispose()}
                $null=$parts.Add(@{Name=$name;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash});$index++
            }
        } finally {$stream.Dispose()}
        $manifest=@{Format='JobsSplit-1';OriginalName=[IO.Path]::GetFileName($source);OriginalSHA256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;Compression=$(if($compress){'gzip'}else{'none'});Parts=@($parts.ToArray())}
        Write-JobsUtf8 (Join-Path $output 'manifest.json') ($manifest|ConvertTo-Json -Depth 6)
        Write-JobsLog "已生成 $($parts.Count) 卷：$output；合并选择 manifest.json。"
    } finally {if($temporary -and (Test-Path -LiteralPath $temporary)){Remove-Item -LiteralPath $temporary}}
}
function Invoke-JobsMerge {
    $manifestPath=Get-JobsPath '选择 JobsSplit manifest.json';$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
    if ($manifest.Format -ne 'JobsSplit-1' -or $manifest.Compression -notin @('none','gzip')) { throw '不支持的分卷清单；MacOS 旧卷请先在 MacOS 合并，或使用 7-Zip 对应格式。' }
    $output=Get-JobsPath '输入新的重建文件路径' -AllowNew
    if(Test-Path -LiteralPath $output){throw '目标已存在，拒绝覆盖。'}
    $root=Split-Path -Parent $manifestPath;$parts=@($manifest.Parts)
    if($parts.Count -lt 1){throw '卷集为空。'}
    foreach($part in $parts){if($part.Name -notmatch '^part-\d{6}$'){throw '卷名越界。'};$path=Join-Path $root $part.Name;if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $part.SHA256){throw "卷校验失败：$($part.Name)"}}
    Confirm-JobsChange "按清单重建 $output，源卷保留"
    $stage=$output+'.jobs-partial-'+[Guid]::NewGuid().ToString('N');$joined=$stage+'.joined'
    try{
        $sink=[IO.File]::Open($joined,[IO.FileMode]::CreateNew)
        try{foreach($part in $parts){$input=[IO.File]::OpenRead((Join-Path $root $part.Name));try{$input.CopyTo($sink)}finally{$input.Dispose()}}}finally{$sink.Dispose()}
        if($manifest.Compression -eq 'gzip'){$input=[IO.File]::OpenRead($joined);$gzip=New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress);$sink=[IO.File]::Open($stage,[IO.FileMode]::CreateNew);try{$gzip.CopyTo($sink)}finally{$sink.Dispose();$gzip.Dispose();$input.Dispose()}}
        else{Move-Item -LiteralPath $joined -Destination $stage}
        if((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -cne $manifest.OriginalSHA256){throw '重建校验失败。'}
        Move-Item -LiteralPath $stage -Destination $output;Write-JobsLog "已核对 SHA-256：$output"
    }finally{foreach($p in @($stage,$joined)){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p}}}
}
function Invoke-JobsMockData {
    $git=Require-JobsCommand 'git.exe';$parent=Get-JobsPath '选择保存 Mock 数据的父目录' -Directory;$destination=Join-Path $parent 'JobsMockData';$url='https://github.com/JobsKits/JobsMockData.git'
    Show-JobsSource 'JobsMockData' $url $destination
    if(Test-Path -LiteralPath $destination){
        $remote=& $git -C $destination remote get-url origin;if($LASTEXITCODE -ne 0 -or $remote -notmatch '^https://github\.com/JobsKits/JobsMockData(?:\.git)?$'){throw '已有目录 origin 不匹配，拒绝覆盖。'}
        if(& $git -C $destination status --porcelain){throw '已有仓库存在本地改动，请先处理。'}
        Confirm-JobsChange '更新现有 Mock 数据（只允许快进）';Invoke-JobsNative $git @('-C',$destination,'pull','--ff-only')
    }else{Confirm-JobsChange '克隆 Mock 数据';Invoke-JobsNative $git @('clone','--',$url,$destination)}
}
function Invoke-JobsManagedProcess([string]$Name,[string]$ScriptPath,[hashtable]$Parameters,[string]$Action = '') {
    $state=Get-JobsState $Name;$record=Join-Path $state 'process.json';$action=$Action;if(!$action){$action=Read-JobsText '输入 start / status / stop' 'start'}
    $process=$null;$saved=$null
    if(Test-Path -LiteralPath $record){$saved=Get-Content -LiteralPath $record -Raw|ConvertFrom-Json;$process=Get-Process -Id $saved.Pid -ErrorAction SilentlyContinue;if($process -and $process.StartTime.ToUniversalTime().Ticks -ne [long]$saved.StartTicks){$process=$null}}
    if($action -eq 'status'){Write-JobsLog $(if($process){"运行中，PID $($process.Id)"}else{'未运行。'});return}
    if($action -eq 'stop'){
        if(!$process){Write-JobsLog '未运行。';return};$details=Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)"
        if(!$details.CommandLine.Contains($saved.Encoded)){throw '进程身份不匹配，拒绝停止。'}
        Confirm-JobsChange "停止本入口进程 $($process.Id)";Stop-Process -Id $process.Id;Remove-Item -LiteralPath $record;return
    }
    if($action -ne 'start'){throw '无效动作。'}
    if($process){Write-JobsLog "已运行，PID $($process.Id)";return}
    $command='& '+"'"+$ScriptPath.Replace("'","''")+"'"
    foreach($key in $Parameters.Keys){$command+=' -'+$key+" '"+([string]$Parameters[$key]).Replace("'","''")+"'"}
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command));$powershell=Join-Path $PSHOME 'powershell.exe';if(!(Test-Path -LiteralPath $powershell)){$powershell=Require-JobsCommand 'powershell.exe'}
    Confirm-JobsChange "启动 $Name 本地后台服务；日志 $state"
    $process=Start-Process -FilePath $powershell -ArgumentList @('-NoProfile','-EncodedCommand',$encoded) -RedirectStandardOutput (Join-Path $state 'stdout.log') -RedirectStandardError (Join-Path $state 'stderr.log') -PassThru
    Start-Sleep -Milliseconds 300;$process.Refresh();if($process.HasExited){throw "后台服务启动失败，查看 $state"}
    @{Pid=$process.Id;StartTicks=$process.StartTime.ToUniversalTime().Ticks;Encoded=$encoded}|ConvertTo-Json|Set-Content -LiteralPath $record -Encoding UTF8
    Write-JobsLog "已启动 PID $($process.Id)；状态记录 $record"
}
function Invoke-JobsMock {
    $action=Read-JobsText 'Mock start / status / stop' 'start'
    if($action -in @('status','stop')){Invoke-JobsManagedProcess 'Mock' '' @{} $action;return}
    if($action -ne 'start'){throw '无效动作。'}
    $root=Get-JobsPath '选择 JSON 数据目录' -Directory;$portText=Read-JobsText '监听端口（仅 127.0.0.1）' '8080';$port=0
    if(![int]::TryParse($portText,[ref]$port)-or $port -lt 1024 -or $port -gt 65535){throw '端口应为 1024 至 65535。'}
    Invoke-JobsManagedProcess 'Mock' (Join-Path (Split-Path -Parent $PSScriptRoot) '【WindowsOS】Mock服务/MockServer.ps1') @{Root=$root;Port=$port} $action
    Write-JobsLog "访问：http://127.0.0.1:$port/；GET /文件名.json 返回对应数据。"
}
function Invoke-JobsStirling {
    $docker=Require-JobsDocker;$name='jobs-stirling-pdf';$owner='JobsCommandOthers.StirlingPDF';$item=Get-JobsContainer $docker $name $owner
    $action=Read-JobsText '输入 start / status / stop / remove' 'start'
    if($action -eq 'status'){Invoke-JobsNative $docker @('ps','-a','--filter',"name=^/$name`$");return}
    if($action -in @('stop','remove')){if(!$item){Write-JobsLog '尚未创建容器。';return};Confirm-JobsChange "$action $name，保留全部数据卷";Invoke-JobsNative $docker @('stop',$name);if($action -eq 'remove'){Invoke-JobsNative $docker @('rm',$name)};return}
    if($action -ne 'start'){throw '无效动作。'}
    Confirm-JobsChange '启动 Stirling PDF（仅回环端口 8088，持久数据卷保留；首次联网下载镜像）'
    if($item){Invoke-JobsNative $docker @('start',$name)}else{
        $image='docker.stirlingpdf.com/stirlingtools/stirling-pdf:latest';Show-JobsSource 'Stirling PDF' "https://$image" 'Docker Desktop 本地镜像及 jobs-stirling-* 数据卷'
        $args=@('run','-d','--name',$name,'--label',"jobs.owner=$owner",'-p','127.0.0.1:8088:8080','--memory','4g')
        foreach($volume in @('configs','logs','customFiles','pipeline','storage')){$args+=@('--mount',"type=volume,source=jobs-stirling-$volume,target=/$volume")}
        $args+=$image;Invoke-JobsNative $docker $args
    }
    Wait-JobsHttp 'http://127.0.0.1:8088/' 90;Write-JobsLog '首次登录按官方文档修改默认密码：https://docs.stirlingpdf.com/Server/Install/Docker/'
    Start-Process 'http://127.0.0.1:8088/'
}
function Invoke-JobsCaddy {
    $caddy=Require-JobsCommand 'caddy.exe';$state=Get-JobsState 'Caddy';$file=Join-Path $state 'Caddyfile';$action=Read-JobsText '输入 start / status / stop / restore-hosts' 'start'
    $hostsPath=Join-Path $env:SystemRoot 'System32\drivers\etc\hosts';$backupRecord=Join-Path $state 'hosts-backup.json'
    if($action -eq 'restore-hosts'){
        if(!(Test-Path -LiteralPath $backupRecord)){throw '没有本入口 hosts 备份。'};$r=Get-Content -LiteralPath $backupRecord -Raw|ConvertFrom-Json
        if((Get-FileHash -LiteralPath $hostsPath).Hash -ne $r.AfterHash){throw 'hosts 已有后续修改，拒绝覆盖；请按备份人工合并。'}
        Confirm-JobsChange "恢复 hosts：$($r.Backup)";Copy-Item -LiteralPath $r.Backup -Destination $hostsPath;return
    }
    if($action -eq 'status'){try{$r=Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:20219/config/' -TimeoutSec 3;Write-JobsLog "Caddy 管理端返回 $($r.StatusCode)"}catch{throw '本入口 Caddy 管理端未就绪。'};return}
    if($action -eq 'stop'){Confirm-JobsChange '停止本入口 Caddy 管理地址 127.0.0.1:20219';Invoke-JobsNative $caddy @('stop','--address','127.0.0.1:20219');return}
    if($action -ne 'start'){throw '无效动作。'}
    $upstream=Read-JobsText '输入本地 HTTP 服务端口' '5173';$port=0
    if(![int]::TryParse($upstream,[ref]$port)-or $port -lt 1 -or $port -gt 65535){throw '无效端口。'}
    $domain=(Read-JobsText '输入本地域名（仅主机名）' 'jobs.localhost').ToLowerInvariant()
    if($domain -notmatch '^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$'){throw '无效域名。'}
    Confirm-JobsChange "创建 Caddy 配置，HTTP 127.0.0.1:8089 / 域名 $domain 反代至 127.0.0.1:$port"
    Write-JobsUtf8 $file ("{`n    admin 127.0.0.1:20219`n    auto_https off`n}`nhttp://${domain}:8089 {`n    bind 127.0.0.1`n    reverse_proxy 127.0.0.1:$port`n}`n")
    Invoke-JobsNative $caddy @('validate','--config',$file,'--adapter','caddyfile')
    if((Read-JobsText '写入 Windows hosts？需要管理员终端，YES 写入；其它跳过') -ceq 'YES'){
        $backup=Backup-JobsFile $hostsPath;$before=[IO.File]::ReadAllText($hostsPath);$line="127.0.0.1 $domain # JobsCommandOthers.Caddy"
        if($before -notmatch "(?m)^127\.0\.0\.1\s+$([regex]::Escape($domain))\s"){
            [IO.File]::AppendAllText($hostsPath,"`r`n$line`r`n",(New-Object Text.UTF8Encoding($false)))
            @{Backup=$backup;AfterHash=(Get-FileHash -LiteralPath $hostsPath).Hash}|ConvertTo-Json|Set-Content -LiteralPath $backupRecord -Encoding UTF8
        }
    }
    Invoke-JobsNative $caddy @('start','--config',$file,'--adapter','caddyfile')
    Write-JobsLog "访问 http://${domain}:8089/；使用独立管理端口；未自动安装证书或修改系统代理。"
}
function Invoke-JobsScheduler {
    $prefix='JobsScheduler-';$action=Read-JobsText '任务管理 list / add / run / disable / enable / remove' 'list'
    if($action -eq 'list'){Get-ScheduledTask -TaskName "$prefix*" -ErrorAction SilentlyContinue|Format-Table TaskName,State;return}
    $name=Read-JobsText '任务名（字母数字、下划线或短横线）';if($name -notmatch '^[A-Za-z0-9_-]{1,60}$'){throw '无效任务名。'};$full=$prefix+$name
    if($action -eq 'add'){
        if(Get-ScheduledTask -TaskName $full -ErrorAction SilentlyContinue){throw '任务已存在，拒绝覆盖。'}
        $script=Get-JobsPath '选择要运行的 .ps1 脚本';if([IO.Path]::GetExtension($script) -ne '.ps1'){throw '仅接受 .ps1。'}
        $time=Read-JobsText '每天运行时间 HH:mm' '09:00';$when=[DateTime]::MinValue
        if(![DateTime]::TryParseExact($time,'HH:mm',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$when)){throw '无效时间。'}
        Confirm-JobsChange "注册当前用户每天 $time 运行 $script（仅用户登录时）"
        $execute=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$args='-NoProfile -File "'+$script+'"'
        $taskAction=New-ScheduledTaskAction -Execute $execute -Argument $args -WorkingDirectory ([IO.Path]::GetDirectoryName($script))
        $trigger=New-ScheduledTaskTrigger -Daily -At $when
        $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $full -Action $taskAction -Trigger $trigger -Principal $principal -Description 'JobsScheduler 当前用户任务'|Out-Null
    }else{
        $task=Get-ScheduledTask -TaskName $full -ErrorAction Stop;Confirm-JobsChange "$action 任务 $full"
        switch($action){'run'{Start-ScheduledTask -InputObject $task};'disable'{Disable-ScheduledTask -InputObject $task|Out-Null};'enable'{Enable-ScheduledTask -InputObject $task|Out-Null};'remove'{Unregister-ScheduledTask -InputObject $task -Confirm:$false};default{throw '无效动作。'}}
    }
    Write-JobsLog '已执行；任务历史和退出码可在 Windows 任务计划程序查看。'
}
function Invoke-JobsScreenshot {
    $html=Get-JobsPath '选择本地 HTML 文件';if([IO.Path]::GetExtension($html) -notin @('.html','.htm')){throw '需要 HTML。'}
    $output=Get-JobsPath '输入新的 PNG 输出路径' -AllowNew;if(Test-Path -LiteralPath $output){throw '输出已存在。'}
    $node=Require-JobsCommand 'node.exe';$npm=Require-JobsCommand 'npm.cmd';$state=Get-JobsState 'Screenshot'
    if(!(Test-Path -LiteralPath (Join-Path $state 'node_modules\puppeteer'))){Show-JobsSource 'Puppeteer 与 Chrome for Testing' 'https://www.npmjs.com/package/puppeteer' $state;Confirm-JobsChange '安装本工具私有 Puppeteer 并下载 Chromium';Invoke-JobsNative $npm @('install','--prefix',$state,'puppeteer')}
    $selector=Read-JobsText 'CSS 选择器（回车整页）';$module=Join-Path $state 'node_modules\puppeteer';$scriptFile=Join-Path $state 'capture.cjs'
    $js='const p=require('+($module|ConvertTo-Json -Compress)+'); const {pathToFileURL}=require("url"); (async()=>{const b=await p.launch();try{const page=await b.newPage();await page.setViewport({width:1440,height:900});await page.goto(pathToFileURL(process.argv[2]).href,{waitUntil:"networkidle2",timeout:30000});const s=process.argv[4];if(s){const e=await page.$(s);if(!e)throw Error("CSS selector not found");await e.screenshot({path:process.argv[3]});}else await page.screenshot({path:process.argv[3],fullPage:true});}finally{await b.close();}})().catch(e=>{console.error(e);process.exit(1)});'
    Confirm-JobsChange "打开本地 HTML 并截图到 $output（页面脚本可能访问网络）";Write-JobsUtf8 $scriptFile $js
    Invoke-JobsNative $node @($scriptFile,$html,$output,$selector);Write-JobsLog "截图：$output"
}
function Invoke-JobsKeyboardLauncher {
    Write-JobsLog '打开当前进程中的可见记录面板；只有本人点击开始并再次确认时才监听，只记按键名与时间。'
    if([Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA){throw '需要STA终端；使用本目录对应CMD或powershell.exe -STA -File入口。'}
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if(!(('Jobs.WindowsTools.KeyboardRecorder') -as [type])){
        Add-Type -Path (Join-Path (Split-Path -Parent $PSScriptRoot) '【WindowsOS】JobsKeyboardRecorder/KeyboardRecorder.cs') -ReferencedAssemblies @('System.Windows.Forms','System.Drawing')
    }
    [Jobs.WindowsTools.KeyboardRecorder]::Run()
    Write-JobsLog '可见记录窗口已关闭，会话监听已结束；没有后台记录进程。'
}
function Invoke-JobsTool([string]$Tool,[switch]$Check) {
    $script:JobsLog=$null
    $summary=@{'Caddy'='本地域名反代；写入独立配置，可选备份修改 hosts，启动/停止专属 Caddy。';'Scheduler'='管理当前用户 JobsScheduler- 任务；新增、启停和删除均明确确认。';'Mock'='以所选 JSON 目录启动/停止回环 Mock 服务，状态日志保存在当前用户目录。';'StirlingPDF'='准备并管理官方 PDF 服务容器；监听回环8088，保留专属持久数据卷。';'MockData'='下载/快进更新 JobsMockData 到选定父目录；保留本地改动。';'AppendUnique'='备份后向 UTF-8 文件追加唯一整行，不记录正文。';'PackageManager'='通过 winget 安装/升级你输入的明确包ID，先显示软件源。';'ReplaceText'='在所选文件树中预览并备份替换字面文本，跳过依赖与生成目录。';'DecodeURL'='解码 URL 编码字符串并复制到剪贴板，不记录正文。';'SplitFile'='保留源文件，生成可选gzip分卷与 SHA-256 清单。';'MergeFile'='校验 JobsSplit-1 分卷并重建新目标，拒绝覆盖已有文件。';'MD5'='读取指定普通文件并显示 MD5，不修改原文件。';'Timestamp'='转换 Unix 秒/毫秒/微秒时间戳，显示本地时区与UTC。';'Screenshot'='打开所选HTML并输出整页/元素PNG；可选私有安装Puppeteer，页面脚本可能联网。';'OpenTerminal'='在选定真实目录打开 cmd.exe，不拼接可执行Shell文本。';'FileCount'='读取所选目录普通文件并按扩展名统计，跳过依赖与生成目录。';'KeyboardRecorder'='显示同进程可见键盘面板；点击开始并确认后只在内存记录按键名/时间，关闭停止，不联网。'}
    Write-Host ("Jobs Windows｜$Tool`n用途与影响："+$summary[$Tool]+"`n确认后显示实际日志位置；Ctrl+C 取消，危险变更精确 YES。")
    if($Check){
        $dependencies=@{Caddy=@('caddy.exe');Mock=@();StirlingPDF=@('docker.exe');MockData=@('git.exe');Screenshot=@('node.exe','npm.cmd');PackageManager=@('winget.exe');Scheduler=@('Get-ScheduledTask');KeyboardRecorder=@()}
        Write-Host '只读检查：入口与模块加载成功；只查询命令是否存在，不启动或写业务文件。'
        if($dependencies.ContainsKey($Tool)){foreach($name in $dependencies[$Tool]){$found=Get-Command $name -ErrorAction SilentlyContinue;Write-Host ($name+': '+$(if($found){'已发现'}else{'未发现'}))}}
        return
    }
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw '本入口仅支持 Windows；当前平台只能使用 -Check。'}
    if((Read-JobsText '按回车继续；输入任意字符取消') -ne ''){return}
    $script:JobsLog=Join-Path ([IO.Path]::GetTempPath()) ("Jobs-"+$Tool+'-'+[Guid]::NewGuid().ToString('N')+'.log')
    Write-JobsLog "日志：$script:JobsLog"
    switch($Tool){
        'Timestamp'{Invoke-JobsTimestamp};'DecodeURL'{Invoke-JobsDecode};'AppendUnique'{Invoke-JobsAppend};'ReplaceText'{Invoke-JobsReplace};'FileCount'{Invoke-JobsCount};'MD5'{Invoke-JobsHash};'SplitFile'{Invoke-JobsSplit};'MergeFile'{Invoke-JobsMerge};'MockData'{Invoke-JobsMockData};'Mock'{Invoke-JobsMock};'StirlingPDF'{Invoke-JobsStirling};'Caddy'{Invoke-JobsCaddy};'Scheduler'{Invoke-JobsScheduler};'Screenshot'{Invoke-JobsScreenshot};'KeyboardRecorder'{Invoke-JobsKeyboardLauncher};'PackageManager'{ $package=Read-JobsText '输入 winget 精确包 ID（如 Git.Git / CaddyServer.Caddy）';if($package -notmatch '^[A-Za-z0-9._-]+$'){throw '无效包 ID。'};Install-JobsWinget $package };'OpenTerminal'{ $directory=Get-JobsPath '选择终端工作目录' -Directory;Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -WorkingDirectory $directory };default{throw "未知工具：$Tool"}
    }
}

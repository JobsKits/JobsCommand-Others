# FileVolumes.ps1 | JobsFileVolumes
# Created by Jobs on 2026年10月28日，星期三.
# 文件分卷内核；固定内存流式读写，无覆盖发布，始终保留原件。
# URL仅在终端展示层着色；日志和机器响应保留纯文本。
# 仅用于终端URL展示，不改变调用者数据。
function Test-JobsEnterChoiceColor {
    param([Collections.IDictionary]$Capabilities = $null)
    if ($null -eq $Capabilities) {
        try {
            $environment = [Environment]::GetEnvironmentVariables('Process')
            $Capabilities = @{ HostName = $Host.Name; InputRedirected = [Console]::IsInputRedirected; OutputRedirected = [Console]::IsOutputRedirected;
                               ErrorRedirected = [Console]::IsErrorRedirected; NoColorPresent = $environment.Contains('NO_COLOR');
                               PlainOutput = $env:PLAIN_OUTPUT; Term = $env:TERM; Windows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT); VirtualTerminal = $false; SourceTree = ($env:IS_SOURCETREE_RUNTIME -eq '1') }
            if ($null -ne $Host.UI.PSObject.Properties['SupportsVirtualTerminal']) { $Capabilities.VirtualTerminal = $Host.UI.SupportsVirtualTerminal }
            foreach ($key in $environment.Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { $Capabilities.SourceTree = $true; break } }
        } catch { return $false }
    }
    return ($Capabilities.HostName -eq 'ConsoleHost' -and -not $Capabilities.InputRedirected -and -not $Capabilities.OutputRedirected -and
            -not $Capabilities.ErrorRedirected -and -not $Capabilities.NoColorPresent -and $Capabilities.PlainOutput -ne '1' -and
            $Capabilities.Term -ine 'dumb' -and (-not [string]::IsNullOrEmpty($Capabilities.Term) -or ($Capabilities.Contains('Windows') -and $Capabilities.Windows)) -and -not $Capabilities.SourceTree -and $Capabilities.VirtualTerminal)
}
# 仅用于终端URL展示，不改变调用者数据。
function Get-JobsUrlRanges {
    param([string]$Text)
    $pattern = '[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"''\x1b]+'
    $punctuation = '，。；：！？、（）【】《》「」『』“”‘’'
    $offset = 0
    while ($offset -lt $Text.Length) {
        $match = [regex]::Match($Text.Substring($offset), $pattern)
        if (-not $match.Success) { break }
        $start = $offset + $match.Index
        $url = $match.Value
        foreach ($mark in $punctuation.ToCharArray()) {
            $at = $url.IndexOf($mark)
            if ($at -ge 0) { $url = $url.Substring(0, $at) }
        }
        while ($url.Length) {
            $last = $url.Substring($url.Length - 1, 1)
            $unmatched = $false
            foreach ($pair in @(@('(', ')'), @('[', ']'), @('{', '}'))) {
                if ($last -eq $pair[1] -and ([regex]::Matches($url, [regex]::Escape($pair[1]))).Count -gt ([regex]::Matches($url, [regex]::Escape($pair[0]))).Count) { $unmatched = $true }
            }
            if ('. , ; : ! ?'.Split(' ') -contains $last -or $unmatched) { $url = $url.Substring(0, $url.Length - 1) }
            else { break }
        }
        [pscustomobject]@{ Start = $start; End = $start + $url.Length }
        $offset = $start + $url.Length
    }
}
# 仅用于终端URL展示，不改变调用者数据。
function Format-JobsUrlText {
    param([AllowEmptyString()][string]$Text, [switch]$Color)
    $control = '\x1b\][^\x1b\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]'
    $sgr = '\x1b\[[0-9;:]*m'
    $value = [regex]::Replace($Text, $control, {
        param($match)
        if ($Color -and $match.Value -match ('^' + $sgr + '$')) { return $match.Value }
        return ''
    })
    if (-not $Color) { return $value }
    $styles = @{}; $visible = New-Object Text.StringBuilder; $offset = 0
    foreach ($match in [regex]::Matches($value, $sgr)) {
        [void]$visible.Append($value.Substring($offset, $match.Index - $offset))
        $index = $visible.Length
        if (-not $styles.ContainsKey($index)) { $styles[$index] = '' }
        $styles[$index] += $match.Value
        $offset = $match.Index + $match.Length
    }
    [void]$visible.Append($value.Substring($offset))
    $plain = $visible.ToString(); $starts = @{}; $ends = @{}
    foreach ($range in @(Get-JobsUrlRanges $plain)) { $starts[$range.Start] = $true; $ends[$range.End - 1] = $true }
    $escape = [string][char]27; $active = ''; $inUrl = $false; $output = New-Object Text.StringBuilder
    for ($index = 0; $index -le $plain.Length; $index++) {
        if ($styles.ContainsKey($index)) {
            $tokens = $styles[$index]; [void]$output.Append($tokens)
            foreach ($match in [regex]::Matches($tokens, $sgr)) {
                $token = $match.Value; $code = $token.Substring(2, $token.Length - 3)
                $fields = $code.Split(';'); $reset = $code -eq ''
                for ($item = 0; $item -lt $fields.Count; $item++) {
                    if ($fields[$item] -eq '0') { $reset = $true }
                    if (@('38', '48', '58') -contains $fields[$item] -and $item + 1 -lt $fields.Count) {
                        if ($fields[$item + 1] -eq '2') { $item += 4 }
                        elseif ($fields[$item + 1] -eq '5') { $item += 2 }
                    }
                }
                if ($reset) { $active = '' }
                $active += $token
            }
            if ($inUrl) { [void]$output.Append($escape + '[32;4m') }
        }
        if ($index -eq $plain.Length) { break }
        if ($starts.ContainsKey($index)) { [void]$output.Append($escape + '[32;4m'); $inUrl = $true }
        [void]$output.Append($plain[$index])
        if ($ends.ContainsKey($index)) { [void]$output.Append($escape + '[0m' + $active); $inUrl = $false }
    }
    return $output.ToString()
}
# 仅用于终端URL展示，不改变调用者数据。
function Get-JobsDisplayBaseStyle {
    param([Collections.IDictionary]$Parameters)
    $codes = @{ Black=30; DarkBlue=34; DarkGreen=32; DarkCyan=36; DarkRed=31; DarkMagenta=35; DarkYellow=33; Gray=37; DarkGray=90; Blue=94; Green=92; Cyan=96; Red=91; Magenta=95; Yellow=93; White=97 }
    $style = ''; $escape = [string][char]27
    if ($Parameters.ContainsKey('ForegroundColor')) { $style += $escape + '[' + $codes[[string]$Parameters.ForegroundColor] + 'm' }
    if ($Parameters.ContainsKey('BackgroundColor')) { $style += $escape + '[' + ($codes[[string]$Parameters.BackgroundColor] + 10) + 'm' }
    return $style
}
# 单次绘制URL并保存纯文本信息记录，兼容原Write-Host参数。
function Write-JobsUrlText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ')
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    $plain = Format-JobsUrlText $text
    if (-not (Test-JobsEnterChoiceColor)) { Write-Host $plain -NoNewline:$NoNewline; return }
    $baseStyle = Get-JobsDisplayBaseStyle $PSBoundParameters
    $rendered = Format-JobsUrlText ($baseStyle + $text + ([string][char]27+'[0m')) -Color
    $message = New-Object Management.Automation.HostInformationMessage
    $message.Message = $plain
    $message.NoNewLine = [bool]$NoNewline
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $message.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $message.BackgroundColor = $BackgroundColor }
    Write-Information -MessageData $message -Tags 'JobsDisplay' -InformationAction SilentlyContinue
    [Console]::Write($rendered)
    if (-not $NoNewline) { [Console]::WriteLine() }
}

Set-StrictMode -Version 2.0

function Get-JobsVolumeFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw '文件路径必须是绝对路径。' }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem' -or $item.PSIsContainer -or
        ($item.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Device)) -ne 0) { throw '仅支持普通文件，不接受文件夹、链接或设备。' }
    return $item
}

function Get-JobsVolumePart {
    param([string]$Name)
    if ($Name -cnotmatch '^(.+)@([0-9]{1,9})of([0-9]{1,9})$') { throw '分卷命名必须是 完整文件名@序号of总数。' }
    $original = $Matches[1]
    $index = [int]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
    $total = [int]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
    if ($original -in @('.', '..') -or $original -match '[<>:"/\\|?*\x00-\x1f]|[. ]$' -or
        $original -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or
        $total -lt 1 -or $index -lt 1 -or $index -gt $total) { throw '非法原文件名或卷号。' }
    return [pscustomobject]@{ Name = $original; Index = $index; Total = $total }
}

function Get-JobsVolumeGroup {
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    if ($Paths.Count -lt 2 -or $Paths.Count -gt 10000) { throw '合并必须完整多选同组分卷（2 至 10000 卷）。' }
    $directory = ''; $name = ''; $parts = @{}; $bytes = [long]0
    foreach ($path in $Paths) {
        $file = Get-JobsVolumeFile $path
        $part = Get-JobsVolumePart $file.Name
        if ($part.Total -ne $Paths.Count -or $file.Length -le 0) { throw '总数与选择数量不符，或存在空分卷。' }
        if ($name.Length -eq 0) { $name = $part.Name; $directory = $file.DirectoryName }
        if ($part.Name -cne $name -or $file.DirectoryName -cne $directory -or $parts.ContainsKey($part.Index)) { throw '请选择同目录、同原文件名、无重复编号的一组完整分卷。' }
        $parts[$part.Index] = $file
        if ($bytes -gt ([long]::MaxValue - $file.Length)) { throw '分卷总长度超出支持范围。' }
        $bytes += $file.Length
    }
    $ordered = @()
    for ($index = 1; $index -le $Paths.Count; $index++) {
        if (-not $parts.ContainsKey($index)) { throw ('缺少第 ' + $index + ' 卷；请全选后重试。') }
        $ordered += $parts[$index]
    }
    return [pscustomobject]@{ Name = $name; Directory = $directory; Files = $ordered; Bytes = $bytes }
}

function Assert-JobsVolumeUnchanged {
    param($Snapshot)
    $current = Get-JobsVolumeFile $Snapshot.FullName
    if ($current.Length -ne $Snapshot.Length -or $current.LastWriteTimeUtc -ne $Snapshot.LastWriteTimeUtc -or
        $current.CreationTimeUtc -ne $Snapshot.CreationTimeUtc) { throw ('输入文件已变化，停止发布：' + $Snapshot.FullName) }
}

function Get-JobsVolumeDigest {
    param([Parameter(Mandatory = $true)][IO.Stream]$Stream)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($hash.ComputeHash($Stream)) } finally { $hash.Dispose() }
}

function Add-JobsVolumeStream {
    param([IO.Stream]$InputStream, [IO.Stream]$OutputStream, $Hash, [byte[]]$Buffer, [long]$Count)
    $remaining = $Count
    while ($remaining -gt 0) {
        $take = [int][Math]::Min($Buffer.Length, $remaining)
        $read = $InputStream.Read($Buffer, 0, $take)
        if ($read -le 0) { throw '输入提前结束，候选结果不发布。' }
        $OutputStream.Write($Buffer, 0, $read)
        [void]$Hash.TransformBlock($Buffer, 0, $read, $Buffer, 0)
        $remaining -= $read
    }
}

function Invoke-JobsFileMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Paths, [string]$OutputDirectory = '')
    $group = Get-JobsVolumeGroup $Paths
    if ([string]::IsNullOrEmpty($OutputDirectory)) { $OutputDirectory = $group.Directory }
    $outputItem = Get-Item -LiteralPath $OutputDirectory -Force -ErrorAction Stop
    if (-not $outputItem.PSIsContainer -or ($outputItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '输出位置必须是普通目录。' }
    $destination = Join-Path $outputItem.FullName $group.Name
    if (Test-Path -LiteralPath $destination) { throw ('目标已存在，拒绝覆盖：' + $destination) }
    $candidate = Join-Path $group.Directory ('.JobsMerge-' + [guid]::NewGuid().ToString('N') + '.partial')
    $inputs = New-Object 'Collections.Generic.List[IO.Stream]'
    $hash = [Security.Cryptography.SHA256]::Create()
    $output = $null
    try {
        # FileShare.Read 在 Windows 上阻止写入和删除；所有输入先锁定，再生成输出。
        foreach ($file in $group.Files) {
            $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $inputs.Add($stream)
            Assert-JobsVolumeUnchanged $file
            if ($stream.Length -ne $file.Length) { throw '输入长度已变化。' }
        }
        $output = [IO.File]::Open($candidate, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] 1048576
        for ($index = 0; $index -lt $inputs.Count; $index++) {
            Add-JobsVolumeStream -InputStream $inputs[$index] -OutputStream $output -Hash $hash -Buffer $buffer -Count $group.Files[$index].Length
        }
        [void]$hash.TransformFinalBlock([byte[]]@(), 0, 0)
        $expected = [Convert]::ToBase64String($hash.Hash)
        $output.Flush($true); $output.Dispose(); $output = $null
        $verify = [IO.File]::Open($candidate, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($verify.Length -ne $group.Bytes -or (Get-JobsVolumeDigest $verify) -cne $expected) { throw '候选长度 / SHA-256 校验失败。' }
        } finally { $verify.Dispose() }
        foreach ($file in $group.Files) { Assert-JobsVolumeUnchanged $file }
        [IO.File]::Move($candidate, $destination)
        Write-JobsUrlText ('✔ 合并完成：' + $destination + '；全部分卷保留。') -ForegroundColor Green
        return $destination
    } catch {
        if ([IO.File]::Exists($candidate)) { Write-Warning ('未发布候选保留：' + $candidate) }
        throw
    } finally {
        if ($null -ne $output) { $output.Dispose() }
        foreach ($stream in $inputs) { $stream.Dispose() }
        $hash.Dispose()
    }
}

function Invoke-JobsFileSplit {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][long]$LimitBytes)
    $file = Get-JobsVolumeFile $Path
    if ($LimitBytes -lt 1 -or $file.Length -le $LimitBytes) { throw '文件必须大于所选分卷上限；请调小上限后重试。' }
    $total = [long][Math]::Ceiling([decimal]$file.Length / [decimal]$LimitBytes)
    if ($total -gt 10000) { throw '超过 10000 卷，请调大分卷上限。' }
    $chunk = [long][Math]::Ceiling([decimal]$file.Length / [decimal]$total)
    $destination = Join-Path $file.DirectoryName ($file.Name + '.chunks')
    if (Test-Path -LiteralPath $destination) { throw ('分卷目录已存在，拒绝覆盖：' + $destination) }
    $candidate = Join-Path $file.DirectoryName ('.JobsSplit-' + [guid]::NewGuid().ToString('N') + '.partial')
    $inputStream = $null; $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $inputStream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        Assert-JobsVolumeUnchanged $file
        if ($inputStream.Length -ne $file.Length) { throw '源文件长度已变化。' }
        [void][IO.Directory]::CreateDirectory($candidate)
        $buffer = New-Object byte[] 1048576
        $remaining = $file.Length
        $volumes = @()
        for ($index = 1; $index -le $total; $index++) {
            $path = Join-Path $candidate ($file.Name + '@' + $index + 'of' + $total)
            $output = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $size = [long][Math]::Min($chunk, $remaining)
            try {
                Add-JobsVolumeStream -InputStream $inputStream -OutputStream $output -Hash $hash -Buffer $buffer -Count $size
                $output.Flush($true)
            } finally { $output.Dispose() }
            $volumes += $path; $remaining -= $size
        }
        if ($remaining -ne 0 -or $inputStream.Position -ne $inputStream.Length) { throw '拆分总长度校验失败。' }
        [void]$hash.TransformFinalBlock([byte[]]@(), 0, 0)
        $expected = [Convert]::ToBase64String($hash.Hash)
        $composed = [Security.Cryptography.SHA256]::Create()
        try {
            foreach ($path in $volumes) {
                $part = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    if ($part.Length -lt 1 -or $part.Length -gt $LimitBytes) { throw '分卷长度超出范围。' }
                    while (($read = $part.Read($buffer, 0, $buffer.Length)) -gt 0) { [void]$composed.TransformBlock($buffer, 0, $read, $buffer, 0) }
                } finally { $part.Dispose() }
            }
            [void]$composed.TransformFinalBlock([byte[]]@(), 0, 0)
            if ([Convert]::ToBase64String($composed.Hash) -cne $expected) { throw '分卷重组 SHA-256 不一致。' }
        } finally { $composed.Dispose() }
        $inputStream.Position = 0
        if ((Get-JobsVolumeDigest $inputStream) -cne $expected) { throw '源文件内容在拆分期间发生变化。' }
        Assert-JobsVolumeUnchanged $file
        [IO.Directory]::Move($candidate, $destination)
        Write-JobsUrlText ('✔ 拆分完成：' + $destination + '；源文件保留。') -ForegroundColor Green
        return $destination
    } catch {
        if ([IO.Directory]::Exists($candidate)) { Write-Warning ('未发布分卷保留：' + $candidate) }
        throw
    } finally {
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        $hash.Dispose()
    }
}

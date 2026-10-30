# Jobs 文件分卷交互；默认使用跨平台原始卷，旧 JobsSplit-1/gzip 通过 -LegacyManifest 保留。
# Created by Jobs on 2026年10月28日，星期三.

# 统一选择器的返回、取消与错误，不把空结果当成默认执行。
function Select-JobsVolumeOption {
    param([string[]]$Rows, [string]$Prompt, [switch]$CanBack)
    $fzf = Require-JobsCommand 'fzf'
    & $fzf --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'fzf 不可用，请修复后重试。' }
    $hint = '回车选择；Esc 取消'
    $arguments = @('--no-multi', '--height=60%', '--border', '--delimiter=\t', '--with-nth=2..', ('--prompt=' + $Prompt))
    if ($CanBack) { $hint += '；← 返回上一层'; $arguments += '--expect=left' }
    $arguments += '--header=' + $hint
    # PowerShell 5.1 原生命令管道默认 ASCII，局部切到 UTF-8 后恢复调用方编码。
    $previousOutputEncoding = $OutputEncoding
    $previousConsoleEncoding = [Console]::OutputEncoding
    try {
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = $OutputEncoding
        $result = @($Rows | & $fzf @arguments)
        $code = $LASTEXITCODE
    } finally {
        $OutputEncoding = $previousOutputEncoding
        [Console]::OutputEncoding = $previousConsoleEncoding
    }
    if ($CanBack -and $result.Count -gt 0 -and $result[0] -ceq 'left') { return [pscustomobject]@{ Action = 'back'; Row = '' } }
    if ($code -eq 1 -or $code -eq 130) { return [pscustomobject]@{ Action = 'cancel'; Row = '' } }
    if ($code -ne 0) { throw ('fzf 选择失败：' + $code) }
    $index = 0
    if ($CanBack) { $index = 1 }
    if ($result.Count -ne ($index + 1) -or [string]::IsNullOrEmpty($result[$index])) { throw '选择结果为空，未执行。' }
    return [pscustomobject]@{ Action = 'selected'; Row = $result[$index] }
}

# 十进制 MiB 转整数字节，拒绝零值及溢出。
function ConvertTo-JobsVolumeBytes {
    param([decimal]$MiB)
    $bytes = [decimal]::Floor($MiB * [decimal]1048576)
    if ($bytes -lt 1 -or $bytes -gt [long]::MaxValue) { throw '上限必须至少一个字节，且不能溢出。' }
    return [long]$bytes
}

# 标准上限使用 fzf；自定义输入可返回真实上层。
function Read-JobsVolumeLimit {
    while ($true) {
        $selected = Select-JobsVolumeOption -Rows @("50`t50 MiB", "100`t100 MiB", "1900`t1900 MiB", "custom`t自定义 MiB") -Prompt '分卷上限 > '
        if ($selected.Action -eq 'cancel') { return $null }
        $key = ($selected.Row -split "`t", 2)[0]
        if ($key -ne 'custom') { return ConvertTo-JobsVolumeBytes ([decimal]$key) }
        while ($true) {
            $answer = Read-JobsText '输入正数 MiB，可带小数；直接回车返回上限选择'
            if ($answer -eq '') { break }
            $number = [decimal]0
            if ($answer -notmatch '^[0-9]+(?:\.[0-9]+)?$' -or -not [decimal]::TryParse($answer, [Globalization.NumberStyles]::AllowDecimalPoint, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
                Write-JobsLog '请输入正数，例如 50、100 或 0.5。'; continue
            }
            try { return ConvertTo-JobsVolumeBytes $number } catch { Write-JobsLog $_.Exception.Message }
        }
    }
}

# 路径优先按原文解析，兼容拖入的引号，拒绝控制字符与链接祖先。
function Resolve-JobsVolumeInput {
    param([string]$Path)
    $candidate = $Path
    if (-not (Test-Path -LiteralPath $candidate)) { $candidate = $candidate.Trim().Trim('"') }
    if ($candidate -match '[\x00-\x1f\x7f]') { throw '路径包含控制字符。' }
    $candidate = [IO.Path]::GetFullPath($candidate)
    $current = $candidate
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '目标或上层目录是链接，停止。' }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return Get-Item -LiteralPath $candidate -Force
}

# 不递归扫描，目录模式逐次明确选择文件；← 可调整上限。
function Invoke-JobsRawSplitWorkflow {
    param($Target, [Nullable[decimal]]$LimitMiB)
    while ($true) {
        $limit = $null
        if ($null -ne $LimitMiB) { $limit = ConvertTo-JobsVolumeBytes $LimitMiB } else { $limit = Read-JobsVolumeLimit }
        if ($null -eq $limit) { Write-JobsLog '已取消，没有生成分卷。'; return }
        if (-not $Target.PSIsContainer) {
            $file = $Target
        } else {
            $files = @(Get-ChildItem -LiteralPath $Target.FullName -Force -File | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and $_.Length -gt $limit -and $_.Name -notmatch '[\x00-\x1f\x7f]' } | Sort-Object Name)
            if ($files.Count -eq 0) { Write-JobsLog '此目录没有超过上限的普通文件。'; return }
            $rows = @(); for ($index = 0; $index -lt $files.Count; $index++) { $rows += "$index`t$($files[$index].Name)（$($files[$index].Length) 字节）" }
            $selection = Select-JobsVolumeOption -Rows $rows -Prompt '待拆文件 > ' -CanBack:($null -eq $LimitMiB)
            if ($selection.Action -eq 'back') { if ($null -ne $LimitMiB) { return }; continue }
            if ($selection.Action -eq 'cancel') { Write-JobsLog '已取消，没有生成分卷。'; return }
            $key = ($selection.Row -split "`t", 2)[0]
            if ($key -notmatch '^\d+$' -or [int]$key -ge $files.Count) { throw '无效文件选择。' }
            $file = $files[[int]$key]
        }
        Show-JobsSource '文件拆分' $file.FullName ($file.FullName + '.chunks')
        Confirm-JobsChange ('按上限 ' + $limit + ' 字节拆分；源文件始终保留')
        $destination = Invoke-JobsFileSplit -Path $file.FullName -LimitBytes $limit
        Write-JobsLog ('已验证并发布：' + $destination)
        return
    }
}

# 扫描当前层与一级子目录，按完整原文件名分组，不把不同组拼接。
function Get-JobsRawVolumeGroups {
    param([string]$Directory)
    $directories = @((Get-Item -LiteralPath $Directory -Force)) + @(Get-ChildItem -LiteralPath $Directory -Directory -Force | Where-Object { $_.Name -notmatch '^\.' -and $_.Name -notin @('node_modules', 'Pods', 'PodsManual', 'build', 'DerivedData') -and $_.Name -notlike 'ManualBy*Pods@Pods' -and ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 })
    foreach ($dir in $directories) {
        $groups = @{}
        foreach ($file in Get-ChildItem -LiteralPath $dir.FullName -File -Force) {
            try { $part = Get-JobsVolumePart $file.Name } catch { continue }
            # Windows 文件系统名称匹配不区分大小写；运行前内核仍核对完整原名。
            if (-not $groups.ContainsKey($part.Name)) { $groups[$part.Name] = @() }
            $groups[$part.Name] += $file.FullName
        }
        foreach ($name in @($groups.Keys | Sort-Object)) {
            Write-Output ([pscustomobject]@{ Name = $name; Directory = $dir.FullName; Paths = [string[]]$groups[$name] })
        }
    }
}

# 单次明确选择一组，直接输入分卷目录时回到其父目录发布。
function Invoke-JobsRawMergeWorkflow {
    param($Target)
    if (-not $Target.PSIsContainer) { throw '合并请输入分卷目录或其父目录；旧清单用 -LegacyManifest。' }
    $groups = @(Get-JobsRawVolumeGroups $Target.FullName)
    if ($groups.Count -eq 0) { Write-JobsLog '未找到 原文件名@序号of总数 格式的分卷。'; return }
    $rows = @(); for ($index = 0; $index -lt $groups.Count; $index++) { $rows += "$index`t$($groups[$index].Name) — $($groups[$index].Directory)（$($groups[$index].Paths.Count) 卷）" }
    $selection = Select-JobsVolumeOption -Rows $rows -Prompt '合并分卷组 > '
    if ($selection.Action -eq 'cancel') { Write-JobsLog '已取消，没有合并。'; return }
    $key = ($selection.Row -split "`t", 2)[0]
    if ($key -notmatch '^\d+$' -or [int]$key -ge $groups.Count) { throw '无效分组选择。' }
    $group = $groups[[int]$key]
    $null = Get-JobsVolumeGroup -Paths $group.Paths
    $outputDirectory = $Target.FullName
    if ($group.Directory -ceq $Target.FullName) { $outputDirectory = [IO.Path]::GetDirectoryName($Target.FullName) }
    if ([string]::IsNullOrEmpty($outputDirectory)) { $outputDirectory = $Target.FullName }
    Show-JobsSource '完整分卷合并' $group.Directory (Join-Path $outputDirectory $group.Name)
    Confirm-JobsChange '只合并所选组，保留全部分卷，拒绝覆盖已有结果'
    $destination = Invoke-JobsFileMerge -Paths $group.Paths -OutputDirectory $outputDirectory
    Write-JobsLog ('已验证并发布：' + $destination)
}

# 公开入口先展示自述，-Check 只读，传统清单模式仍使用原实现。
function Invoke-JobsPortableVolumeTool {
    param([ValidateSet('SplitFile','MergeFile')][string]$Tool, [switch]$Check, [string]$Path, [Nullable[decimal]]$LimitMiB, [switch]$LegacyManifest, [string]$DefaultRoot)
    if ($LegacyManifest) {
        if (-not [string]::IsNullOrEmpty($Path) -or $null -ne $LimitMiB) { throw '-LegacyManifest 使用旧交互，不能与 -Path / -LimitMiB 混用。' }
        Invoke-JobsTool -Tool $Tool -Check:$Check
        return
    }
    $script:JobsLog = $null
    Write-Host '======== Jobs 跨平台原始分卷 ========' -ForegroundColor Red
    Write-Host '用途：原文件名@序号of总数，大小与 SHA-256 校验，无覆盖发布；原件始终保留。' -ForegroundColor Blue
    Write-Host '单文件 / 目录输入；目录只扫描当前层或合并时一级子目录。需要可用 fzf；Ctrl+C 取消。' -ForegroundColor Blue
    Write-Host '旧 JobsSplit-1 清单及 gzip 通过 -LegacyManifest 使用；日志在系统临时目录。' -ForegroundColor Blue
    if ($Check) {
        $fzf = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue
        Write-Host ('只读加载通过；fzf：' + $(if ($fzf) { '已发现，运行时继续检查可用性。' } else { '未发现，交互选择前需准备。' }))
        return
    }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '交互入口仅支持 Windows；其它平台可 -Check 或运行隔离内核测试。' }
    if ((Read-JobsText '按回车继续；其它输入取消') -ne '') { return }
    $script:JobsLog = Join-Path ([IO.Path]::GetTempPath()) ('Jobs-' + $Tool + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsLog ('日志：' + $script:JobsLog)
    if ([string]::IsNullOrEmpty($Path)) { $Path = Read-JobsText '输入单文件 / 目录，回车使用入口目录' $DefaultRoot }
    $target = Resolve-JobsVolumeInput $Path
    if ($Tool -eq 'SplitFile') { Invoke-JobsRawSplitWorkflow -Target $target -LimitMiB $LimitMiB } else { Invoke-JobsRawMergeWorkflow -Target $target }
}

#requires -Version 5.1
# Jobs 原始分卷 / 传统清单兼容隔离回归；仅临时文件，无安装或用户目录操作。
# Created by Jobs on 2026年10月28日，星期三.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Common/JobsTools.ps1')
. (Join-Path $root 'Common/FileVolumes.ps1')
. (Join-Path $root 'Common/FileVolumeWorkflow.ps1')
$script:assertions = 0
function Assert-Volume {
    param([bool]$Condition, [string]$Reason)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Reason) }
}
function Assert-VolumeThrows {
    param([scriptblock]$Run, [string]$Reason)
    $threw = $false
    try { & $Run | Out-Null } catch { $threw = $true }
    Assert-Volume $threw $Reason
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsPortableVolumes-' + [guid]::NewGuid().ToString('N'))
if ([IO.Directory]::Exists('/private/tmp')) { $temporary = Join-Path '/private/tmp' ([IO.Path]::GetFileName($temporary)) }
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $file = Join-Path $temporary "中文 & %TEMP% ' `$() [literal]@extra.bin"
    $data = New-Object byte[] 1048587
    $random = New-Object Random 419
    $random.NextBytes($data)
    [IO.File]::WriteAllBytes($file, $data)
    $digest = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $split = Invoke-JobsFileSplit -Path $file -LimitBytes 100000
    $paths = @(Get-ChildItem -LiteralPath $split -File | Sort-Object Name -Descending | ForEach-Object FullName)
    $output = Join-Path $temporary 'restored'
    [void][IO.Directory]::CreateDirectory($output)
    $merged = Invoke-JobsFileMerge -Paths $paths -OutputDirectory $output
    Assert-Volume ((Get-FileHash -LiteralPath $merged).Hash -ceq $digest) 'raw随机字节跨块拆分/乱序合并与原件SHA256一致'
    Assert-Volume ((Get-FileHash -LiteralPath $file).Hash -ceq $digest) '始终保留源文件'
    Assert-VolumeThrows { Invoke-JobsFileSplit -Path $file -LimitBytes 100000 } '已有分卷目录不覆盖'
    Assert-VolumeThrows { Invoke-JobsFileMerge -Paths $paths -OutputDirectory $output } '已有还原文件不覆盖'
    Assert-VolumeThrows { Get-JobsVolumeGroup -Paths @($paths[0], $paths[1]) } '缺卷不自动补齐'
    Assert-Volume ((ConvertTo-JobsVolumeBytes ([decimal]0.5)) -eq 524288) '小数MiB精确换算'
    foreach ($limit in @([decimal]0, [decimal]-1, [decimal]'0.0000001')) { Assert-VolumeThrows { ConvertTo-JobsVolumeBytes $limit } '无效字节上限拒绝' }

    # 模拟真实fzf出口，业务函数保持原实现；检查返回先于通用退出码判断。
    & {
        $script:FzfCode = 0; $script:FzfLines = @(); $script:FzfVersion = 0
        function Require-JobsCommand { param($Name) return 'Invoke-JobsFzfFixture' }
        function Invoke-JobsFzfFixture {
            if ($args -contains '--version') { $global:LASTEXITCODE = $script:FzfVersion; return }
            $null = @($input)
            $global:LASTEXITCODE = $script:FzfCode
            foreach ($line in $script:FzfLines) { Write-Output $line }
        }
        $script:FzfCode = 1; $script:FzfLines = @('left')
        $choice = Select-JobsVolumeOption -Rows @("x`tname") -Prompt 'test' -CanBack
        Assert-Volume ($choice.Action -ceq 'back') '←即使无匹配退出1仍返回真正上层'
        foreach ($code in @(1, 130)) {
            $script:FzfCode = $code; $script:FzfLines = @()
            $choice = Select-JobsVolumeOption -Rows @("x`tname") -Prompt 'test'
            Assert-Volume ($choice.Action -ceq 'cancel') '空匹配/Esc均取消'
        }
        $script:FzfCode = 0; $script:FzfLines = @()
        Assert-VolumeThrows { Select-JobsVolumeOption -Rows @("x`tname") -Prompt 'test' } '成功退出但空结果不能默认执行'
        $script:FzfLines = @('', "x`tname")
        $choice = Select-JobsVolumeOption -Rows @("x`tname") -Prompt 'test' -CanBack
        Assert-Volume ($choice.Action -ceq 'selected' -and $choice.Row -ceq "x`tname") '空expect行与真实选择分开解析'
        $script:FzfCode = 2; $script:FzfLines = @()
        Assert-VolumeThrows { Select-JobsVolumeOption -Rows @("x`tname") -Prompt 'test' } '选择器错误不伪装成取消'
        $script:FzfVersion = 2
        Assert-VolumeThrows { Select-JobsVolumeOption -Rows @("x`tname") -Prompt 'test' } 'fzf损坏立即停止'
    }

    & {
        $script:Choices = New-Object 'Collections.Generic.Queue[object]'
        $script:Text = New-Object 'Collections.Generic.Queue[string]'
        function Select-JobsVolumeOption { param($Rows, $Prompt, [switch]$CanBack) return $script:Choices.Dequeue() }
        function Read-JobsText { param($Prompt, $Default) return $script:Text.Dequeue() }
        $script:Choices.Enqueue([pscustomobject]@{ Action = 'selected'; Row = "custom`t自定义" })
        $script:Choices.Enqueue([pscustomobject]@{ Action = 'selected'; Row = "100`t100 MiB" })
        $script:Text.Enqueue('')
        Assert-Volume ((Read-JobsVolumeLimit) -eq 104857600) '自定义空输入返回上限选择'
        $script:Choices.Enqueue([pscustomobject]@{ Action = 'cancel'; Row = '' })
        Assert-Volume ($null -eq (Read-JobsVolumeLimit)) '上限Esc保持取消'
        $script:confirmed = 0
        function Confirm-JobsChange { param($Message) $script:confirmed++ }
        $script:Choices.Enqueue([pscustomobject]@{ Action = 'cancel'; Row = '' })
        Invoke-JobsRawSplitWorkflow -Target (Get-Item -LiteralPath $temporary) -LimitMiB ([decimal]0.1)
        Assert-Volume ($script:confirmed -eq 0) '目录文件选择取消不确认或拆分'
        $script:Choices.Enqueue([pscustomobject]@{ Action = 'back'; Row = '' })
        Invoke-JobsRawSplitWorkflow -Target (Get-Item -LiteralPath $temporary) -LimitMiB ([decimal]0.1)
        Assert-Volume ($script:confirmed -eq 0) '显式上限目录←不执行业务'
        $script:Choices.Enqueue([pscustomobject]@{ Action = 'cancel'; Row = '' })
        Invoke-JobsRawMergeWorkflow -Target (Get-Item -LiteralPath $split)
        Assert-Volume ($script:confirmed -eq 0) '合并组取消不发布'
    }

    # -Check默认走raw；只有显式LegacyManifest才分流旧工具。
    & {
        $script:legacyCalls = @()
        function Invoke-JobsTool { param($Tool, [switch]$Check) $script:legacyCalls += ($Tool + ':' + $Check) }
        Invoke-JobsPortableVolumeTool -Tool SplitFile -Check -DefaultRoot $temporary
        Invoke-JobsPortableVolumeTool -Tool MergeFile -Check -DefaultRoot $temporary
        Assert-Volume ($script:legacyCalls.Count -eq 0) '默认只读入口不进入旧manifest路径'
        Invoke-JobsPortableVolumeTool -Tool SplitFile -Check -LegacyManifest -DefaultRoot $temporary
        Invoke-JobsPortableVolumeTool -Tool MergeFile -Check -LegacyManifest -DefaultRoot $temporary
        Assert-Volume ($script:legacyCalls.Count -eq 2 -and $script:legacyCalls[0] -ceq 'SplitFile:True' -and $script:legacyCalls[1] -ceq 'MergeFile:True') 'LegacyManifest显式保留原分流和Check'
    }

    # 旧内核直接使用临时夹具；none与gzip清单都必须真实往返。
    foreach ($compression in @('none', 'gzip')) {
        & {
            $script:Answers = New-Object 'Collections.Generic.Queue[string]'
            function Read-JobsText { param($Prompt, $Default) return $script:Answers.Dequeue() }
            $destination = Join-Path $temporary ('legacy-' + $compression)
            $restored = Join-Path $temporary ('restored-' + $compression + '.bin')
            foreach ($answer in @($file, $destination, '1', $(if ($compression -eq 'gzip') { 'gzip' } else { '' }), 'YES')) { $script:Answers.Enqueue($answer) }
            Invoke-JobsSplit
            $manifestPath = Join-Path $destination 'manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-Volume ($manifest.Format -ceq 'JobsSplit-1' -and $manifest.Compression -ceq $compression) '旧JobsSplit-1清单及压缩标记保持'
            foreach ($answer in @($manifestPath, $restored, 'YES')) { $script:Answers.Enqueue($answer) }
            Invoke-JobsMerge
            Assert-Volume ((Get-FileHash -LiteralPath $restored).Hash -ceq $digest) ('旧manifest真实还原SHA256：' + $compression)
            Assert-Volume ((Get-FileHash -LiteralPath $file).Hash -ceq $digest -and [IO.File]::Exists((Join-Path $destination 'part-000001'))) '旧模式源文件及分卷保持'
            foreach ($answer in @($manifestPath, $restored)) { $script:Answers.Enqueue($answer) }
            Assert-VolumeThrows { Invoke-JobsMerge } '旧模式已有还原目标仍拒绝覆盖'
        }
    }
    [Console]::WriteLine(('PASS: FileVolumes.Tests.ps1 ({0} assertions)' -f $script:assertions))
} finally {
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}

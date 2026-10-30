#requires -Version 5.1
# Jobs Windows 文件工具隔离回归；仅在本次临时目录写入，不安装或修改系统。
[CmdletBinding()]
param([switch]$SkipEntrypoints)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('JobsOthersTest-'+[guid]::NewGuid().ToString('N'))
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){$fixture=Join-Path '/private/tmp' (Split-Path -Leaf $fixture)}
[void][IO.Directory]::CreateDirectory($fixture)
$script:count=0
# 失败时保留准确的业务标签。
function Assert-Equal($Actual,$Expected,[string]$Label){if($Actual -cne $Expected){throw "$Label；实际=$Actual；预期=$Expected"};$script:count++}
# 拒绝分支必须抛错，不能被误记为成功。
function Assert-Throws([scriptblock]$Body,[string]$Label){$failed=$false;try{& $Body}catch{$failed=$true};if(!$failed){throw "$Label：应当失败"};$script:count++}
try{
    & {
        . (Join-Path $root 'Common/JobsTools.ps1')
        $textFile=Join-Path $fixture '中文 [file].txt'
        Write-JobsUtf8 $textFile "# value`r`nold" $true
        Assert-Equal (Read-JobsUtf8 $textFile).Bom $true '读取 UTF8 BOM'
        $bad=Join-Path $fixture 'bad.txt';[IO.File]::WriteAllBytes($bad,[byte[]]@(255,254,0,0))
        Assert-Throws {Read-JobsUtf8 $bad} '拒绝二进制和 UTF16'
        $script:answers=New-Object 'Collections.Generic.Queue[string]'
        function Read-JobsText([string]$Prompt,[string]$Default=''){if(!$script:answers.Count){throw '夹具输入耗尽'};return $script:answers.Dequeue()}
        foreach($answer in @('','yes','Yes',' YES','YES ')){$script:answers.Enqueue($answer);Assert-Throws {Confirm-JobsChange '测试'} '危险确认只接受精确 YES'}
        $script:answers.Enqueue('YES');Confirm-JobsChange '测试';Assert-Equal $script:answers.Count 0 '精确 YES 放行'
        $script:answers.Enqueue($textFile);$script:answers.Enqueue('new value');$script:answers.Enqueue('YES')
        Invoke-JobsAppend
        Assert-Equal (Read-JobsUtf8 $textFile).Text "# value`r`nold`r`nnew value`r`n" '追加保留原文与换行'
        Assert-Equal (Read-JobsUtf8 $textFile).Bom $true '追加保留 BOM'
        $script:answers.Enqueue($textFile);$script:answers.Enqueue('new value');Invoke-JobsAppend
        Assert-Equal $script:answers.Count 0 '重复整行不再确认或写入'
        $originalConfirm=${function:Confirm-JobsChange}
        function Confirm-JobsChange([string]$Message){[IO.File]::AppendAllText($textFile,'concurrent')}
        $script:answers.Enqueue($textFile);$script:answers.Enqueue('must not overwrite')
        Assert-Throws {Invoke-JobsAppend} '确认期间并发修改停止'
        Assert-Equal (Read-JobsUtf8 $textFile).Text "# value`r`nold`r`nnew value`r`nconcurrent" '保留并发写入'
        Set-Item Function:Confirm-JobsChange $originalConfirm
        $scan=Join-Path $fixture 'scan';[void][IO.Directory]::CreateDirectory($scan)
        [IO.File]::WriteAllText((Join-Path $scan 'keep.txt'),'keep')
        foreach($skip in @('.git','node_modules','Pods','.dart_tool','build','DerivedData')){[void][IO.Directory]::CreateDirectory((Join-Path $scan $skip));[IO.File]::WriteAllText((Join-Path $scan "$skip/skip.txt"),'skip')}
        Assert-Equal (@(Get-JobsFiles $scan).Count) 1 '递归排除依赖与生成目录'
        if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
            $linked=Join-Path $fixture 'linked';New-Item -ItemType SymbolicLink -Path $linked -Target $scan|Out-Null
            $script:answers.Enqueue((Join-Path $linked 'keep.txt'));Assert-Throws {Get-JobsPath '路径'} '拒绝链接上层的已有文件'
            $script:answers.Enqueue((Join-Path $linked 'new.txt'));Assert-Throws {Get-JobsPath '路径' -AllowNew} '拒绝链接上层的新目标'
        }
        & {
            $replaceRoot=Join-Path $fixture 'replace tree';[void][IO.Directory]::CreateDirectory($replaceRoot)
            $replaceFile=Join-Path $replaceRoot '中文 [text].txt';Write-JobsUtf8 $replaceFile 'old $value [literal]' $true
            $untouched=Join-Path $replaceRoot 'other.txt';Write-JobsUtf8 $untouched 'keep' $false
            foreach($answer in @($replaceRoot,'old $value','new $value','YES')){$script:answers.Enqueue($answer)}
            Invoke-JobsReplace
            Assert-Equal (Read-JobsUtf8 $replaceFile).Text 'new $value [literal]' '目录替换按字面量处理特殊字符'
            Assert-Equal (Read-JobsUtf8 $replaceFile).Bom $true '目录替换保留 BOM'
            Assert-Equal (Read-JobsUtf8 $untouched).Text 'keep' '未命中文件保持'
            foreach($answer in @($replaceFile,'new $value','old $value','YES')){$script:answers.Enqueue($answer)}
            Invoke-JobsReplace
            Assert-Equal (Read-JobsUtf8 $replaceFile).Text 'old $value [literal]' '单文件替换仍可用'
            $linkKind='SymbolicLink';if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){$linkKind='Junction'}
            $replaceLink=Join-Path $fixture 'replace link'
            try{
                New-Item -ItemType $linkKind -Path $replaceLink -Target $replaceRoot|Out-Null
                foreach($path in @($replaceLink,(Join-Path $replaceLink '中文 [text].txt'))){
                    $script:answers.Enqueue($path)
                    Assert-Throws {Invoke-JobsReplace} '替换入口拒绝链接目录与链接祖先的文件'
                }
                Assert-Equal (Read-JobsUtf8 $replaceFile).Text 'old $value [literal]' '链接拒绝后源文件保持'
                Assert-Equal $script:answers.Count 0 '链接拒绝在读取替换文本与确认之前'
            }finally{if(Test-Path -LiteralPath $replaceLink){[IO.Directory]::Delete($replaceLink)}}
            $swapTarget=Join-Path $fixture 'swap target';[void][IO.Directory]::CreateDirectory($swapTarget)
            $swapFile=Join-Path $swapTarget '中文 [text].txt';Write-JobsUtf8 $swapFile 'old $value [literal]' $true
            $moved=Join-Path $fixture 'replace moved'
            function Confirm-JobsChange([string]$Message){
                [IO.Directory]::Move($replaceRoot,$moved)
                New-Item -ItemType $linkKind -Path $replaceRoot -Target $swapTarget|Out-Null
            }
            try{
                foreach($answer in @($replaceFile,'old $value','must not write')){$script:answers.Enqueue($answer)}
                Assert-Throws {Invoke-JobsReplace} '确认期间目录变为链接时停止'
                Assert-Equal (Read-JobsUtf8 $swapFile).Text 'old $value [literal]' '确认期间链接替换不写入新目标'
                Assert-Equal (Read-JobsUtf8 (Join-Path $moved '中文 [text].txt')).Text 'old $value [literal]' '确认期间保留原目录内容'
                Assert-Equal (@(Get-ChildItem -LiteralPath $swapTarget -File).Count) 1 '链接拒绝不在替代目标创建备份'
            }finally{if(Test-Path -LiteralPath $replaceRoot){[IO.Directory]::Delete($replaceRoot)}}
        }
        & {
            $literal=Join-Path $fixture 'literal %TEMP% [path].txt';Write-JobsUtf8 $literal 'keep'
            $script:answers.Enqueue($literal)
            Assert-Equal (Get-JobsPath '夹具') $literal '已有路径中的环境变量字面量保持'
            $newLiteral=Join-Path $fixture 'new %TEMP% [path].txt';$script:answers.Enqueue($newLiteral)
            Assert-Equal (Get-JobsPath '夹具' -AllowNew) $newLiteral '新目标路径中的环境变量字面量保持'
            $savedPathRoot=[Environment]::GetEnvironmentVariable('JOBS_REGRESSION_PATH_ROOT','Process')
            try{
                [Environment]::SetEnvironmentVariable('JOBS_REGRESSION_PATH_ROOT',$fixture,'Process')
                $script:answers.Enqueue('%JOBS_REGRESSION_PATH_ROOT%'+[IO.Path]::DirectorySeparatorChar+'literal %TEMP% [path].txt')
                Assert-Equal (Get-JobsPath '夹具') $literal '显式环境变量根仅展开首段'
                [Environment]::SetEnvironmentVariable('JOBS_REGRESSION_PATH_ROOT',$null,'Process')
                $script:answers.Enqueue('%JOBS_REGRESSION_PATH_ROOT%'+[IO.Path]::DirectorySeparatorChar+'missing.txt')
                Assert-Throws {Get-JobsPath '夹具' -AllowNew} '未设置环境变量根停止'
            }finally{[Environment]::SetEnvironmentVariable('JOBS_REGRESSION_PATH_ROOT',$savedPathRoot,'Process')}
        }
        $source=Join-Path $fixture 'binary source.bin';$bytes=New-Object byte[] (2*1024*1024+7)
        for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=[byte]($i%251)}
        [IO.File]::WriteAllBytes($source,$bytes)
        foreach($mode in @('','gzip')){
            $output=Join-Path $fixture ('parts-'+$(if($mode){$mode}else{'plain'}));$merged=$output+'.bin'
            foreach($answer in @($source,$output,'1',$mode,'YES')){$script:answers.Enqueue($answer)}
            Invoke-JobsSplit
            foreach($answer in @((Join-Path $output 'manifest.json'),$merged,'YES')){$script:answers.Enqueue($answer)}
            Invoke-JobsMerge
            Assert-Equal (Get-FileHash -LiteralPath $merged).Hash (Get-FileHash -LiteralPath $source).Hash ('分卷往返 '+$mode)
            $script:answers.Enqueue((Join-Path $output 'manifest.json'));$script:answers.Enqueue($merged)
            Assert-Throws {Invoke-JobsMerge} '重建拒绝覆盖已有目标'
            [IO.File]::AppendAllText((Join-Path $output 'part-000001'),'corruption')
            $script:answers.Enqueue((Join-Path $output 'manifest.json'));$script:answers.Enqueue($merged+'.other')
            Assert-Throws {Invoke-JobsMerge} '损坏卷在确认前停止'
            Assert-Equal (Test-Path -LiteralPath ($merged+'.other')) $false '损坏卷不发布目标'
        }
        $hostPath=(Get-Process -Id $PID).Path
        # 以编码源码保留引号，避免 5.1 的传统原生参数规则破坏此 PowerShell 夹具。
        $stderrProbe=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('[Console]::Error.WriteLine("fixture stderr"); exit 0'))
        Invoke-JobsNative $hostPath @('-NoLogo','-NoProfile','-EncodedCommand',$stderrProbe)
        Assert-Throws {Invoke-JobsNative $hostPath @('-NoLogo','-NoProfile','-Command','exit 7')} '原生命令非零失败'
        Assert-Throws {Invoke-JobsNative 'jobs-regression-command-does-not-exist' @()} '缺命令失败'
    }
    if(!$SkipEntrypoints){
        $hostPath=(Get-Process -Id $PID).Path
        foreach($entry in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '【WindowsOS】*.ps1'){
            & $hostPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $entry.FullName -Check|Out-Null
            Assert-Equal $LASTEXITCODE 0 ('只读入口 '+$entry.Name)
        }
    }
    Write-Host "PASS：$script:count 项断言；只使用临时夹具。"
}finally{Remove-Item -LiteralPath $fixture -Recurse -Force}

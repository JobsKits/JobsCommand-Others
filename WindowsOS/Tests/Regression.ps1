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

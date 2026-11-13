#requires -Version 5.1
# Jobs 原始分卷 / 传统清单兼容隔离回归；仅临时文件，无安装或用户目录操作。
# Created by Jobs on 2026年10月28日，星期三.
# BEGIN JOBS_TERMINAL_STYLE_V1 - session-only colors; no profile or registry changes.
function New-JobsTerminalStyleState {
    if ($PSVersionTable.PSVersion.Major -lt 5) { return @{ JobsTerminalPlainFallback = $true; Before = @{} } }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $Host.Name -ne 'ConsoleHost') { return $null }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $null }
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $null }
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$key -match '^(?i:SOURCE_?TREE)') { return $null }
    }
    if (-not ('Jobs.TerminalStyleV1.Native' -as [type])) {
        try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
namespace Jobs.TerminalStyleV1 {
    public static class Native {
        [StructLayout(LayoutKind.Explicit, Size=20, CharSet=CharSet.Unicode)]
        public struct InputRecord {
            [FieldOffset(0)] public ushort Kind;
            [FieldOffset(4)] public int Down;
            [FieldOffset(8)] public ushort Repeat;
            [FieldOffset(10)] public ushort Key;
            [FieldOffset(12)] public ushort Scan;
            [FieldOffset(14)] public char Character;
            [FieldOffset(16)] public uint Modifiers;
        }
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint mode);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint mode);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint count);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool ReadConsoleInputW(IntPtr h, [Out] InputRecord[] records, uint count, out uint read);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr h, InputRecord[] records, uint count, out uint written);
        const string OwnerName = "JOBS_TERMINAL_STYLE_WINDOWS_OWNER";
        static readonly string[] Keys = { "10", "11", "4;0", "4;1", "4;2", "4;3", "4;4", "4;5", "4;6", "4;7", "4;8", "4;9", "4;10", "4;11", "4;12", "4;13", "4;14", "4;15" };
        static readonly string[] Hex = { "000000", "ff5f56", "5fd787", "ffd75f", "5fafff", "d787ff", "5fd7ff", "eeeeee", "9e9e9e", "ff8787", "87ffaf", "ffff87", "87bfff", "ffafff", "afffff", "ffffff" };
        static readonly Regex Reply = new Regex("\\x1b\\](?<key>10|11|4;[0-9]{1,2});(?<rgb>rgb:[0-9a-f]{1,4}/[0-9a-f]{1,4}/[0-9a-f]{1,4})(?:\\x07|\\x1b\\\\)", RegexOptions.IgnoreCase);
        public sealed class State {
            public IntPtr Input, Output;
            public uint OutputMode;
            public ConsoleColor Foreground, Background;
            public Dictionary<string,string> Original, Applied;
            public string Owner, PreviousOwner, Recovery;
            public bool Active, ModeChanged, Fallback;
            public Dictionary<string,string> EnvironmentBefore = new Dictionary<string,string>();
        }
        static string Escape(string key, string value) { return "\x1b]" + key + ";" + value + "\x07"; }
        static string Rgb(string hex) { return "rgb:" + hex.Substring(0,2) + "/" + hex.Substring(2,2) + "/" + hex.Substring(4,2); }
        static string Normal(string rgb) {
            string[] parts = rgb.Substring(4).Split('/');
            for (int n=0; n<3; n++) {
                int maximum = (1 << (4 * parts[n].Length)) - 1;
                int value = Convert.ToInt32(parts[n],16);
                parts[n] = ((value * 65535L + maximum/2) / maximum).ToString("x4");
            }
            return String.Join("/",parts);
        }
        // Preserve unrelated key/window records instead of consuming user input during color queries.
        static Dictionary<string,string> Query(State state) {
            uint pending;
            if (!GetNumberOfConsoleInputEvents(state.Input,out pending) || pending != 0) { return null; }
            StringBuilder commands = new StringBuilder();
            foreach (string key in Keys) { commands.Append(Escape(key,"?")); }
            Console.Write(commands.ToString());
            List<InputRecord> records = new List<InputRecord>();
            List<int> characterIndices = new List<int>();
            StringBuilder text = new StringBuilder();
            Dictionary<string,string> result = new Dictionary<string,string>();
            Stopwatch timer = Stopwatch.StartNew();
            try {
                while (timer.ElapsedMilliseconds < 600) {
                    if (result.Count == Keys.Length && GetNumberOfConsoleInputEvents(state.Input,out pending) && pending == 0) { break; }
                    if (WaitForSingleObject(state.Input,20) != 0) { continue; }
                    InputRecord[] item = new InputRecord[1]; uint read;
                    if (!ReadConsoleInputW(state.Input,item,1,out read) || read != 1) { break; }
                    int index = -1;
                    if (item[0].Kind == 1 && item[0].Character != '\0') {
                        if (item[0].Down != 0) { index = text.Length; text.Append(item[0].Character); }
                        else if (text.Length != 0 && text[text.Length-1] == item[0].Character) { index = text.Length-1; }
                    }
                    records.Add(item[0]); characterIndices.Add(index);
                    foreach (Match match in Reply.Matches(text.ToString())) {
                        string key = match.Groups["key"].Value;
                        if (Array.IndexOf(Keys,key) >= 0) { result[key] = match.Groups["rgb"].Value; }
                    }
                }
            } finally {
                bool[] used = new bool[text.Length];
                foreach (Match match in Reply.Matches(text.ToString())) {
                    for (int n=match.Index; n<match.Index+match.Length; n++) { used[n] = true; }
                }
                List<InputRecord> replay = new List<InputRecord>();
                for (int n=0; n<records.Count; n++) {
                    int index = characterIndices[n];
                    if (index < 0 || !used[index]) { replay.Add(records[n]); }
                }
                if (replay.Count != 0) {
                    uint written;
                    if (!WriteConsoleInputW(state.Input,replay.ToArray(),(uint)replay.Count,out written) || written != replay.Count) {
                        Console.Error.WriteLine("[Jobs] Could not replay terminal input; color protection is unavailable.");
                        result.Clear();
                    }
                }
            }
            return result.Count == Keys.Length ? result : null;
        }
        static void Plain(State state) {
            foreach (string key in new string[] { "NO_COLOR", "PLAIN_OUTPUT", "FORCE_COLOR", "CLICOLOR", "ANSI_COLORS_DISABLED" }) {
                state.EnvironmentBefore[key] = Environment.GetEnvironmentVariable(key);
                Environment.SetEnvironmentVariable(key, key == "FORCE_COLOR" || key == "CLICOLOR" ? "0" : "1");
            }
            state.Fallback = true;
        }
        public static void Enter(State state) {
            try {
                state.Input = GetStdHandle(-10); state.Output = GetStdHandle(-11);
                uint inputMode;
                if (!GetConsoleMode(state.Input,out inputMode) || !GetConsoleMode(state.Output,out state.OutputMode)) { Plain(state); return; }
                IntPtr window = GetConsoleWindow();
                if (window == IntPtr.Zero) { Plain(state); return; }
                string identity = window.ToInt64().ToString("x");
                state.PreviousOwner = Environment.GetEnvironmentVariable(OwnerName);
                if (!String.IsNullOrEmpty(state.PreviousOwner)) {
                    string[] owner = state.PreviousOwner.Split(':');
                    int pid; long started;
                    if (owner.Length == 3 && owner[0] == identity && Int32.TryParse(owner[1],out pid) && Int64.TryParse(owner[2],out started)) {
                        try { if (Process.GetProcessById(pid).StartTime.ToUniversalTime().Ticks == started) { return; } } catch {}
                    }
                }
                state.Foreground = Console.ForegroundColor; state.Background = Console.BackgroundColor;
                if ((state.OutputMode & 4) == 0) {
                    if (!SetConsoleMode(state.Output,state.OutputMode | 4)) { Plain(state); return; }
                    state.ModeChanged = true;
                }
                state.Original = Query(state);
                if (state.Original == null) { Restore(state); Plain(state); return; }
                state.Applied = new Dictionary<string,string>();
                state.Applied["10"] = "rgb:ff/ff/ff"; state.Applied["11"] = "rgb:00/00/00";
                for (int n=0; n<16; n++) { state.Applied["4;"+n] = Rgb(Hex[n]); }
                StringBuilder restore = new StringBuilder();
                foreach (string key in Keys) { restore.Append(Escape(key,state.Original[key])); }
                string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(restore.ToString()));
                state.Recovery = Path.Combine(Path.GetTempPath(),"JobsTerminalStyle-"+Process.GetCurrentProcess().Id+"-"+Guid.NewGuid().ToString("N")+".ps1");
                string manual = "# Restore only the session colors saved by this Jobs script.\r\n"+
                    "if ([Console]::IsOutputRedirected) { throw 'Run in the original console.' }\r\n"+
                    "Add-Type -Namespace Jobs -Name RecoveryConsole -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern System.IntPtr GetStdHandle(int n); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);'\r\n"+
                    "$h = [Jobs.RecoveryConsole]::GetStdHandle(-11); [uint32]$m = 0\r\n"+
                    "if (-not [Jobs.RecoveryConsole]::GetConsoleMode($h, [ref]$m)) { throw 'Run in the original console.' }\r\n"+
                    "try {\r\nif (-not [Jobs.RecoveryConsole]::SetConsoleMode($h, ($m -bor 4))) { throw 'Cannot enable terminal recovery.' }\r\n"+
                    "[Console]::Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+encoded+"')))\r\n"+
                    "[Console]::ForegroundColor = [ConsoleColor]"+((int)state.Foreground)+"\r\n"+
                    "[Console]::BackgroundColor = [ConsoleColor]"+((int)state.Background)+"\r\n"+
                    "[Console]::Write([string][char]27 + '[39;49m')\r\n"+
                    "} finally { [void][Jobs.RecoveryConsole]::SetConsoleMode($h, $m) }\r\n";
                File.WriteAllText(state.Recovery,manual,new UTF8Encoding(false));
                state.Owner = identity+":"+Process.GetCurrentProcess().Id+":"+Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
                Environment.SetEnvironmentVariable(OwnerName,state.Owner);
                state.Active = true;
                foreach (string key in Keys) { Console.Write(Escape(key,state.Applied[key])); }
                Console.ForegroundColor = ConsoleColor.White; Console.BackgroundColor = ConsoleColor.Black;
                Dictionary<string,string> check = Query(state);
                foreach (string key in Keys) {
                    if (check == null || Normal(check[key]) != Normal(state.Applied[key])) { Restore(state); Plain(state); return; }
                }
            } catch (Exception error) {
                Restore(state); Plain(state);
                Console.Error.WriteLine("[Jobs] Terminal style unavailable: " + error.Message);
            }
        }
        public static void Restore(State state) {
            if (state == null) { return; }
            try {
                if (state.Active) {
                    Dictionary<string,string> current = Query(state);
                    bool complete = current != null;
                    if (current != null) {
                        bool restoreForeground = Console.ForegroundColor == ConsoleColor.White && Normal(current["10"]) == Normal(state.Applied["10"]) && Normal(current["4;15"]) == Normal(state.Applied["4;15"]);
                        bool restoreBackground = Console.BackgroundColor == ConsoleColor.Black && Normal(current["11"]) == Normal(state.Applied["11"]) && Normal(current["4;0"]) == Normal(state.Applied["4;0"]);
                        foreach (string key in Keys) {
                            if (Normal(current[key]) == Normal(state.Applied[key])) { Console.Write(Escape(key,state.Original[key])); }
                            else if (Normal(current[key]) != Normal(state.Original[key])) {
                                complete = false; Console.Error.WriteLine("[Jobs] Kept a concurrent color change: " + key);
                            }
                        }
                        if (restoreForeground) { Console.ForegroundColor = state.Foreground; Console.Write("\x1b[39m"); }
                        if (restoreBackground) { Console.BackgroundColor = state.Background; Console.Write("\x1b[49m"); }
                    }
                    if (complete) {
                        Dictionary<string,string> check = Query(state);
                        foreach (string key in Keys) { if (check == null || Normal(check[key]) != Normal(state.Original[key])) { complete = false; } }
                    }
                    if (complete) { File.Delete(state.Recovery); }
                    else { Console.Error.WriteLine("[Jobs] Color restore needs review. Manual recovery: powershell -NoProfile -File \""+state.Recovery+"\""); }
                }
            } catch (Exception error) {
                Console.Error.WriteLine("[Jobs] Color restore failed: "+error.Message+"; recovery: "+state.Recovery);
            } finally {
                if (state.Owner != null && Environment.GetEnvironmentVariable(OwnerName) == state.Owner) { Environment.SetEnvironmentVariable(OwnerName,state.PreviousOwner); }
                state.Active = false;
                uint currentMode;
                if (state.ModeChanged && GetConsoleMode(state.Output,out currentMode) && currentMode == (state.OutputMode | 4)) { SetConsoleMode(state.Output,state.OutputMode); }
                state.ModeChanged = false;
                if (state.Fallback) {
                    foreach (KeyValuePair<string,string> pair in state.EnvironmentBefore) {
                        string applied = pair.Key == "FORCE_COLOR" || pair.Key == "CLICOLOR" ? "0" : "1";
                        if (Environment.GetEnvironmentVariable(pair.Key) == applied) { Environment.SetEnvironmentVariable(pair.Key,pair.Value); }
                    }
                    state.Fallback = false;
                }
            }
        }
    }
}
'@
        } catch {
            [Console]::Error.WriteLine('[Jobs] Terminal style setup failed; using plain output: ' + $_.Exception.Message)
            return @{ JobsTerminalPlainFallback = $true; Before = @{} }
        }
    }
    return New-Object Jobs.TerminalStyleV1.Native+State
}
# Guard setup is optional; failure keeps business behavior and the user's original terminal settings.
function Start-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in @('NO_COLOR', 'PLAIN_OUTPUT', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED')) {
            $State.Before[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $(if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }))
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Enter($State) }
}
# A finally block also runs for script exit and Ctrl+C; direct .NET calls avoid stopped pipelines.
function Stop-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in $State.Before.Keys) {
            $applied = if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }
            if ([Environment]::GetEnvironmentVariable($key) -ceq $applied) { [Environment]::SetEnvironmentVariable($key, $State.Before[$key]) }
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Restore($State) }
}
# END JOBS_TERMINAL_STYLE_V1

$__jobsTerminalStyleState = $null
try {
    if ($MyInvocation.InvocationName -ne '.') {
        $__jobsTerminalStyleState = New-JobsTerminalStyleState
        Start-JobsTerminalStyle $__jobsTerminalStyleState
    }
# BEGIN JOBS_TERMINAL_STYLE_ORIGINAL_BODY
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

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}

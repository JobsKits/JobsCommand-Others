#requires -Version 5.1
# 原始分卷与旧 JobsSplit-1/gzip：确认后执行业务；-Check 只读，原件保留。
param([switch]$Check, [string]$Path, [Nullable[decimal]]$LimitMiB, [switch]$LegacyManifest)
try {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common/JobsTools.ps1')
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common/FileVolumes.ps1')
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common/FileVolumeWorkflow.ps1')
    Invoke-JobsPortableVolumeTool -Tool 'SplitFile' -Check:$Check -Path $Path -LimitMiB $LimitMiB -LegacyManifest:$LegacyManifest -DefaultRoot $PSScriptRoot
    exit 0
} catch {
    Write-Host ('✖ ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

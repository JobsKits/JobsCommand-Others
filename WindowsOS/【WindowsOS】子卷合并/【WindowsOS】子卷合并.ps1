#requires -Version 5.1
# 数字卷号完整组还原；-LegacyManifest 保留旧清单/gzip；确认前不写业务。
param([switch]$Check, [string]$Path, [switch]$LegacyManifest)
try {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common/JobsTools.ps1')
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common/FileVolumes.ps1')
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common/FileVolumeWorkflow.ps1')
    Invoke-JobsPortableVolumeTool -Tool 'MergeFile' -Check:$Check -Path $Path -LegacyManifest:$LegacyManifest -DefaultRoot $PSScriptRoot
    exit 0
} catch {
    Write-Host ('✖ ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

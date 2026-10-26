#requires -Version 5.1
# Mock服务：对应 Windows 原生 / Docker 适配入口。确认前不执行业务；-Check 只加载检查。
param([switch]$Check)
try {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Common/JobsTools.ps1')
    Invoke-JobsTool -Tool 'Mock' -Check:$Check
    exit 0
} catch {
    Write-Host ('✖ ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

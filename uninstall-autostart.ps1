$ErrorActionPreference = "Stop"

$TaskName = "CampusNetworkAutoLogin"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VbsPath = Join-Path $ScriptDir "CampusNetworkAutoLogin.vbs"
$StartupFolder = [Environment]::GetFolderPath("Startup")
$StartupFile = Join-Path $StartupFolder "CampusNetworkAutoLogin.cmd"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "已移除自启动任务：$TaskName"
}
else {
    Write-Host "未找到自启动任务：$TaskName"
}

if (Test-Path $StartupFile) {
    Remove-Item -LiteralPath $StartupFile -Force
    Write-Host "已移除启动文件：$StartupFile"
}
else {
    Write-Host "未找到启动文件：$StartupFile"
}

if (Test-Path $VbsPath) {
    Remove-Item -LiteralPath $VbsPath -Force
    Write-Host "已移除无窗口启动脚本：$VbsPath"
}
else {
    Write-Host "未找到无窗口启动脚本：$VbsPath"
}

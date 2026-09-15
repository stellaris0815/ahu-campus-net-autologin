param(
    [switch]$OneShot
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LoginScript = Join-Path $ScriptDir "campus-login.ps1"
$TaskName = "CampusNetworkAutoLogin"
$StartupFolder = [Environment]::GetFolderPath("Startup")
$StartupFile = Join-Path $StartupFolder "CampusNetworkAutoLogin.cmd"

$watchdogArg = if ($OneShot) { "" } else { " -Watchdog" }

if (-not (Test-Path $LoginScript)) {
    throw "找不到登录脚本：$LoginScript"
}

try {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LoginScript`"$watchdogArg"

    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "自动登录 Dr.COM 校园网认证页面。" `
        -Force `
        -ErrorAction Stop | Out-Null

    $registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $registered) {
        throw "任务计划程序未成功创建：$TaskName"
    }

    if (Test-Path $StartupFile) {
        Remove-Item -LiteralPath $StartupFile -Force
    }

    Write-Host "已安装任务计划程序自启动：$TaskName"
    if ($OneShot) {
        Write-Host "模式：登录一次并重试若干次后退出。"
    }
    else {
        Write-Host "模式：看门狗（常驻后台，约每 5 分钟检测一次，掉线自动重登）。"
    }
    Write-Host "当前 Windows 用户登录后会自动运行。"
}
catch {
    if (-not (Test-Path $StartupFolder)) {
        New-Item -ItemType Directory -Path $StartupFolder | Out-Null
    }

    $cmd = @(
        "@echo off",
        "start `"`" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LoginScript`"$watchdogArg"
    )
    Set-Content -Path $StartupFile -Value $cmd -Encoding ASCII

    Write-Host "任务计划程序不可用，已改用启动文件夹自启动。"
    Write-Host "启动文件：$StartupFile"
    if ($OneShot) {
        Write-Host "模式：登录一次并重试若干次后退出。"
    }
    else {
        Write-Host "模式：看门狗（常驻后台，约每 5 分钟检测一次，掉线自动重登）。"
    }
    Write-Host "当前 Windows 用户登录后会自动运行。"
}

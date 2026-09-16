param(
    [switch]$OneShot
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LoginScript = Join-Path $ScriptDir "campus-login.ps1"
$ConfigPath = Join-Path $ScriptDir "campus-login.config.json"
$TaskName = "CampusNetworkAutoLogin"
$StartupFolder = [Environment]::GetFolderPath("Startup")
$StartupFile = Join-Path $StartupFolder "CampusNetworkAutoLogin.cmd"

$watchdogArg = if ($OneShot) { "" } else { " -Watchdog" }

if (-not (Test-Path $LoginScript)) {
    throw "找不到登录脚本：$LoginScript"
}

$intervalMinutes = 5
if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.WatchdogIntervalMinutes) {
            $intervalMinutes = [int]$cfg.WatchdogIntervalMinutes
        }
    }
    catch {
        $intervalMinutes = 5
    }
}
if ($intervalMinutes -lt 1) {
    $intervalMinutes = 5
}

try {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LoginScript`"$watchdogArg"

    if ($OneShot) {
        $trigger = New-ScheduledTaskTrigger -AtLogOn
    }
    else {
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $repeatTemplate = New-ScheduledTaskTrigger `
            -Once `
            -At (Get-Date).AddMinutes(1) `
            -RepetitionInterval (New-TimeSpan -Minutes $intervalMinutes) `
            -RepetitionDuration (New-TimeSpan -Days 3650)
        $trigger.Repetition = $repeatTemplate.Repetition
    }

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
        -Description "自动登录安徽大学校园网 Dr.COM 认证页面。" `
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
        Write-Host "模式：一次性自启动，开机只登录一次。"
    }
    else {
        Write-Host "模式：定时自动重连（每 $intervalMinutes 分钟运行一次，登录成功后退出）。"
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
        Write-Host "模式：一次性自启动，开机只登录一次。"
    }
    else {
        Write-Host "模式：已降级为开机自动登录一次；定时自动重连需要管理员权限创建任务计划程序。"
        Write-Host "请右键 PowerShell 以管理员身份运行：.\install-autostart.ps1"
    }
    Write-Host "当前 Windows 用户登录后会自动运行。"
}

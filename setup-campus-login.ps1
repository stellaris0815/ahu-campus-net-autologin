$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "campus-login.config.json"

function Read-WithDefault {
    param(
        [string]$Prompt,
        [string]$Default
    )

    $text = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $Default
    }
    $text.Trim()
}

Write-Host "校园网自动登录配置"
Write-Host "密码会使用 Windows DPAPI 加密，只能由当前 Windows 用户解密。"
Write-Host ""

$defaultPortal = "http://172.16.253.3/a79.htm"
$portalPageUrl = Read-WithDefault "认证页面地址" $defaultPortal
$username = Read-Host "校园网账号"
$suffix = Read-WithDefault "账号后缀（如果账号已带 @ 则留空；否则请手动输入你实际使用的后缀）" ""
if ($username.Contains("@")) {
    $suffix = ""
}

$securePassword = Read-Host "校园网密码" -AsSecureString
$encryptedPassword = $securePassword | ConvertFrom-SecureString

$config = [ordered]@{
    PortalPageUrl = $portalPageUrl
    PortalHost = "172.16.253.3"
    LoginMethod = 1
    JsVersion = "3.3.2"
    Username = $username
    AccountSuffix = $suffix
    AccountPrefix = ""
    EncryptedPassword = $encryptedPassword
    MaxAttempts = 8
    RetrySeconds = 15
    AlwaysTryLogin = $false
    WatchdogIntervalMinutes = 5
    CampusProbeAttempts = 6
    CampusProbeRetrySeconds = 10
    ConnectivityCheckUrls = @(
        "http://www.msftconnecttest.com/connecttest.txt",
        "http://connectivitycheck.gstatic.com/generate_204",
        "http://neverssl.com/"
    )
}

$config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
Write-Host ""
Write-Host "配置已写入：$ConfigPath"
Write-Host "运行 .\campus-login.ps1 -Once 测试登录。"
Write-Host "运行 .\campus-login.ps1 -Watchdog 可常驻检测，掉线自动重连。"

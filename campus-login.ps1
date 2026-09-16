param(
    [switch]$Once,
    [switch]$ValidateOnly,
    [switch]$Watchdog,
    [switch]$NoClose
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir "campus-login.config.json"
$LogDir = Join-Path $ScriptDir "logs"
$LogPath = Join-Path $LogDir "campus-login.log"
$LogMaxBytes = 1MB

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    }

    if (Test-Path $LogPath) {
        $item = Get-Item -LiteralPath $LogPath
        if ($item.Length -gt $LogMaxBytes) {
            $old = "$LogPath.old"
            Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $LogPath -Destination $old -Force
            Write-Host "日志超过 1MB，已轮转为 $old"
        }
    }

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-PlainTextPassword {
    param([string]$EncryptedPassword)

    $secure = ConvertTo-SecureString $EncryptedPassword
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function ConvertTo-QueryString {
    param([hashtable]$Data)

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Data.Keys) {
        $value = [string]$Data[$key]
        $parts.Add(("{0}={1}" -f [Uri]::EscapeDataString([string]$key), [Uri]::EscapeDataString($value)))
    }
    $parts -join "&"
}

function Get-QueryValue {
    param(
        [string]$Url,
        [string[]]$Names
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return ""
    }

    $uri = [Uri]$Url
    $query = $uri.Query.TrimStart("?")
    if ([string]::IsNullOrWhiteSpace($query)) {
        return ""
    }

    foreach ($pair in $query -split "&") {
        if ([string]::IsNullOrWhiteSpace($pair)) {
            continue
        }

        $nameValue = $pair -split "=", 2
        $name = [Uri]::UnescapeDataString($nameValue[0])
        foreach ($target in $Names) {
            if ($name -ieq $target) {
                if ($nameValue.Count -lt 2) {
                    return ""
                }
                return [Uri]::UnescapeDataString($nameValue[1])
            }
        }
    }

    ""
}

function Get-JsStringValue {
    param(
        [string]$Html,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Html)) {
        return ""
    }

    $pattern = "(?s)(?:var\s+)?$([regex]::Escape($Name))\s*=\s*'([^']*)'"
    $match = [regex]::Match($Html, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    ""
}

function Convert-HexIpToString {
    param([string]$HexIp)

    if ($HexIp -notmatch "^[0-9a-fA-F]{8}$") {
        return ""
    }

    $octets = for ($i = 0; $i -lt 8; $i += 2) {
        [Convert]::ToInt32($HexIp.Substring($i, 2), 16)
    }
    $octets -join "."
}

function Test-IsValidIPv4 {
    param([string]$Ip)

    if ([string]::IsNullOrWhiteSpace($Ip)) {
        return $false
    }

    if ($Ip -notmatch "^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}$") {
        return $false
    }

    if ($Ip -eq "0.0.0.0" -or $Ip -eq "000.000.000.000") {
        return $false
    }

    $true
}

function Get-LocalIPv4 {
    $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.PrefixOrigin -ne "WellKnown"
        } |
        Sort-Object InterfaceMetric, InterfaceIndex

    foreach ($address in $addresses) {
        return $address.IPAddress
    }

    ""
}


function Test-PortalReachable {
    param(
        [object]$Config,
        [int]$TimeoutSec = 5
    )

    $portalPageUrl = if ($Config.PortalPageUrl) { [string]$Config.PortalPageUrl } else { "http://172.16.253.3/a79.htm" }

    try {
        $response = Invoke-WebRequest -Uri $portalPageUrl -UseBasicParsing -TimeoutSec $TimeoutSec -MaximumRedirection 3
        return $true
    }
    catch {
        return $false
    }
}

function Get-InternetState {
    param([object]$Config)

    $urls = @($Config.ConnectivityCheckUrls)
    if ($urls.Count -eq 0) {
        $urls = @("http://www.msftconnecttest.com/connecttest.txt")
    }

    foreach ($url in $urls) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 5
            $finalUrl = $response.BaseResponse.ResponseUri.AbsoluteUri
            $content = [string]$response.Content

            if ($finalUrl -match "/a\d+\.htm" -or $finalUrl -match "172\.16\.253\.3") {
                return [pscustomobject]@{
                    Online = $false
                    PortalUrl = $finalUrl
                    Reason = "检测到认证页跳转"
                }
            }

            if ($content -match "Dr\.COMWebLoginID|a41\.js|DDDDD|upass|wlanuserip|/eportal/") {
                return [pscustomobject]@{
                    Online = $false
                    PortalUrl = ""
                    Reason = "检测到认证页内容"
                }
            }

            $knownGoodContent =
                ($url -match "msftconnecttest" -and $content -match "Microsoft Connect Test") -or
                ($url -match "neverssl" -and $content -match "NeverSSL")

            if ($response.StatusCode -eq 204 -or $knownGoodContent) {
                return [pscustomobject]@{
                    Online = $true
                    PortalUrl = ""
                    Reason = "联网检测通过"
                }
            }
        }
        catch {
            $message = $_.Exception.Message
            $response = $_.Exception.Response
            if ($response -and $response.ResponseUri -and $response.ResponseUri.AbsoluteUri -match "/a\d+\.htm") {
                return [pscustomobject]@{
                    Online = $false
                    PortalUrl = $response.ResponseUri.AbsoluteUri
                    Reason = "检测到认证页跳转"
                }
            }

            Write-Log "联网检测失败：${url}，$message" "WARN"
        }
    }

    [pscustomobject]@{
        Online = $false
        PortalUrl = ""
        Reason = "联网检测未通过"
    }
}

function Invoke-JsonpRequest {
    param(
        [string]$Url,
        [hashtable]$Data,
        [int]$TimeoutSec = 12
    )

    $callback = "dr{0}" -f (Get-Random -Minimum 1000 -Maximum 9999)
    $payload = @{}
    $payload["callback"] = $callback
    foreach ($key in $Data.Keys) {
        $payload[$key] = $Data[$key]
    }
    $payload["v"] = Get-Random -Minimum 500 -Maximum 10500

    $separator = if ($Url.Contains("?")) { "&" } else { "?" }
    $requestUrl = $Url + $separator + (ConvertTo-QueryString $payload)
    $response = Invoke-WebRequest -Uri $requestUrl -UseBasicParsing -TimeoutSec $TimeoutSec
    $content = $response.Content.Trim()

    $pattern = "^\s*$([regex]::Escape($callback))\s*\((.*)\)\s*;?\s*$"
    $match = [regex]::Match($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
        throw "认证接口返回内容格式不符合预期：$content"
    }

    $match.Groups[1].Value | ConvertFrom-Json
}

function Get-PortalErrorMessage {
    param([object]$Result)

    if ($Result.msg) {
        return [string]$Result.msg
    }

    $retCode = $Result.ret_code
    if ($null -eq $retCode) {
        return "未知错误"
    }

    $messages = @{
        1 = "账号、密码或服务后缀不匹配"
        2 = "该 IP 已在线"
        3 = "认证系统忙"
        4 = "未知认证错误"
        5 = "认证挑战请求失败"
        6 = "认证挑战请求超时"
        7 = "认证失败"
        8 = "认证超时"
        9 = "下线失败"
        10 = "认证服务器拒绝请求"
    }

    $code = [int]$retCode
    if ($messages.ContainsKey($code)) {
        return "ret_code=$code，$($messages[$code])"
    }

    "ret_code=$code"
}

function Get-PortalContext {
    param(
        [object]$Config,
        [string]$DiscoveredPortalUrl
    )

    $portalPageUrl = if (-not [string]::IsNullOrWhiteSpace($DiscoveredPortalUrl)) {
        $DiscoveredPortalUrl
    }
    else {
        $Config.PortalPageUrl
    }

    if ([string]::IsNullOrWhiteSpace($portalPageUrl)) {
        $portalPageUrl = "http://172.16.253.3/a79.htm"
    }

    Write-Log "正在读取认证页面：$portalPageUrl"
    $page = Invoke-WebRequest -Uri $portalPageUrl -UseBasicParsing -TimeoutSec 12
    $html = $page.Content
    $finalPortalPageUrl = $page.BaseResponse.ResponseUri.AbsoluteUri

    $pageIp = Get-JsStringValue $html "v46ip"
    if ([string]::IsNullOrWhiteSpace($pageIp)) {
        $pageIp = Get-JsStringValue $html "ss5"
    }
    if ([string]::IsNullOrWhiteSpace($pageIp)) {
        $pageIp = Convert-HexIpToString (Get-JsStringValue $html "ss3")
    }

    $querySourceUrl = if (-not [string]::IsNullOrWhiteSpace(([Uri]$finalPortalPageUrl).Query)) {
        $finalPortalPageUrl
    }
    elseif (-not [string]::IsNullOrWhiteSpace($DiscoveredPortalUrl)) {
        $DiscoveredPortalUrl
    }
    else {
        $Config.PortalPageUrl
    }

    $queryWlanUserIp = Get-QueryValue $querySourceUrl @("ip", "wlanuserip", "userip", "user-ip", "UserIP", "uip", "station_ip")
    $pageIpValid = Test-IsValidIPv4 $pageIp
    $queryIpValid = Test-IsValidIPv4 $queryWlanUserIp

    if ($pageIpValid) {
        $wlanUserIp = $pageIp
        if ($queryIpValid -and $queryWlanUserIp -ne $pageIp) {
            Write-Log "认证页实时 IP=$pageIp，URL 参数 IP=$queryWlanUserIp，优先使用认证页实时 IP。" "WARN"
        }
    }
    elseif ($queryIpValid) {
        $wlanUserIp = $queryWlanUserIp
    }
    else {
        $wlanUserIp = $queryWlanUserIp
    }

    if ([string]::IsNullOrWhiteSpace($wlanUserIp) -or $wlanUserIp -eq "000.000.000.000") {
        $wlanUserIp = Get-LocalIPv4
    }

    $wlanUserMac = (Get-QueryValue $querySourceUrl @("mac", "usermac", "wlanusermac", "umac", "client_mac", "station_mac"))
    if ([string]::IsNullOrWhiteSpace($wlanUserMac)) {
        $wlanUserMac = Get-JsStringValue $html "ss4"
    }
    if ([string]::IsNullOrWhiteSpace($wlanUserMac)) {
        $wlanUserMac = "000000000000"
    }
    $wlanUserMac = $wlanUserMac -replace "[:-]", ""

    $portalHost = $Config.PortalHost
    if ([string]::IsNullOrWhiteSpace($portalHost)) {
        $portalHost = ([Uri]$finalPortalPageUrl).Host
    }

    $loginMethod = $Config.LoginMethod
    if (-not $loginMethod) {
        $loginMethod = 1
    }

    [pscustomobject]@{
        PortalHost = $portalHost
        WlanUserIp = $wlanUserIp
        WlanUserIpv6 = ""
        WlanUserMac = $wlanUserMac
        WlanAcIp = Get-QueryValue $querySourceUrl @("wlanacip", "acip", "switchip", "nasip", "nas-ip")
        WlanAcName = Get-QueryValue $querySourceUrl @("wlanacname", "sysname", "nasname", "nas-name")
        LoginMethod = [int]$loginMethod
        JsVersion = if ($Config.JsVersion) { $Config.JsVersion } else { "3.3.2" }
    }
}

function Invoke-CampusLogin {
    param([object]$Config)

    $state = Get-InternetState $Config
    Write-Log "联网状态：online=$($state.Online)，原因=$($state.Reason)"
    if ($state.Online -and -not $Config.AlwaysTryLogin) {
        Write-Log "当前已经联网，跳过登录。"
        return $true
    }

    $context = Get-PortalContext $Config $state.PortalUrl
    if ([string]::IsNullOrWhiteSpace($context.WlanUserIp) -or $context.WlanUserIp -eq "000.000.000.000") {
        throw "无法确定 wlan_user_ip。请先手动打开一次认证页，然后更新 campus-login.config.json 里的 PortalPageUrl。"
    }

    $username = [string]$Config.Username
    $suffix = [string]$Config.AccountSuffix
    if ($username.Contains("@")) {
        $suffix = ""
    }

    $prefix = [string]$Config.AccountPrefix
    $account = "{0}{1}{2}" -f $prefix, $username, $suffix
    $password = Get-PlainTextPassword $Config.EncryptedPassword

    $loginUrl = "http://{0}:801/eportal/?c=Portal&a=login" -f $context.PortalHost
    $data = @{
        login_method = $context.LoginMethod
        user_account = $account
        user_password = $password
        wlan_user_ip = $context.WlanUserIp
        wlan_user_ipv6 = $context.WlanUserIpv6
        wlan_user_mac = $context.WlanUserMac
        wlan_ac_ip = $context.WlanAcIp
        wlan_ac_name = $context.WlanAcName
        jsVersion = $context.JsVersion
    }

    Write-Log "正在登录账号 $account，接口=$loginUrl，IP=$($context.WlanUserIp)，MAC=$($context.WlanUserMac)，AC=$($context.WlanAcIp)"
    $result = Invoke-JsonpRequest -Url $loginUrl -Data $data -TimeoutSec 15
    $resultText = $result | ConvertTo-Json -Compress
    Write-Log "认证接口返回：$resultText"

    $loginSucceeded = $result.result -eq 1 -or $result.result -eq "ok"
    $retCode = $null
    if ($null -ne $result.ret_code) {
        try {
            $retCode = [int]$result.ret_code
        }
        catch {
            $retCode = $null
        }
    }

    if (-not $loginSucceeded -and $retCode -eq 2) {
        $loginSucceeded = $true
    }

    if ($loginSucceeded) {
        if ($retCode -eq 2) {
            Write-Log "该 IP 已在线（ret_code=2），按已在线处理。"
        }
        else {
            Write-Log "登录成功。"
        }
        return $true
    }

    $message = Get-PortalErrorMessage $result
    Write-Log "登录未通过：$message" "WARN"
    return $false
}

function Invoke-LoginWithRetry {
    param(
        [object]$Config,
        [int]$Attempts,
        [int]$RetrySeconds
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Write-Log "第 $attempt/$Attempts 次尝试"
            if (Invoke-CampusLogin $Config) {
                return $true
            }
        }
        catch {
            Write-Log $_.Exception.Message "ERROR"
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $RetrySeconds
        }
    }

    return $false
}

if (-not (Test-Path $ConfigPath)) {
    throw "缺少配置文件：$ConfigPath。请先运行 setup-campus-login.ps1。"
}

$config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($ValidateOnly) {
    Write-Log "配置读取成功。账号=$($config.Username)，后缀=$($config.AccountSuffix)，认证页=$($config.PortalPageUrl)"
    [void](Get-PlainTextPassword $config.EncryptedPassword)
    Write-Log "当前 Windows 用户可以解密已保存的密码。"
    exit 0
}

$attempts = if ($Once) { 1 } elseif ($config.MaxAttempts) { [int]$config.MaxAttempts } else { 6 }
$retrySeconds = if ($config.RetrySeconds) { [int]$config.RetrySeconds } else { 15 }
$watchdogIntervalMinutes = if ($config.WatchdogIntervalMinutes) { [int]$config.WatchdogIntervalMinutes } else { 5 }
$campusProbeAttempts = if ($config.CampusProbeAttempts) { [int]$config.CampusProbeAttempts } else { 6 }
$campusProbeRetrySeconds = if ($config.CampusProbeRetrySeconds) { [int]$config.CampusProbeRetrySeconds } else { 10 }

if ($Watchdog) {
    $onCampus = $false
    for ($probe = 1; $probe -le $campusProbeAttempts; $probe++) {
        Write-Log "校园网探测 $probe/$campusProbeAttempts：$($config.PortalPageUrl)"
        if (Test-PortalReachable $config) {
            $onCampus = $true
            Write-Log "检测到校园网，开始自动登录。"
            break
        }
        if ($probe -lt $campusProbeAttempts) {
            Write-Log "暂未检测到校园网，${campusProbeRetrySeconds} 秒后重试。" "WARN"
            Start-Sleep -Seconds $campusProbeRetrySeconds
        }
    }

    if (-not $onCampus) {
        Write-Log "未检测到校园网，自动退出。" "WARN"
        exit 0
    }

    $loginResult = Invoke-LoginWithRetry $config $attempts $retrySeconds
    if ($loginResult) {
        if (-not $NoClose) {
            Write-Log "登录成功/已联网，即将自动关闭窗口。"
            Start-Sleep -Milliseconds 800
            [Environment]::Exit(0)
        }
        exit 0
    }

    Write-Log "自动登录未完成，保留窗口方便查看日志。" "WARN"
    exit 1
}

if (Invoke-LoginWithRetry $config $attempts $retrySeconds) {
    if (-not $NoClose) {
        Write-Log "登录成功/已联网，即将自动关闭窗口。"
        Start-Sleep -Milliseconds 800
        [Environment]::Exit(0)
    }
    exit 0
}

exit 1

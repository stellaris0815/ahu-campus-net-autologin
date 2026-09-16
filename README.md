# 安徽大学校园网自动登录

适用于安徽大学校园网的 Dr.COM / 哆点认证页面自动登录脚本，纯 PowerShell 实现，支持开机自启、定时自动重连、校园网范围检测、登录后自动退出。

> 本项目主要针对安徽大学校园网环境开发，原理也适用于同类 Dr.COM / 哆点认证页面。请只用于你自己的校园网账号，并遵守学校网络使用规定。

## 功能特性

- 自动读取认证页实时 IP，不依赖经常变化的 `wlanuserip=...` 旧链接
- 账号密码使用 Windows DPAPI 加密保存
- 支持开机自启（任务计划程序优先，失败自动改用启动文件夹）
- 定时自动重连：由任务计划程序每 5 分钟运行一次，登录成功后自动退出，不常驻后台
- 校园网范围探测：不在校园网时自动退出，避免后台空转
- 日志自动轮转，避免日志无限膨胀
- 登录成功后自动关闭终端窗口，不需要手动关闭

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `campus-login.ps1` | 执行自动登录 |
| `setup-campus-login.ps1` | 首次配置账号、密码，生成加密配置 |
| `install-autostart.ps1` | 安装开机自启 |
| `uninstall-autostart.ps1` | 移除开机自启 |
| `campus-login.config.example.json` | 配置示例，不包含真实账号密码 |
| `logs/` | 运行日志目录（不会上传到 Git） |

## 环境要求

- Windows 10 / 11
- PowerShell 5.1 或更高版本（Windows 自带的 Windows PowerShell 即可）
- 校园网 Dr.COM / 哆点认证页面

## 快速开始

在项目目录打开 PowerShell：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\setup-campus-login.ps1
.\campus-login.ps1 -Once
.\install-autostart.ps1
```

> 默认安装会创建 Windows 任务计划程序，每隔几分钟自动运行一次登录脚本，登录成功后自动退出，实现“不常驻后台 + 掉线自动重连”。
> 如果任务计划程序创建失败，会降级为启动文件夹里的开机登录一次；需要管理员权限运行 `install-autostart.ps1` 才能启用定时自动重连。

### 配置账号后缀

如果账号已经带 `@`（例如 `学号@cmccwx`），配置时账号填写完整账号，后缀留空。
否则在配置脚本中手动输入你实际使用的后缀，不同运营商/有线和无线可能不同。

## 常用参数

```powershell
# 只尝试一次，成功后自动关闭窗口
.\campus-login.ps1 -Once

# 只尝试一次，但成功后不关闭窗口（调试用）
.\campus-login.ps1 -Once -NoClose

# 只验证配置和密码能否解密，不登录
.\campus-login.ps1 -ValidateOnly

# 自动登录一次：先探测校园网，登录成功后自动退出（配合任务计划程序可实现定时重连）
.\campus-login.ps1 -Watchdog

# 安装一次性自启动（不常驻）
.\install-autostart.ps1 -OneShot
```

## 隐私与安全

- 请勿上传 `campus-login.config.json` 和 `logs/` 目录，它们包含真实账号、加密密码和运行日志。
- 配置文件只能由当前 Windows 用户解密；换电脑或换 Windows 用户后需要重新运行 `setup-campus-login.ps1`。

## License

[MIT](LICENSE)

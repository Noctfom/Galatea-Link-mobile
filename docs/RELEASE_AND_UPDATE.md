# 发布与更新

## 固定应用身份

Android `applicationId` 与 `namespace` 统一为：

```text
com.noctfom.galatealink
```

该标识从首次公开发布开始不应再改变。`mobile` 已经体现在产品名和仓库名中，无需重复加入应用标识。正式签名密钥同样必须长期保管，丢失或更换会影响已安装用户升级

从旧测试包 `com.example.galatea_link_mobile` 迁移时，Android 会把新包识别为另一应用。首次公开发布前应卸载旧测试包，并重新导入需要保留的本地资产和设置

## 首次创建正式签名

密钥只需要创建一次，但以后每一个 GitHub、下载页或商店版本都必须使用同一正式密钥签名。创建密码、保存密钥与离线备份必须由项目所有者本人完成，协作者只需要验证最终 APK 的公开证书指纹

在 PowerShell 中运行：

```powershell
Set-Location E:\flutter_app\galatea_link_mobile
.\scripts\create_release_keystore.ps1 `
  -KeystorePath '你选定的仓库外安全目录\galatea-link-mobile-release.jks' `
  -KeytoolPath 'E:\Android Studio\jbr\bin\keytool.exe'
```

脚本不会把密码放进命令行或日志，随后由 `keytool` 直接交互询问。证书有效期已设置为约二十七年，正式发布前应确认满足预期的应用生命周期

创建后将 `android/key.properties.example` 复制为 `android/key.properties`，只在本机填写密码、别名和 JKS 绝对路径。该文件与 JKS 已被 `.gitignore` 排除

备份至少应包含：

- 原始 JKS 文件
- JKS 密码、Key 密码和 Alias
- JKS 文件 SHA-256 与签名证书 SHA-256
- 一份断网介质备份和一份不同地点的加密备份

完成备份后应实际复制回一台测试环境，运行一次签名构建确认备份可用。不要只验证压缩包可以打开，也不要把密码和未加密 JKS 放在同一云盘目录

## 版本规则

`pubspec.yaml` 使用 `主版本.次版本.修订号+内部版本号`：

```text
version: 0.2.2+6
```

- `versionName` 用于用户阅读和 Git 标签
- `versionCode` 必须在每次发布时严格递增，更新判断以它为准
- 稳定版 Git 标签建议使用 `v0.2.2`
- APK 文件名建议使用 `Galatea-Link-mobile-v0.2.2-universal.apk`

## 稳定版更新清单

应用仅在用户点击“检查稳定版更新”时请求：

```text
https://galatea.noctfom.top/mobile/update.json
```

清单格式：

```json
{
  "schema_version": 1,
  "channel": "stable",
  "version_name": "0.2.2",
  "version_code": 6,
  "minimum_supported_version_code": 1,
  "download_url": "https://github.com/Noctfom/Galatea-Link-mobile/releases/download/v0.2.2/Galatea-Link-mobile-v0.2.2-universal.apk",
  "release_page_url": "https://github.com/Noctfom/Galatea-Link-mobile/releases/tag/v0.2.2",
  "sha256": "填写 APK 的六十四位 SHA-256 小写或大写十六进制值",
  "release_notes": "本次稳定版的简短说明",
  "published_at": "2026-09-14T00:00:00Z"
}
```

`download_url` 和 `release_page_url` 必须是 HTTPS，应用限制清单最大为 256 KiB。当前实现只展示结果并由系统浏览器打开发布页，不申请安装未知应用权限，也不会静默下载或安装 APK

更新清单暂时不可用时，设置页会明确显示更新服务尚未发布或网络错误，不影响游戏、模型和 LLM 功能

## 发布步骤

1. 更新 `pubspec.yaml` 版本和发布说明
2. 运行 `flutter pub get`、`flutter analyze` 和 `flutter test`
3. 使用固定正式密钥运行 `flutter build apk --release`
4. 计算 APK 的 SHA-256 并记录产物大小
5. 创建对应 GitHub Release，上传重新命名后的 APK、SHA-256 文件和源码归档
6. APK 上传完成后再原子更新子域名上的 `mobile/update.json`
7. 在至少一台干净设备和一台覆盖升级设备上验证下载、签名、安装、资产保留和对局流程

GitHub Release 上传 APK 后，可以使用仓库工具生成清单：

```powershell
.\scripts\generate_update_manifest.ps1 `
  -ApkPath '.\build\release\Galatea-Link-mobile-v0.2.2-universal.apk' `
  -VersionName '0.2.2' `
  -VersionCode 6 `
  -DownloadUrl 'https://github.com/Noctfom/Galatea-Link-mobile/releases/download/v0.2.2/Galatea-Link-mobile-v0.2.2-universal.apk' `
  -ReleasePageUrl 'https://github.com/Noctfom/Galatea-Link-mobile/releases/tag/v0.2.2' `
  -ReleaseNotes '修正本机 YGOMobile 自动等待和连接状态提示，增加详细卡组拒绝反馈与 Core 决策诊断' `
  -OutputPath '.\build\release\update.json'
```

生成的 `update.json` 不包含密钥，可以交给静态网站、对象存储或普通 HTTPS 服务器发布

Windows 可以使用：

```powershell
Get-FileHash .\build\release\Galatea-Link-mobile-v0.2.2-universal.apk -Algorithm SHA256
```

建议为 `update.json` 设置较短缓存时间或在替换时执行 CDN 清理，避免旧清单长时间指向已撤回版本。若需要撤回问题版本，应先恢复到上一稳定清单，再处理 GitHub Release

## 商店与下载页资料

首次公开发布前还需要准备：

- 产品简介、版本说明、应用图标和至少两张真实界面截图
- 公开隐私政策 URL，内容以 `docs/PRIVACY.md` 为基线
- GPL-3.0-only 源码与许可证入口
- 支持邮箱或 GitHub Issue 地址
- 非官方项目与游戏素材权属声明

APK、GKG、ONNX、`cards.cdb`、卡组文件、房间密码和 API Key 不应提交进 Git 仓库

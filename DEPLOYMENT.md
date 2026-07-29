# Sub2Watch 实机部署记录

本文记录 Sub2Watch 在实体 iPhone/Apple Watch 上已经验证过的部署环境、当前手机同步架构和 Xcode 安装注意事项。修改 Scheme、签名或 WatchConnectivity 配置前，请先核对本文。

## 当前架构

Sub2Watch 由 iPhone 统一访问 Sub2API：

1. iPhone 保存服务地址和登录凭据，并通过 `URLSession.shared` 请求 Sub2API。
2. iPhone 将不含服务器地址、密码、管理员密钥及登录 token 的 `DeviceSyncSnapshot` 写入 WatchConnectivity application context。
3. Watch 收到快照后更新看板、本地缓存、小组件和额度重置判断。
4. Watch 手动刷新时向 iPhone 发送刷新命令；iPhone 完成请求后发布新快照。

## 已验证环境

最后核对日期：2026-07-29。

- macOS 26.5（25F71）
- Xcode 27.0（27A5228h），路径为 `/Applications/Xcode-beta.app`
- iOS 27 开发者版本
- watchOS 27.0（24R5305g）
- 实体设备型号：Watch7,18
- Watch App Bundle ID：`com.yinian.Sub2Watch.watchkitapp`
- Widget Bundle ID：`com.yinian.Sub2Watch.watchkitapp.widgets`
- App Group：`group.com.yinian.Sub2Watch`

机器上的 `xcode-select` 可能仍指向 `/Applications/Xcode.app` 的 Xcode 26。命令行构建 watchOS 27 时必须显式指定 Xcode 27：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Sub2Watch.xcodeproj \
  -scheme "Sub2Watch Watch App" \
  -configuration Debug \
  -destination "generic/platform=watchOS" \
  -derivedDataPath /tmp/Sub2WatchXcode27DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## 日常部署方式

- 在 Xcode 中选择 `Sub2Watch` Scheme 和已连接的 iPhone。
- 为 iPhone App、Watch App 和 Widget Extension 三个 Target 选择同一个 Personal Team。
- Run 后先在 iPhone 完成登录。Watch App 已嵌入 iOS App；没有自动安装时，在 iPhone 的 Watch App 中手动安装。
- iPhone 登录并刷新后，Watch 设置页应显示“由 iPhone 管理”和最近同步时间。

## Watch 单独部署方式

- 实体表构建使用共享 Scheme `Sub2Watch Watch App`。
- Watch App 的 Debug 配置设置 `ENABLE_DEBUG_DYLIB = NO`。
- 首选 `Scripts/install-watch-without-debug.sh` 构建并通过 `devicectl` 只安装 App。脚本不会启动 App，也不会建立 Xcode Run 会话。
- Xcode 27 会在打开项目时自动向 Watch Scheme 写入 `debugServiceExtension="internal"`。不要把删除该字段当作稳定修复；绕开 Xcode Run 会话才是可重复的部署方式。
- 如需用 Xcode Run 安装，安装完成后必须停止运行会话，再从 Watch 桌面直接启动 App。
- 不要在 Xcode 的 Devices and Simulators 中 Unpair Watch。该操作可能导致 Watch 无法重新被 Xcode 发现。

### 仅安装、不调试

安装时 Watch 必须在 `devicectl list devices` 中显示为 `connected`。如果它显示为 `unavailable`，先打开 iPhone 和 Watch 的蓝牙与 Wi-Fi，让 Xcode/CoreDevice 建立安装隧道。此连接只用于安装，不代表 App 的网络请求会经过 Mac。

退出 Xcode 后，在项目目录运行：

```bash
./Scripts/install-watch-without-debug.sh "你的 Apple Watch 名称或 CoreDevice UUID"
```

设备名称或 UUID 可通过 `xcrun devicectl list devices` 查询，并作为脚本的第一个参数传入。脚本完成后，从 Watch 桌面手动打开 Sub2Watch；不要再在 Xcode 中点击 Run。

## 已确认的 Xcode 回归

实体 Watch 还会间歇出现以下 Xcode 设备通道错误：

- `CoreDeviceError 4000`
- `RemotePairingError 1001`
- `Timed out while attempting to establish tunnel using negotiated network parameters`

Apple Developer Forums 已有相同报告，Apple 工程师判断为系统 Bug：

- [Connection problems between Xcode and Apple Watch](https://developer.apple.com/forums/thread/831768)
- [Apple watch Xcode pairing & connection issues](https://developer.apple.com/forums/thread/813066)
- Feedback：`FB19367415`

## 部署保护

- 不依赖手工删除 `debugServiceExtension="internal"`；Xcode 27 会在打开项目时自动写回。
- Xcode Run 无法稳定连接实体表时，使用只安装脚本规避调试运行通道。
- Watch App、Widget Extension 和 iPhone App 必须使用同一个 Team，并保持匹配的 Bundle ID 与 App Group。
- Watch 端不得保存或接收服务器地址、密码、管理员密钥及登录 token。

## 验证清单

每次部署相关修改后至少完成：

```bash
swift test
```

并使用上面的 Xcode 27 命令完成 watchOS 27 SDK 构建。实体设备还需确认：

- iPhone 能登录 Sub2API 并完成刷新。
- iPhone 页面显示 WatchConnectivity 状态及最近同步时间。
- Watch 能收到最新快照，看板、总额度、账号页和小组件均能读取数据。
- Watch 手动刷新能触发 iPhone 请求，并在完成后收到新快照。

# Sub2Watch 实机部署记录

本文记录 Sub2Watch 在实体 Apple Watch 上已经验证过的部署环境、已知系统问题和回归保护。修改 Xcode Scheme、网络会话或签名配置前，请先核对本文。

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

## 当前部署方式

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

## watchOS 27 实机网络问题

模拟器可以正常登录并访问真实 Sub2API。实体 Watch 曾稳定复现以下状态：

- `NWPath.status == .unsatisfied`
- 路径显示为“其他”，没有可用的 Wi-Fi/蜂窝接口
- Sub2API、Apple 连通性地址和 Cloudflare `1.1.1.1` 同时失败
- 使用系统默认会话时返回 `NSURLErrorDomain -1004`
- 使用 `waitsForConnectivity` 时最终返回 `NSURLErrorDomain -1001`
- 管理员密钥和邮箱密码登录均失败，因此问题与鉴权方式无关
- 早期测试中关闭蓝牙、让 Watch 使用自身 Wi-Fi 曾恢复请求；后续在 Xcode 运行会话中关闭蓝牙仍出现 `-1004`，因此蓝牙开关不是稳定修复

该现象说明 watchOS 27 Beta 的配对中继、CoreDevice 调试通道或当前 App 进程的网络路径存在异常。其他 Watch 应用可以联网也不能排除该问题，因为不同进程可能使用不同的现有连接与路由。应用没有公开 API 可以让 `URLSession` 禁用蓝牙中继或强制使用 Wi-Fi。

当前可靠的实机测试流程：

1. 确认 Watch 已直接加入可访问 Sub2API 的 Wi-Fi。
2. 使用上面的脚本只安装 App，或在安装完成后停止 Xcode 运行会话。
3. 保持 Watch 的 Wi-Fi 开启。需要验证直连时，关闭蓝牙并等待 Watch 显示 Wi-Fi 已连接；不要关闭 Wi-Fi。
4. 从 Watch 桌面重新启动 Sub2Watch。
5. 先观察 Apple 和 Cloudflare 诊断；两者也失败时，记录 App 显示的 `NWPath`，不要修改 Sub2API 域名、密钥或登录代码。

## 已确认的 Xcode 回归

实体 Watch 还会间歇出现以下 Xcode 设备通道错误：

- `CoreDeviceError 4000`
- `RemotePairingError 1001`
- `Timed out while attempting to establish tunnel using negotiated network parameters`

Apple Developer Forums 已有相同报告，Apple 工程师判断为系统 Bug：

- [Connection problems between Xcode and Apple Watch](https://developer.apple.com/forums/thread/831768)
- [Apple watch Xcode pairing & connection issues](https://developer.apple.com/forums/thread/813066)
- Feedback：`FB19367415`

## 回归保护

在 watchOS 27 Beta 问题得到确认修复前：

- API 请求保持使用 `URLSession.shared`。
- 不要改成长时间持有的 `URLSessionConfiguration.ephemeral` 会话。
- 不要为主请求启用 `waitsForConnectivity`；它只会把立即可见的 `-1004` 变成较晚出现的 `-1001`。
- 不依赖手工删除 `debugServiceExtension="internal"`；Xcode 27 会在打开项目时自动写回。使用只安装脚本规避该运行通道。
- 不要因为 Sub2API、Apple 和 Cloudflare 同时失败而修改 Cloudflare、TLS、IPv6 或管理员密钥配置。
- 如需强制 Wi-Fi，只能另行使用底层 Network.framework 的 Wi-Fi-only 连接；它不能直接替代 `URLSession`，不应在没有完整 HTTPS/HTTP 实现和实机验证的情况下接入生产请求。

## 验证清单

每次部署相关修改后至少完成：

```bash
swift test
```

并使用上面的 Xcode 27 命令完成 watchOS 27 SDK 构建。实体表验证时分别记录：

- 蓝牙开启时的 `NWPath` 和 Apple/Cloudflare 结果
- 蓝牙关闭、Watch 直连 Wi-Fi 时的结果
- App 是由 Xcode 正在运行，还是通过脚本安装并从 Watch 桌面启动

诊断输出中的 `Wi-Fi / TCP` 使用 Network.framework 强制 Wi-Fi 连接 `1.1.1.1:443`，不经过 `URLSession`。如果该 TCP 探针可用而 Apple/Cloudflare 的 URLSession 探针失败，可以继续评估 Wi-Fi-only 传输兜底；如果 TCP 探针也失败，则当前 App 进程没有可用的底层 Wi-Fi socket 路径，应用层无法修复。

2026-07-29 的无调试实机验证结果：

- 通过 `devicectl` 只安装，不由 Xcode 启动
- Xcode 已退出，Watch 蓝牙关闭，Wi-Fi 保持开启
- 默认路径：`不可用 · Wi-Fi · IPv4`
- 强制 Wi-Fi TCP：`waiting(POSIXErrorCode 50: Network is down)`
- Apple 与 Cloudflare URLSession 探针均为 `-1004`
- 强制重启 Watch 后，在不修改 App、服务器、域名、鉴权或 Cloudflare 配置的情况下，真实数据请求立即恢复

以上结果证明本次故障是 watchOS 的瞬时网络路径状态异常，而不是 App 请求、Sub2API、密钥或 Cloudflare 问题。系统仍能识别 Wi-Fi/IPv4 接口，但当前 App 的默认路径为 `unsatisfied`，URLSession 和底层连接都无法建立；重启会重新启动系统网络服务并重建 Wi-Fi、蓝牙中继和 CoreDevice 相关路径。具体由哪个系统守护进程或切换事件触发，仍需 sysdiagnose 才能确认。

疑似触发条件包括 Xcode/CoreDevice 实体部署、调试隧道异常，以及蓝牙中继与直接 Wi-Fi 之间反复切换。出现相同特征时按以下顺序处理：

1. 确认 Apple、Cloudflare 和 Sub2API 是否同时失败。
2. 如果同时为 `-1004`，且 `NWPath` 为 `不可用`，不要修改服务器或鉴权。
3. 强制重启 Watch，并从 Watch 桌面直接启动 App。
4. 仍未恢复时，忘记并重新加入 Wi-Fi。
5. 升级后续 watchOS 27/Xcode 27 Beta；持续复现时提交 Feedback，并附带复现后的 sysdiagnose。

公开的相似报告：

- [apple/swift-nio #2255](https://github.com/apple/swift-nio/issues/2255)：watchOS Beta 模拟器正常、实体 Watch 网络连接失败。
- [firebase-ios-sdk #15053](https://github.com/firebase/firebase-ios-sdk/issues/15053)：实体 Apple Watch 出现 `POSIXErrorCode 50`，模拟器正常。
- [Apple Developer Forums #831768](https://developer.apple.com/forums/thread/831768)：Xcode 与 Apple Watch 的连接/隧道异常。
- [Apple Developer Forums #813066](https://developer.apple.com/forums/thread/813066)：Apple Watch 配对及 CoreDevice 连接问题。

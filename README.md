# Sub2Watch

一个自用的 watchOS 额度监控应用。Apple Watch 直接请求 Sub2API，不经过 iPhone 转发，也不包含账号、额度或密钥的写入操作。

## 当前功能

- 使用管理员密钥读取全部 Sub2API 账号，并按平台分组
- 展示 Codex、Claude、Gemini、Antigravity 和 Grok 各自的额度窗口、重置时间及账号状态
- 在总额度页按平台分别汇总平均剩余、数据覆盖数、请求数、Token 和费用，不混算不同平台的额度窗口
- 在每个账号下展示该平台实际提供的额度窗口；不支持额度查询的账号类型仍会显示并明确标记
- 主界面采用横向三页：左侧为用量看板，中间默认显示总额度，右侧为可纵向滚动的单账号额度列表
- 展示全站今日/累计请求数、输入/输出/缓存 Token、费用、RPM、TPM 和平均响应时间
- 在 Sub2API Ops Monitoring 可用时展示近 24 小时 OpenAI 模型请求、输出 Token、生成速度和首 Token 延迟
- 支持账号列表刷新和单账号实时额度刷新
- 管理员密钥保存在 Apple Watch Keychain（仅本设备、解锁后可用）
- 账号与额度快照保存在本地缓存，离线时仍可查看并标记过期状态
- 默认只允许 HTTPS；可在明确确认风险后使用 HTTP

## 要求

- Xcode 16 或更高版本
- iPhone 运行 iOS 17 或更高版本
- Apple Watch 运行 watchOS 10 或更高版本
- 一个可从 Apple Watch 当前网络访问的 Sub2API 地址
- Sub2API 管理员密钥

建议给 Sub2API 配置可信 HTTPS 证书。允许 HTTP 只解决明文连接限制，不会让自签名或无效的 HTTPS 证书变得可信。管理员密钥权限很高，不要在不可信 Wi-Fi 上通过 HTTP 使用。

## 个人真机安装

1. 用 Xcode 打开 `Sub2Watch.xcodeproj`。
2. 在 `Sub2Watch` 和 `Sub2Watch Watch App` 两个 Target 的 **Signing & Capabilities** 中选择自己的 Personal Team。
3. 如果默认 Bundle ID 已被占用，将 `com.yinian.Sub2Watch` 改为自己的唯一 ID，并将 Watch App 的 ID 保持为它的子级，例如 `你的ID.watchkitapp`。
4. 在 iPhone 和 Apple Watch 上启用开发者模式，并确保手表已与该 iPhone 配对。
5. 常规系统可以选择 `Sub2Watch Watch App` Scheme 和配对的 Apple Watch 后点击 Run。watchOS/Xcode 27 Beta 建议改用 `DEPLOYMENT.md` 中的“仅安装、不调试”脚本。
6. 第一次启动时，在手表输入 Sub2API 地址和管理员密钥，点击“连接并保存”。地址既可以是服务根地址，也可以以 `/api/v1` 结尾。

使用免费 Personal Team 安装的应用通常需要定期重新签名。个人自用不需要 App Store Connect 或 TestFlight。

实体 Watch 的已验证环境、Xcode 27 部署方式和当前 watchOS 27 网络问题见
[`DEPLOYMENT.md`](DEPLOYMENT.md)。重新安装或修改网络层前请先阅读该文档。

## 网络说明

- 公网部署：使用 Apple Watch 能解析并访问的域名，推荐 HTTPS。
- 局域网部署：手表必须能直接访问对应 IP 和端口；仅 iPhone 能访问并不代表手表一定可达。
- 蜂窝网络：私网地址通常不可达，需要 VPN、隧道或公开入口。
- 应用调用以下只读接口，并通过 `x-api-key` 请求头鉴权：
  - `GET /api/v1/admin/accounts`
  - `GET /api/v1/admin/accounts/:id/usage`
  - `GET /api/v1/admin/openai/accounts/:id/quota`
  - `GET /api/v1/admin/usage`
  - `GET /api/v1/admin/usage/stats`
  - `GET /api/v1/admin/dashboard/stats`
  - `GET /api/v1/admin/ops/dashboard/openai-token-stats`

首页刷新会以最多 2 个账号并发刷新额度。Codex 保留专用额度接口以及本地 5h/服务端 7d 用量统计；其他平台使用 Sub2API 通用账号 usage 接口，保留 Claude、Gemini、Antigravity 和 Grok 各自的窗口定义。每个平台、每种窗口独立计算平均剩余和数据覆盖数，不会跨平台混算。用量页的今日与累计数据是全站口径，可能包含非 OpenAI 请求；模型统计才是 OpenAI 口径，且需要 Sub2API 开启 Ops Monitoring。

## 本地验证

Debug 构建支持以下启动环境变量：

- `SUB2WATCH_BASE_URL`：预填 Sub2API 地址
- `SUB2WATCH_ADMIN_KEY`：预填管理员密钥，不写入普通偏好设置
- `SUB2WATCH_DEMO=1`：跳过配置页并加载模拟额度数据
- `SUB2WATCH_PAGE=0|1|2`：Debug 下直接打开看板、总额度或账号额度页，默认值为 `1`

配置页的“开发 > 查看模拟数据”也可以进入模拟模式。这些入口仅存在于 Debug 构建。

运行核心逻辑测试：

```bash
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/sub2watch-swift-cache \
CLANG_MODULE_CACHE_PATH=/tmp/sub2watch-clang-cache \
swift test --disable-sandbox --scratch-path /tmp/sub2watch-build
```

运行无签名 watchOS 真机目标构建：

```bash
xcodebuild -project Sub2Watch.xcodeproj \
  -scheme "Sub2Watch Watch App" \
  -configuration Debug \
  -destination "generic/platform=watchOS" \
  -derivedDataPath /tmp/Sub2WatchDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

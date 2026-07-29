# Packaging（Developer ID / Notarization）

macOS 分发**不使用 Velopack**。推荐流程：

## 1. Archive

Xcode → Product → Archive，或：

```bash
xcodebuild -scheme Athlon-work -configuration Release \
  -archivePath build/Athlon-work.xcarchive archive
```

## 2. Export Developer ID app

使用 ExportOptions.plist（`method: developer-id`），导出 `.app`。

## 3. Notarize

```bash
# 打包 zip
ditto -c -k --keepParent Athlon-work.app Athlon-work.zip

xcrun notarytool submit Athlon-work.zip \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait

xcrun stapler staple Athlon-work.app
```

## 4. 分发

- 直接分发 stapled `.app` / `.dmg` / `.zip`
- 可选：Sparkle 等开源更新通道（非 Velopack）

## 注意

- Hardened Runtime + 所需 entitlements（网络、Keychain、用户选中的文件）
- 无 License / SSO 门，安装后即可运行（仍需用户配置 Model API Key）

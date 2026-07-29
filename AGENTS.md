# Sub2Watch workspace instructions

Before changing networking, authentication transport, Xcode schemes, signing, or physical Apple Watch deployment, read `DEPLOYMENT.md` completely.

Until the watchOS 27 physical-device regression documented there is confirmed fixed:

- Keep API traffic on `URLSession.shared`; do not introduce a persistent ephemeral session or `waitsForConnectivity` for primary requests.
- Prefer `Scripts/install-watch-without-debug.sh` for physical deployment. Xcode 27 rewrites `debugServiceExtension="internal"`, so removing that XML attribute is not a durable fix.
- Treat simultaneous Sub2API, Apple, and Cloudflare failures as a Watch network-path failure, not an authentication or server configuration failure.
- Verify deployment changes with the Xcode 27 command in `DEPLOYMENT.md` and run `swift test`.

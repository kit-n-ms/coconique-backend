# KM Auth Starter Docs Index

KM Auth Starter 共通基盤のドキュメント索引です。

## 最初に読む

- [共通基盤仕様書](./common-platform-spec.md)
- [Handoff Guide](./handoff-guide.md)
- [Product Fork Checklist](./product-fork-checklist.md)

## 本番化・運用前

- [Final Smoke Test](./final-smoke-test.md)
- [Security Final Checklist](./security-final-checklist.md)
- [Common Platform Release Notes v1](./common-platform-release-notes-v1.md)

## 既存の関連docs

既に作成済みの場合、以下も併せて参照する。

- `docs/env.md`
- `docs/deploy-checklist.md`
- `docs/mail-provider.md`
- `docs/resend_mail_webhook_guide.md`
- `docs/admin-api.md`
- `docs/product-fork-guide.md`
- `docs/stage15-production-readiness.md`

## この基盤の目的

この基盤は、Hodokoo / Coconique などの複数プロダクトに複製して使うための、認証・課金・メール・Webhook・管理API・運用チェックの共通スターターである。

プロダクト固有の事業ロジック、本人確認、契約書チェック、マッチング機能、非弁法対応UIなどは、派生先で追加する。

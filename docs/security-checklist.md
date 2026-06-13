# Security Checklist

## Cookie / Session

- [ ] HttpOnly cookie を使っている
- [ ] 本番では Secure cookie を有効化している
- [ ] SameSite を適切に設定している
- [ ] session cookie名をサービスごとに分離している
- [ ] auth_sessions に expires_at がある
- [ ] logout時に auth_sessions.revoked_at を更新している
- [ ] 期限切れsessionをcleanupする

## CSRF

- [ ] unsafe method に X-CSRF-Token を要求している
- [ ] CSRF cookie名をサービスごとに分離している
- [ ] フロント側で credentials: include を使っている
- [ ] CSRFエラー時に詳細な内部情報を出していない

## CORS

- [ ] 本番では許可originを限定している
- [ ] wildcard origin を使っていない
- [ ] credentialsを使う場合、originを明示している

## Password

- [ ] has_secure_password を使っている
- [ ] password_digest 以外に平文を保存していない
- [ ] 12文字以上を要求している
- [ ] password reset token はdigest保存
- [ ] password reset token に期限がある

## Email Verification

- [ ] tokenはdigest保存
- [ ] tokenに期限がある
- [ ] used_at を記録している
- [ ] メール認証前に機微な個人情報を入力させすぎない

## Stripe

- [ ] STRIPE_SECRET_KEY をフロントに出していない
- [ ] webhook signing secret を検証している
- [ ] checkout.session.completed で残高反映している
- [ ] success_url 到達だけで残高反映していない
- [ ] webhook event id で冪等性を担保している
- [ ] completed済みPaymentCheckoutSessionを二重処理しない
- [ ] Stripe account / API key / webhook secret をサービスごとに分離している

## Logging

- [ ] passwordをログ出力しない
- [ ] tokenをログ出力しない
- [ ] secret keyをログ出力しない
- [ ] Stripe secretをログ出力しない
- [ ] 本番でdebug exceptionを返さない

## Admin

- [ ] 管理APIはadmin roleのみ
- [ ] 管理者アカウントはサービスごとに分離
- [ ] 管理操作はaudit_logsに記録



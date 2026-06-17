# Environment Variables

Coconique は Hodokoo 等とは完全に別サービスとして運用する前提です。DB、cookie名、CSRF cookie名、secret、Stripe、Resend、本人確認Provider、ActiveStorage bucket は必ず分離してください。

## App identity / Legal versions

| Key | Example | Notes |
|---|---|---|
| `APP_NAME` | `coconique_api` | `/up` 等に表示する内部名 |
| `CURRENT_APP_KEY` | `coconique` | 課金・Seed・アプリ識別に使う。Coconiqueでは `coconique` 固定 |
| `CURRENT_TERMS_VERSION` | `2026-06-14` | 利用規約バージョン |
| `CURRENT_PRIVACY_VERSION` | `2026-06-14` | プライバシーポリシーバージョン |

## Frontend / CORS

| Key | Example | Notes |
|---|---|---|
| `FRONTEND_ORIGIN` | `http://localhost:5173` | フロントURL |
| `FRONTEND_APP_URL` | `http://localhost:5173` | fake checkout等の戻り先生成に使用 |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:5173,http://127.0.0.1:5173` | 複数指定はカンマ区切り |
| `FRONTEND_EMAIL_VERIFICATION_URL` | `http://localhost:5173/auth/email-verifications/confirm` | メール認証URL |
| `FRONTEND_PASSWORD_RESET_URL` | `http://localhost:5173/auth/password-resets/confirm` | パスワード再設定URL |
| `FRONTEND_EMERGENCY_CONTACT_APPROVAL_URL` | `http://localhost:5173/emergency-contacts/approve` | 緊急連絡先承認URL |
| `COCONIQUE_IDENTITY_RETURN_URL` | `http://localhost:5173/app/safety/registration` | 本人確認Providerから戻るURL |
| `REQUIRE_ORIGIN_FOR_UNSAFE_REQUESTS` | `true` | 本番では `true` 推奨 |
| `NGROK_HOST` | `xxxx.ngrok-free.dev` | ローカルWebhook確認用 |

## Cookie / Session

| Key | Example | Notes |
|---|---|---|
| `AUTH_COOKIE_NAME` | `coconique_session` | Coconique専用。Hodokoo等と絶対に共有しない |
| `CSRF_COOKIE_NAME` | `coconique_csrf` | フロント `VITE_CSRF_COOKIE_NAME` と一致させる |
| `AUTH_COOKIE_SECURE` | `true` | 本番では `true` |
| `AUTH_COOKIE_SAME_SITE` | `lax` | API/フロントが完全クロスサイトの場合は要検討 |
| `AUTH_COOKIE_DOMAIN` | `.example.com` | 必要な場合のみ。基本は未設定推奨 |

## Mail

| Key | Example | Notes |
|---|---|---|
| `MAIL_PROVIDER` | `file` / `resend` | ローカルは `file`, 本番は `resend` 推奨 |
| `MAIL_FROM` | `Coconique <no-reply@coconique.com>` | ResendでVerify済みドメインを使う |
| `RESEND_API_KEY` | `re_xxx` | 派生サービスごとに分離 |
| `RESEND_WEBHOOK_SECRET` | `whsec_xxx` | Resend webhook署名検証用 |
| `POSTMARK_API_TOKEN` | `xxx` | Postmark利用時のみ |

期待されるResend設定:

```bash
bin/rails runner 'puts "MAIL_PROVIDER=#{ENV["MAIL_PROVIDER"]}"; puts "delivery_method=#{ActionMailer::Base.delivery_method}"'
```

```txt
MAIL_PROVIDER=resend
delivery_method=resend_custom
```

## Stripe / Billing

| Key | Example | Notes |
|---|---|---|
| `STRIPE_SECRET_KEY` | `sk_test_xxx` | Coconique専用Stripeアカウント/プロジェクトで発行 |
| `STRIPE_WEBHOOK_SECRET` | `whsec_xxx` | `/webhooks/stripe` の署名検証用 |
| `STRIPE_SUCCESS_URL` | `http://localhost:5173/billing/success?session_id={CHECKOUT_SESSION_ID}` | `{CHECKOUT_SESSION_ID}` を残す |
| `STRIPE_CANCEL_URL` | `http://localhost:5173/billing/cancel` | キャンセル時URL |
| `STRIPE_PRICE_FOUNDER_MONTHLY` | `price_xxx` | Founder月額 430円/月 のRecurring Price ID。`founder_beta_monthly` は `mode=subscription` でこのPriceを使う |
| `STRIPE_COUPON_FIRST_MONTH_100` | `coupon_xxx` | 330円OFF / duration once。初回請求を100円にする |
| `STRIPE_PRICE_HOST_TICKET` | `price_xxx` | 追加主催チケット 1,000円 のOne-time Price ID。未設定時はAPI側の `price_data` で作成 |
| `STRIPE_TAX_ENABLED` | `false` | 初期βではOFF。Coconique上の表示価格を総額として扱う |
| `REQUIRE_STRIPE_CONFIG` | `true` | staging/productionで厳密チェックしたい時 |
| `COCONIQUE_USE_FAKE_STRIPE_CHECKOUT` | `true` | 開発用。`false` を明示した場合はdevelopmentでも本物のStripe Checkoutを使う |
| `COCONIQUE_ALLOW_FAKE_CHECKOUT_COMPLETE` | `true` | 開発用。fake checkout完了APIを許可 |
| `COCONIQUE_ALLOW_FAKE_PAYMENT_METHOD` | `true` | 開発用。安全登録内のfakeカード登録を許可 |
| `COCONIQUE_DEVELOPER_COLLABORATOR_CODES` | `開発協力メンバー` | カンマ区切り。FounderプランCheckout時に一致した場合だけ模擬決済へ強制遷移 |
| `CHECKOUT_ALLOWED_HOSTS` | `localhost,127.0.0.1` | checkout完了URLの許可host |

Step 7-2以降、Founder βプランは `mode: subscription` で作成します。初月100円は「430円/月Price + 初回のみ330円OFF Coupon」で実現し、2ヶ月目以降はStripe Subscriptionの自動更新で430円を請求します。追加主催チケットは従来どおり `mode: payment` の都度決済です。月額チケット5枚の付与は `invoice.paid` webhookを正とし、`checkout.session.completed` だけではチケット付与しません。

Stripe webhookで最低限有効化するイベント:

- `checkout.session.completed`
- `checkout.session.expired`
- `invoice.paid`
- `invoice.payment_failed`
- `invoice.payment_action_required`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `identity.verification_session.verified`（Stripe Identity fallback利用時）
- `identity.verification_session.requires_input`
- `identity.verification_session.canceled`

## Coconique SMS / Safety registration

初期βではSMS認証を安全登録の必須条件から外す。Twilio Verify関連設定は、将来のリスクベース追加確認用としてdormant扱いで残す。

| Key | Example | Notes |
|---|---|---|
| `COCONIQUE_SMS_PROVIDER` | `fake_sms` / `twilio_verify` | 初期βでは必須フローでは使わない。将来の追加確認用 |
| `TWILIO_ACCOUNT_SID` | `AC...` | Twilio Account SID。使わない場合は未設定可 |
| `TWILIO_AUTH_TOKEN` | `xxx` | Twilio Auth Token。ログ出力禁止 |
| `TWILIO_VERIFY_SERVICE_SID` | `VA...` | Twilio Verify Service SID |
| `TWILIO_VERIFY_CHANNEL` | `sms` | 将来SMS確認を使う場合のchannel |
| `TWILIO_VERIFY_LOCALE` | `ja` | Verify SMSのロケール |
| `TWILIO_VERIFY_API_BASE_URL` | `https://verify.twilio.com` | 通常は変更不要 |
| `TWILIO_VERIFY_CUSTOM_FRIENDLY_NAME` | `Coconique` | SMS上のサービス名として使う場合に設定 |
| `COCONIQUE_COLLABORATOR_PROMO_CODES` | `COCOBETA,FOUNDER,FRIEND` | 協力者β用コード。実運用では推測困難な値に変更 |

## Coconique re-registration prevention

| Key | Example | Notes |
|---|---|---|
| `COCONIQUE_REENTRY_SIGNAL_SECRET` | long random secret | Didit/Stripe由来の再登録防止シグナルをHMAC化する秘密値。raw値・免許証番号・カード番号は保存しない |
| `COCONIQUE_CAPTURE_STRIPE_CARD_FINGERPRINT` | `true` | Stripe invoice paid時にcard fingerprintを取得できる場合、HMAC化して補助シグナルとして保存。testでは明示しない限り外部取得しない |

## Coconique Identity Verification

| Key | Example | Notes |
|---|---|---|
| `COCONIQUE_IDENTITY_PROVIDER_PRIMARY` | `didit` / `quick_trust` / `stripe_identity` / `fake` | 主Provider |
| `COCONIQUE_IDENTITY_PROVIDER_FALLBACK` | `fake` | 主Provider未設定時のfallback。productionでは慎重に設定 |
| `COCONIQUE_USE_FAKE_IDENTITY` | `false` | developmentでfake Providerを強制するFeature Flag |
| `COCONIQUE_ALLOW_FAKE_IDENTITY` | `false` | fake本人確認完了APIの許可。productionでは原則false |
| `COCONIQUE_IDENTITY_PUBLIC_RETURN_URL` | `https://app.example.com/identity/return` | Didit QR/スマホ完了後の公開戻り先。ローカルスマホ検証ではViteをngrok等で公開したURLにする |

### Didit

| Key | Example | Notes |
|---|---|---|
| `DIDIT_API_BASE_URL` | `https://verification.didit.me` | Didit API base URL |
| `DIDIT_API_KEY` | `didit_xxx` | Didit API Key |
| `DIDIT_WEBHOOK_SECRET` | `whsec_xxx` | `/webhooks/didit` の署名検証用 |
| `DIDIT_WORKFLOW_ID_STANDARD` | `uuid` | 免許証/パスポート/在留カード等の通常workflow |
| `DIDIT_WORKFLOW_ID_MY_NUMBER` | `uuid` | マイナンバー表面のみworkflow。初期本番はOFF |
| `DIDIT_MY_NUMBER_CARD_ENABLED` | `false` | 初期本番は `false` |
| `DIDIT_SSL_ALLOW_CRL_FAILURE` | `false` | ローカルOpenSSLが `unable to get certificate CRL` で失敗する場合のみdevelopmentで一時利用。本番は必ず `false` |

### Quick Trust

| Key | Example | Notes |
|---|---|---|
| `QUICK_TRUST_LIVE_ENABLED` | `false` | 正式API仕様確定までfalse |
| `QUICK_TRUST_STUB_MODE` | `true` | 開発/検証用stubを使う |
| `QUICK_TRUST_API_BASE_URL` | `https://...` | 正式API仕様確定後に設定 |
| `QUICK_TRUST_API_KEY` | `qt_xxx` | 正式API仕様確定後に設定 |
| `QUICK_TRUST_WEBHOOK_SECRET` | `whsec_xxx` | `/webhooks/quick_trust` の署名検証用 |
| `QUICK_TRUST_MY_NUMBER_CARD_ENABLED` | `false` | 初期本番は `false` |

## Auth TTL / Solid Queue

| Key | Example | Notes |
|---|---|---|
| `AUTH_SESSION_TTL_DAYS` | `14` | ログインセッションTTL |
| `EMAIL_VERIFICATION_TTL_HOURS` | `24` | メール認証TTL |
| `PASSWORD_RESET_TTL_MINUTES` | `30` | パスワード再設定TTL |
| `JOB_CONCURRENCY` | `1` | worker process数 |

開発時は別ターミナルで起動します。

```bash
bin/jobs start
```
| `COCONIQUE_REQUEST_SYNC_INTERVAL_SECONDS` | `60` | Coconique APIリクエスト時に走る終了処理・帰宅確認通知処理の簡易スロットル秒数。リリース後はジョブ化推奨 |
| `STRIPE_BILLING_PORTAL_RETURN_URL` | `http://localhost:5173/app/settings` | Stripe Billing Portalから戻る先 |

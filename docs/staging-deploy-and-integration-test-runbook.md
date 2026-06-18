# Coconique Step 7-6 ステージング反映・Stripe/Didit実接続テスト手順

更新日: 2026-06-18  
対象: Staging環境 / Stripe Test mode / Didit staging相当Workflow

---

## 0. 目的

ステージング環境で以下を本番に近い形で確認する。

- Web/APIがHTTPSで接続できる
- Cookie / CSRF / CORS がステージングドメインで動く
- Stripe Test modeでFounder β Subscription Checkoutが動く
- `invoice.paid` webhookで月額主催チケット5枚が付与される
- Stripe Billing Portalでカード管理画面が開く
- Diditの本人確認Session作成、スマホQR、`/identity/return`、webhook/sync反映が動く
- SMS必須撤去後の安全登録条件が正しい
- 支払い未設定/本人確認未完了ユーザーに開催詳細がAPIでも返らない

---

## 1. デプロイ前の前提

### Web

- ステージングURL例: `https://app.stg.coconique.jp`
- API接続先はステージングAPIに向く
- `VITE_COCONIQUE_PUBLIC_APP_ORIGIN` はステージングWeb URL

### API

- ステージングURL例: `https://api.stg.coconique.jp`
- `RAILS_ENV=production` + `APP_ENV=staging` で運用する。`config/environments/staging.rb` は現時点では作らない
- `CURRENT_APP_KEY=coconique`
- `AUTH_COOKIE_DOMAIN=.stg.coconique.jp` を設定する。フロントが `app.stg`、APIが `api.stg` のため、CSRF cookieをWeb側が読める必要がある
- StripeはTest mode
- Diditはステージング用Workflowまたは本番前検証用Workflow
- マイナンバーカードは初期OFF
- SMSは初期必須から撤去済みなので `COCONIQUE_SMS_PROVIDER=fake`

---

## 2. 反映後にAPIで実行するdoctor

```bash
bin/rails db:migrate
bin/rails coconique:doctor
bin/rails coconique:staging:doctor
bin/rails coconique:stripe:doctor
bin/rails coconique:stripe:verify_remote
bin/rails coconique:identity:doctor
```

期待値:

- `coconique:staging:doctor` がErrors 0
- `RAILS_ENV=production`
- `APP_ENV=staging`
- `AUTH_COOKIE_DOMAIN=.stg.coconique.jp`
- `CORS_ALLOWED_ORIGINS` に `https://app.stg.coconique.jp` が含まれる
- Stripe keyが `sk_test_` / `pk_test_`
- Stripe Price/Couponが同じTest modeアカウントで取得できる
- `STRIPE_TAX_ENABLED=false`
- `COCONIQUE_USE_FAKE_STRIPE_CHECKOUT=false`
- `COCONIQUE_USE_FAKE_IDENTITY=false`
- `COCONIQUE_ALLOW_FAKE_IDENTITY=false`
- `COCONIQUE_IDENTITY_PUBLIC_RETURN_URL=https://.../identity/return`
- `DIDIT_MY_NUMBER_CARD_ENABLED=false`
- `DIDIT_SSL_ALLOW_CRL_FAILURE=false`

---

## 3. Cloudflare Access / Cookie / CORS 確認

`*.stg.coconique.jp` はCloudflare Accessで保護する。ただしWebhookはProvider署名で保護するため、Accessをbypassする。

保護対象:

```txt
app.stg.coconique.jp
api.stg.coconique.jp
admin.stg.coconique.jp
```

Bypass対象:

```txt
api.stg.coconique.jp/webhooks/stripe
api.stg.coconique.jp/webhooks/didit
api.stg.coconique.jp/webhooks/resend
api.stg.coconique.jp/webhooks/quick_trust
```

最初に確認すること:

- `app.stg.coconique.jp` がAccess認証後に開く
- `/api/v1/auth/csrf` が200で返る
- ブラウザのCookieに `coconique_csrf` が入り、domainが `.stg.coconique.jp` になっている
- ログイン後に `coconique_session` が入り、domainが `.stg.coconique.jp` になっている
- `/api/v1/auth/me` が200で返る
- POST/PATCH/DELETEでCORSやpreflightエラーが出ない
- Stripe/Didit webhookはAccess認証なしでProviderから到達できる

注意: Rails側にBasic Auth等の保険を入れる場合、`OPTIONS` preflight と `/webhooks/*` を落とさないこと。

---

## 4. Stripe Dashboard / Test mode設定

### Product / Price

| 用途 | 設定 | 期待値 |
|---|---|---|
| Founder β月額 | Recurring Price | 430 JPY / month |
| 初月割引 | Coupon | 330 JPY off / once |
| 追加主催チケット | One-time Price | 1000 JPY |

### Webhook endpoint

```text
https://api.stg.coconique.jp/webhooks/stripe
```

購読イベント:

```text
checkout.session.completed
checkout.session.expired
invoice.paid
invoice.payment_failed
invoice.payment_action_required
customer.subscription.updated
customer.subscription.deleted
charge.refunded
refund.updated
```

Stripe公式docsでは、サブスクリプションはwebhookで支払い失敗やステータス変化を処理し、Checkoutのサブスクリプション導入でもイベント監視とCustomer Portal設定が案内されている。

---

## 5. Stripe stagingテスト

### STG-STRIPE-01 新規ユーザー初回100円Checkout

1. シークレット/プライベートブラウザでWeb stagingへアクセス
2. 新規登録
3. メール認証
4. プロフィール入力
5. 月額利用開始画面からStripe Checkoutへ進む
6. Stripe Test cardで決済
7. `/billing/success` に戻る

期待結果:

- 画面に「登録が完了しました」
- 主催チケット5枚
- 次回更新日が1ヶ月後
- APIのbilling/statusでもsubscription active

確認API例:

```bash
bin/rails runner 'u=User.find_by(email: "stg-user@example.com"); puts u&.coconique_billing&.attributes'
```

### STG-STRIPE-02 Webhook確認

Stripe Dashboardのイベントログで以下を確認。

- `checkout.session.completed` が200
- `invoice.paid` が200

APIログで `/webhooks/stripe` が記録されること。

### STG-STRIPE-03 Billing Portal

1. `/app/settings` → 決済・チケット
2. クレジットカード設定を開く
3. Stripe Billing Portalが開く
4. 戻るボタンで `/app/settings` に戻る

### STG-STRIPE-04 支払い失敗

可能ならStripe test cardまたはStripe Dashboardのテスト機能で支払い失敗イベントを発生させる。

期待結果:

- `invoice.payment_failed` を受信
- `billingActive=false` 相当
- 参加申請/募集公開が止まる
- ログイン自体は可能

---

## 6. Didit staging設定

### Workflow

初期ON:

- 日本限定
- 運転免許証
- パスポート
- 在留カード
- 顔照合 + ライブ判定
- 18歳以上確認

初期OFF:

- マイナンバーカード
- 書類裏面必須化
- 日本国外の一般ID文書

### Return URL

```text
https://app.stg.coconique.jp/identity/return
```

### Webhook endpoint

```text
https://api.stg.coconique.jp/webhooks/didit
```

Didit docsではHosted Sessionがユーザー向けフローに推奨され、Session作成で生成されたURLをユーザーに提示し、結果はwebhookまたはAPIで受け取る形が説明されている。

---

## 7. Didit stagingテスト

### STG-DIDIT-01 本人確認Session作成

1. Stripe登録済みユーザーでログイン
2. 安全登録画面へ進む
3. Diditで本人確認を開始
4. Didit画面またはQRが表示される

期待結果:

- API 500なし
- Didit verification URLへ遷移
- `coconique_identity_verification_sessions` にsession保存

### STG-DIDIT-02 スマホQR / return URL

1. PCに表示されたQRをスマホで読む
2. スマホでDidit本人確認を完了
3. スマホ側が `/identity/return` に戻る

期待結果:

- 「本人確認の操作が完了しました」系の表示
- スマホ側でログイン必須画面にならない
- PC側は状態再取得で本人確認済みになる

### STG-DIDIT-03 webhook / sync反映

期待結果:

- `/webhooks/didit` が200
- webhookが遅れても安全登録画面のsyncで `identityVerified=true`
- `ageOver18=true`
- `canApplyOrPublish=true`

確認API:

```bash
bin/rails runner 'u=User.find_by(email: "stg-user@example.com"); pp u.coconique_identity_verification_sessions.order(:id).last&.attributes'
```

---

## 8. 開催詳細保護テスト

### STG-PRIVACY-01 未課金ユーザー

1. 未課金ユーザーで募集詳細を開く
2. 画面上で開催日時/集合場所/人数/服装/費用/主催メンバーがblurまたは案内表示になる
3. APIレスポンスに制限対象フィールドが含まれていないことを確認

### STG-PRIVACY-02 課金済み・本人確認未完了ユーザー

期待結果:

- 詳細情報はまだ見えない
- Didit本人確認への導線が出る

### STG-PRIVACY-03 課金済み・本人確認済みユーザー

期待結果:

- 開催日時/集合場所/人数/服装/費用/主催メンバーが表示される
- 参加申請できる

---

## 9. 募集作成/参加/通報の最小スモーク

| ID | 手順 | 期待結果 |
|---|---|---|
| STG-EVENT-01 | venueNameありで下書き保存 | 保存OK |
| STG-EVENT-02 | venueNameありで公開 | 公開OK、チケットreserved |
| STG-EVENT-03 | 参加申請 | 申請中になる |
| STG-EVENT-04 | 主催者が承認 | 参加確定、チャット可 |
| STG-EVENT-05 | チャット投稿 | 承認済みだけ表示/投稿可 |
| STG-EVENT-06 | 通報 | 管理画面に未対応として出る |
| STG-EVENT-07 | 退会/BAN | ログイン不可/再登録防止シグナル確認 |

---

## 10. Staging OK条件

- [ ] API/Web stagingがHTTPSで動く
- [ ] Cloudflare Accessで `*.stg.coconique.jp` が保護されている
- [ ] Stripe/Didit webhook pathはAccess bypass + Provider署名検証になっている
- [ ] CSRF/session cookie domainが `.stg.coconique.jp` になっている
- [ ] `bin/rails coconique:staging:doctor` Errors 0
- [ ] Stripe Test Checkout成功
- [ ] `invoice.paid` webhookでチケット5枚付与
- [ ] Billing Portalが開く
- [ ] Didit本人確認がライブ撮影ありで成功
- [ ] スマホQR後 `/identity/return` に戻る
- [ ] Didit webhookまたはsyncで本人確認済みになる
- [ ] SMSなしで安全登録完了できる
- [ ] 未課金/未本人確認ユーザーに開催詳細がAPIでも返らない
- [ ] 募集公開/参加申請/承認/チャット/通報が最低限通る
- [ ] BAN/退会後の状態が破綻しない


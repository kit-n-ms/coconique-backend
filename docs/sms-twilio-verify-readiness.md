# Coconique SMS / Twilio Verify 接続準備

更新日: 2026-06-16

## 方針

CoconiqueのSMS認証はログイン手段ではなく、安全登録の一部として利用する。
Rails側の既存ユーザー・Cookie session・CSRF構成を維持し、SMS送信とコード確認だけをTwilio Verifyに委譲する。

## 環境変数

```env
COCONIQUE_SMS_PROVIDER=twilio_verify
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_VERIFY_SERVICE_SID=VAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_VERIFY_CHANNEL=sms
TWILIO_VERIFY_LOCALE=ja
TWILIO_VERIFY_API_BASE_URL=https://verify.twilio.com
TWILIO_VERIFY_CUSTOM_FRIENDLY_NAME=Coconique
```

`TWILIO_AUTH_TOKEN` はログ・フロント・エラー詳細に出さない。

## ローカル確認

設定値の存在確認のみ行う。

```bash
bin/rails coconique:sms:doctor
```

実SMS送信を試す場合のみ、`COCONIQUE_SMS_PROVIDER=twilio_verify` にしてRailsを再起動する。
通常のdevelopment/testは `fake_sms` のままでよい。

## APIフロー

1. `POST /api/v1/coconique/safety/phone_verifications`
   - 電話番号を正規化
   - Twilio Verify `Verifications` を作成
   - Coconique側には電話番号digest、masked phone、Twilio verification SIDのみ保存
2. `POST /api/v1/coconique/safety/phone_verifications/confirm`
   - Twilio Verify `VerificationCheck` にコードを送信
   - `approved` / `valid=true` ならCoconique側を電話番号確認済みにする

## 保存するもの

- 電話番号digest
- マスク済み電話番号
- Twilio verification SID
- provider status / check status

保存しないもの

- 平文電話番号
- SMS本文
- ユーザー入力コード

## 注意

- SMS送信はコストが発生するため、β前にレート制限を追加検討する。
- Twilio Verifyは成功verificationごとの基本料金に加えてchannel feeがかかる。
- 電話番号の国制限を入れる場合は、日本向け初期βでは `+81` のみ許可する案を検討する。

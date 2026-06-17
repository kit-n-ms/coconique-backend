# Coconique Step 7-3 Didit本人確認 本接続準備メモ

更新日: 2026-06-15

## 方針

Coconiqueの一般βでは、参加申請または募集公開の直前に安全登録を求める。本人確認Providerは `COCONIQUE_IDENTITY_PROVIDER_PRIMARY=didit` を基本とし、SMS確認完了後にDidit hosted sessionへ遷移する。

DiditのHosted Sessionは、サーバー側でSessionを作成し、返ってきた本人確認URLへユーザーを遷移させる方式。Diditの公式ドキュメントでは、`POST /v3/session/` に `workflow_id` と `vendor_data`、`callback` を渡してsessionを作成し、生成されたverification URLをユーザーへ提示する流れが案内されている。

## Coconique側で保存するもの

保存する:

- provider: `didit`
- provider_session_id
- local public_id
- status
- workflow_type
- document_type
- provider_status
- verified_at
- age_over_18
- provider session削除済み日時

保存しない:

- 本人確認書類画像
- セルフィー画像
- OCR詳細
- 住所全文
- 書類番号
- Diditの詳細レポート全文

## 環境変数

```env
COCONIQUE_IDENTITY_PROVIDER_PRIMARY=didit
COCONIQUE_IDENTITY_PROVIDER_FALLBACK=fake_identity
COCONIQUE_USE_FAKE_IDENTITY=false
COCONIQUE_ALLOW_FAKE_IDENTITY=false

DIDIT_API_BASE_URL=https://verification.didit.me
DIDIT_API_KEY=didit_xxx
DIDIT_WORKFLOW_ID_STANDARD=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
DIDIT_WEBHOOK_SECRET=whsec_or_didit_secret
DIDIT_MY_NUMBER_CARD_ENABLED=false
# DIDIT_WORKFLOW_ID_MY_NUMBER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## Didit管理画面側で設定するもの

- KYC Workflowを作成
- 初期ON想定: 運転免許証、パスポート、在留カード
- 初期OFF: マイナンバーカード
- Callback/Redirect先: フロントの安全登録ページ
- Webhook endpoint: `https://api.example.com/webhooks/didit`
- Webhook secretを `DIDIT_WEBHOOK_SECRET` に設定

## ローカル検証

DiditからローカルへWebhookを直接届けるには、ngrok等でRailsの `/webhooks/didit` を公開する。

```bash
ngrok http 3000
```

Didit管理画面のWebhook endpointに以下のようなURLを設定する。

```text
https://xxxxx.ngrok-free.app/webhooks/didit
```

## Coconique側の確認コマンド

```bash
bin/rails coconique:identity:doctor
bin/rails routes | grep didit
bin/rails routes | grep identity_verifications
bin/rails test
```

## 反映経路

正ルート:

1. SMS確認完了
2. `POST /api/v1/coconique/safety/identity_verifications`
3. Didit session作成
4. ユーザーをDidit本人確認URLへ遷移
5. Didit webhook `/webhooks/didit`
6. Coconique側で `identity_verified` / `age_over_18` を反映
7. 安全登録完了

保険ルート:

1. ユーザーがDiditからCoconique安全登録ページへ戻る
2. `POST /api/v1/coconique/safety/identity_verifications/sync`
3. Coconique APIがDidit decision APIを再照会
4. 支払い済みなら安全登録状態を更新

Webhookを正としつつ、戻り画面からの同期でローカル検証や反映遅延に強くする。

## β前に必ず見ること

- Didit session作成時に `verification_url` が返る
- フロントからDiditへ遷移できる
- Diditから安全登録ページへ戻れる
- WebhookがRailsログに届く
- `approved` で `identity_verification_status=verified` になる
- `rejected` で `identity_verification_status=rejected` になる
- 18歳未満または年齢確認NGを本番前にどう受けるか確認する
- provider session削除APIが成功し、Coconique側に削除日時が残る

## 2026-06-16 追記: ローカルTLS/CRLエラー

Didit session作成時に以下のようなエラーが出る場合がある。

```text
OpenSSL::SSL::SSLError: certificate verify failed (unable to get certificate CRL)
```

これはCoconiqueの操作手順の問題ではなく、ローカルPCのOpenSSL/証明書ストア設定がCRL確認を要求しているのに、必要なCRLを取得・参照できない場合に起こる。

今回の実装では、Didit API接続時にCoconique側で専用のcert storeを作り、通常の証明書チェーン・ホスト名検証は維持しつつ、CRL検証フラグを明示的に外すようにした。

それでもローカルdevelopmentで同じエラーが残る場合だけ、以下を一時的に使える。

```env
DIDIT_SSL_ALLOW_CRL_FAILURE=true
```

注意:

- 本番では必ず `false`
- development/test専用
- 許可するのは `unable to get certificate CRL` のみ
- 通常の証明書不正やホスト名不一致は許可しない

## Didit Workflow設定メモ

DiditのWorkflow Builder上では、スクリーンショットのように「身分証明書」タブ内で文書面を「片側」にできるため、マイナンバーカードを通常workflowに含めても、表面のみ撮影に設定できる可能性がある。

ただし初期本番では、Coconique側の安全方針として以下を推奨する。

1. 通常workflow: 運転免許証、パスポート、在留カードをON
2. マイナンバーカード: まずOFF、または別workflowで限定検証
3. マイナンバーをONにする場合は、Didit画面で裏面撮影が一切出ないことを実機で確認
4. Coconique側にはOCR詳細・画像URL・住所全文・書類番号を保存しない

## Diditのテスト利用

- DiditのConsoleでTest/Sandbox用のAPI keyとWorkflow IDを使う
- Coconique側の `DIDIT_API_KEY` と `DIDIT_WORKFLOW_ID_STANDARD` は同じ環境・同じWorkflowのものを設定する
- local webhook検証はngrok等で `/webhooks/didit` を公開する
- webhookが届かない場合でも、Diditから戻った安全登録画面で `sync` APIが1回だけ結果照会する


## Didit QR / スマホ戻り先

PCでDidit画面を開き、QRコードからスマホで本人確認する場合、スマホ側はPCの `localhost` に戻れない。
そのため、Didit session作成時のreturn URLはログイン必須画面ではなく、公開の完了ページを指定する。

```env
COCONIQUE_IDENTITY_PUBLIC_RETURN_URL=https://app.example.com/identity/return
```

ローカルでスマホ実機確認する場合は、Vite dev serverもngrok等で公開し、公開URLを上記に設定する。

例:

```bash
ngrok http 5173
# COCONIQUE_IDENTITY_PUBLIC_RETURN_URL=https://xxxxx.ngrok-free.app/identity/return
```

スマホ側の完了ページはログイン不要の案内だけを表示し、Coconiqueの状態反映はPC側のwebhook/syncで行う。

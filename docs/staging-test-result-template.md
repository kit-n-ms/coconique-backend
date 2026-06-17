# Coconique Step 7-6 Staging 実接続テスト記録テンプレート

実施日:  
実施者:  
Web URL:  
API URL:  
Git SHA / deploy id:  

## 1. Doctor

| コマンド | 結果 | メモ |
|---|---|---|
| `bin/rails db:migrate` |  |  |
| `bin/rails km:doctor` |  |  |
| `bin/rails coconique:staging:doctor` |  |  |
| `bin/rails coconique:stripe:doctor` |  |  |
| `bin/rails coconique:stripe:verify_remote` |  |  |
| `bin/rails coconique:identity:doctor` |  |  |

## 2. Stripe

| ID | 項目 | 結果 | メモ |
|---|---|---|---|
| STRIPE-01 | 初月100円Checkout |  |  |
| STRIPE-02 | Success画面でチケット5枚 |  |  |
| STRIPE-03 | `checkout.session.completed` webhook 200 |  |  |
| STRIPE-04 | `invoice.paid` webhook 200 |  |  |
| STRIPE-05 | Billing Portal起動 |  |  |
| STRIPE-06 | 支払い失敗時の制限 |  |  |

## 3. Didit

| ID | 項目 | 結果 | メモ |
|---|---|---|---|
| DIDIT-01 | Session作成 |  |  |
| DIDIT-02 | スマホQR認証 |  |  |
| DIDIT-03 | `/identity/return` 表示 |  |  |
| DIDIT-04 | Didit webhook 200 |  |  |
| DIDIT-05 | syncで本人確認反映 |  |  |
| DIDIT-06 | `canApplyOrPublish=true` |  |  |

## 4. 詳細保護

| ID | 項目 | 結果 | メモ |
|---|---|---|---|
| PRIVACY-01 | 未課金ユーザーで詳細blur |  |  |
| PRIVACY-02 | APIで制限フィールドが返らない |  |  |
| PRIVACY-03 | 課金済み・未本人確認で制限 |  |  |
| PRIVACY-04 | 課金済み・本人確認済みで表示 |  |  |

## 5. 募集/参加/通報

| ID | 項目 | 結果 | メモ |
|---|---|---|---|
| EVENT-01 | 募集下書き |  |  |
| EVENT-02 | 募集公開 |  |  |
| EVENT-03 | 参加申請 |  |  |
| EVENT-04 | 承認 |  |  |
| EVENT-05 | チャット |  |  |
| EVENT-06 | 通報 |  |  |
| EVENT-07 | BAN/退会 |  |  |

## 6. 判定

- [ ] Staging OK
- [ ] 修正後再テスト
- [ ] 本番設定準備へ進む

未解決Issue:

1.
2.
3.

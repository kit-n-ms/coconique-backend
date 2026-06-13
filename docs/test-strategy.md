# Test Strategy

## 目的

Hodokoo / Coconique に複製しても大きく修正しなくてよい「共通基盤の契約テスト」です。

## テスト対象

- 認証
- CSRF
- `/me`
- クレジット商品一覧
- クレジット残高
- Stripe webhook
- 残高の二重加算防止

## あえて対象にしないもの

- Hodokoo固有の契約書/営業トーク/AIチェック履歴
- Coconique固有の本人確認/緊急連絡先/通報/集合場所
- サービス固有のUIデザイン

## 実行

```bash
bin/rails test
```

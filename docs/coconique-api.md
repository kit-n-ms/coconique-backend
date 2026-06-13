# Coconique API 追加仕様

共通基盤 v1 の Auth / Onboarding / Billing を壊さず、Coconique 固有のイベント・気になる・参加申請・ダッシュボード用APIを追加する。

## 方針

- 既存の認証、Cookie session、CSRF、AuditLog を流用する。
- `id` はフロントのモックデータに合わせ、イベントでは `public_id` を返す。
- Coconique 固有の本人確認や詳細な管理画面はまだ入れない。
- レスポンスは Vue 側の `CoconiqueEvent` 型に合わせて camelCase で返す。

## エンドポイント

すべてログイン必須。

### ダッシュボード

```http
GET /api/v1/coconique/dashboard
```

返却例:

```json
{
  "ok": true,
  "data": {
    "dashboard": {
      "safety_notice": {},
      "action_counts": {},
      "pickup_events": [],
      "recommended_events": [],
      "hosted_events": [],
      "current_rule": {},
      "safety_features": []
    }
  }
}
```

### イベント

```http
GET /api/v1/coconique/events
GET /api/v1/coconique/events/:public_id
POST /api/v1/coconique/events
PATCH /api/v1/coconique/events/:public_id
```

クエリ:

- `category_key`
- `status`
- `q`
- `limit`

### 気になる

```http
GET /api/v1/coconique/favorites
POST /api/v1/coconique/events/:public_id/favorite
DELETE /api/v1/coconique/events/:public_id/favorite
```

### 参加申請

```http
GET /api/v1/coconique/participation_requests
GET /api/v1/coconique/participation_requests/:id
PATCH /api/v1/coconique/participation_requests/:id
PATCH /api/v1/coconique/participation_requests/:id/withdraw
POST /api/v1/coconique/events/:public_id/participation_requests
GET /api/v1/coconique/events/:public_id/participation_requests
PATCH /api/v1/coconique/participation_requests/:id/approve
PATCH /api/v1/coconique/participation_requests/:id/reject
```

- 自分の申請一覧は `GET /api/v1/coconique/participation_requests`
- 主催イベントの申請一覧は `GET /api/v1/coconique/events/:public_id/participation_requests`
- approve / reject はイベント主催者または admin のみ可能。

### 自分が貼った予定

```http
GET /api/v1/coconique/hosted_events
```

## 追加モデル

- `CoconiqueEvent`
- `CoconiqueEventFavorite`
- `CoconiqueParticipationRequest`

## Seed

`db/seeds.rb` に、Vue 側の `demoEvents.ts` と同じ9件のイベントを追加している。

```bash
bin/rails db:seed
```

## フロント連携メモ

まずは既存のモック表示を維持し、以下の順番でAPIに置き換えるのが安全。

1. `GET /api/v1/coconique/events` で `eventStore.events` を差し替え
2. `POST/DELETE favorite` で `toggleFavorite` をAPI化
3. `POST participation_requests` で参加申請をAPI化
4. `GET dashboard` でダッシュボード件数とピックアップ表示をAPI化


## Step 1: 予定作成・編集・公開管理

この段階では、チケット消費・参加承認・終了後レビューはまだ入れず、主催者が予定を作成して状態管理できるところまでを扱う。

### 作成

```http
POST /api/v1/coconique/events
```

- `publish: false` または未指定: `draft` として下書き保存
- `publish: true`: 作成直後に `recruiting` として公開

### 編集

```http
PATCH /api/v1/coconique/events/:public_id
```

イベント主催者または admin のみ更新可能。

### 公開・募集管理

```http
PATCH /api/v1/coconique/events/:public_id/publish
PATCH /api/v1/coconique/events/:public_id/close
PATCH /api/v1/coconique/events/:public_id/reopen
PATCH /api/v1/coconique/events/:public_id/cancel
PATCH /api/v1/coconique/events/:public_id/finish
```

状態の意味:

- `draft`: 下書き。主催者だけが確認できる。
- `recruiting`: 募集中。参加者向け一覧に表示される。
- `closed`: 募集停止。参加者向け一覧には表示せず、新規申請も不可。
- `confirmed`: 開催確定。参加承認フロー実装時に使用予定。
- `finished`: 終了済み。終了後管理の入口。
- `canceled`: 中止。参加者向け一覧には表示しない。

### 自分が貼った予定

```http
GET /api/v1/coconique/hosted_events
GET /api/v1/coconique/hosted_events?status=draft
GET /api/v1/coconique/hosted_events?q=カフェ
```

主催者本人の予定は、下書き・募集中・募集停止・終了・中止を含めて取得できる。

## Step 2: 気になる

### 一覧

```http
GET /api/v1/coconique/favorites
```

返却対象は、現在募集中または開催確定で、開始日時が未来の予定。終了済み・中止・募集停止中・募集締切後の予定は一覧から外れる。参加申請済み・承認済みでも、ユーザー本人の保存リストとして表示できる。

### 追加

```http
POST /api/v1/coconique/events/:public_id/favorite
```

- 募集中または開催確定の予定のみ追加可能。
- 自分が主催する予定は追加不可。
- 参加申請済み・承認済みの予定でも、ユーザー本人の保存用途として追加可能。
- 追加時に `coconique_events.interested_count` を +1 する。

### 削除

```http
DELETE /api/v1/coconique/events/:public_id/favorite
```

募集停止・終了・中止後でも、自分の保存状態を外せるように、削除は公開状態に依存しない。

### 自動削除

- 参加申請作成時・承認時も、その予定の `favorite` は自動削除しない。
- 予定を `finished` または `canceled` にした時、その予定に紐づく `favorite` は削除する。
- 募集停止 `closed` は再開の可能性があるためDB上の `favorite` は残すが、一覧APIからは返さない。

## Step 3: Participation Requests / 参加申請

### Participant

- `POST /api/v1/coconique/events/:event_public_id/participation_requests`
  - body: `{ "message": "参加したいです" }`
  - creates a pending participation request.
  - does not consume tickets at this step.
  - returns the existing request if it is already pending.
  - allows resubmission from `withdrawn` / `auto_withdrawn` / `draft`.
  - blocks own hosted events, closed/canceled/finished/expired recruitment events, full events, approved requests, and rejected requests.

- `GET /api/v1/coconique/participation_requests`
  - returns the current user's participation request history.
  - optional: `?status=pending|approved|rejected|withdrawn|auto_withdrawn`.

- `GET /api/v1/coconique/participation_requests/:id`
  - `:id` is `public_id` like `prq-xxxxxxxxxxxxxxxx`.
  - owner, host, and admin can read it.

- `PATCH /api/v1/coconique/participation_requests/:id`
  - updates message while the request is `pending`.

- `PATCH /api/v1/coconique/participation_requests/:id/withdraw`
  - withdraws only `pending` requests.
  - keeps favorites untouched.

### Host

- `GET /api/v1/coconique/events/:event_public_id/participation_requests`
  - host/admin only.
  - returns requests for the hosted event.
  - optional status filter is supported.

Approval/rejection and the host-side approval UI are implemented in Step 4. Ticket consumption is planned for a later mock-ticket/ticket management step.

## Step 4: 参加承認・参加者管理

### 承認

```http
PATCH /api/v1/coconique/participation_requests/:id/approve
```

- host/admin only.
- only `pending` requests can be approved.
- closed/canceled/finished/past/full events cannot approve new participants.
- approval increments `coconique_events.current_participants`.
- if `current_participants >= min_participants` and the event is still `recruiting`, the event becomes `confirmed`.
- approved participants can see `meetingPlace` in their own participation request detail.
- ticket consumption is intentionally not performed in this step; it will be added with the mock-ticket/ticket management step.

### 見送り

```http
PATCH /api/v1/coconique/participation_requests/:id/reject
```

- host/admin only.
- only `pending` requests can be rejected.
- rejected requests do not change `current_participants`.

### 参加者管理

```http
GET /api/v1/coconique/events/:public_id/participants
```

- host/admin only.
- returns approved participation requests for the event.
- used by the host-side participant management UI.

# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Coconique 派生 API

Coconique用に以下のAPIを追加しています。

- `GET /api/v1/coconique/dashboard`
- `GET /api/v1/coconique/events`
- `GET /api/v1/coconique/events/:public_id`
- `POST /api/v1/coconique/events`
- `POST /api/v1/coconique/events/:public_id/favorite`
- `DELETE /api/v1/coconique/events/:public_id/favorite`
- `POST /api/v1/coconique/events/:public_id/participation_requests`
- `GET /api/v1/coconique/participation_requests`
- `GET /api/v1/coconique/hosted_events`

詳細は `docs/coconique-api.md` を参照してください。

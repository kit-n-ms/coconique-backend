require "test_helper"

class CoconiqueApiTest < ActionDispatch::IntegrationTest
  include AuthRequestHelper
  include JsonResponseHelper

  setup do
    @user = create_test_user!
    @host = create_test_user!(email: "host-#{SecureRandom.hex(6)}@example.test")
    login_as!(@user)

    @event = CoconiqueEvent.create!(
      public_id: "evt-test-001",
      host: @host,
      title: "テスト散歩会",
      category_key: "walk",
      venue_name: "渋谷の小さな公園",
      area: "東京都 渋谷区",
      starts_at: 3.days.from_now,
      ends_at: 3.days.from_now + 2.hours,
      meeting_place: "渋谷駅前",
      image_url: "https://example.test/walk.jpg",
      capacity: 4,
      min_participants: 2,
      current_participants: 1,
      interested_count: 0,
      cost_label: "無料",
      dress_code: "歩きやすい靴",
      host_display_name: "ココさん",
      host_age_group: "30代",
      host_message: "テストです",
      summary: "テスト用イベントです",
      status: :recruiting
    )
  end

  test "lists coconique events" do
    get "/api/v1/coconique/events"

    assert_response :success
    body = json_body
    assert_equal true, body["ok"]
    assert body.dig("data", "events").any? { |event| event["id"] == "evt-test-001" }
  end

  test "toggles favorite" do
    post "/api/v1/coconique/events/#{@event.public_id}/favorite",
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal 1, @user.coconique_event_favorites.count

    delete "/api/v1/coconique/events/#{@event.public_id}/favorite",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal 0, @user.coconique_event_favorites.count
  end


  test "favorites list keeps requested events and request does not remove favorite" do
    post "/api/v1/coconique/events/#{@event.public_id}/favorite",
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal 1, @user.coconique_event_favorites.count
    assert_equal 1, @event.reload.interested_count

    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal 1, @user.coconique_event_favorites.count
    assert_equal 1, @event.reload.interested_count

    get "/api/v1/coconique/favorites"

    assert_response :success
    assert json_body.dig("data", "events").any? { |event| event["id"] == @event.public_id }
  end

  test "requested event can be added to favorites later" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal 0, @user.coconique_event_favorites.count

    post "/api/v1/coconique/events/#{@event.public_id}/favorite",
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal 1, @user.coconique_event_favorites.count
    assert_equal 1, @event.reload.interested_count

    get "/api/v1/coconique/favorites"

    assert_response :success
    assert json_body.dig("data", "events").any? { |event| event["id"] == @event.public_id }
  end

  test "expired recruitment event is hidden from favorites" do
    @event.update!(recruitment_ends_at: 1.hour.ago)

    post "/api/v1/coconique/events/#{@event.public_id}/favorite",
      headers: json_headers(csrf_headers)

    assert_response :unprocessable_entity

    @event.update!(recruitment_ends_at: 1.day.from_now)

    post "/api/v1/coconique/events/#{@event.public_id}/favorite",
      headers: json_headers(csrf_headers)

    assert_response :created

    @event.update!(recruitment_ends_at: 1.hour.ago)

    get "/api/v1/coconique/favorites"

    assert_response :success
    assert_not json_body.dig("data", "events").any? { |event| event["id"] == @event.public_id }
  end

  test "event without approved participants is auto canceled and removed from favorites" do
    post "/api/v1/coconique/events/#{@event.public_id}/favorite",
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal 1, @event.reload.interested_count

    login_as!(@host)

    patch "/api/v1/coconique/events/#{@event.public_id}/finish",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "canceled", json_body.dig("data", "event", "status")
    assert_equal 0, @event.reload.coconique_event_favorites.count
    assert_equal 0, @event.interested_count
  end

  test "creates participation request" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal "pending", json_body.dig("data", "participation_request", "status")
  end


  test "participation request list detail update and withdraw flow" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "最初の申請文です" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")
    assert_match(/^prq-/, request_id)

    get "/api/v1/coconique/participation_requests"

    assert_response :success
    assert json_body.dig("data", "participation_requests").any? { |request| request["id"] == request_id }

    get "/api/v1/coconique/participation_requests/#{request_id}"

    assert_response :success
    assert_equal "pending", json_body.dig("data", "participation_request", "status")
    assert_not json_body.dig("data", "participation_request", "event").key?("meetingPlace")

    patch "/api/v1/coconique/participation_requests/#{request_id}",
      params: { message: "更新した申請文です" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "更新した申請文です", json_body.dig("data", "participation_request", "message")

    patch "/api/v1/coconique/participation_requests/#{request_id}/withdraw",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "withdrawn", json_body.dig("data", "participation_request", "status")
  end

  test "duplicate pending participation request does not create a second row" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "もう一度送信" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal request_id, json_body.dig("data", "participation_request", "id")
    assert_equal 1, @user.coconique_participation_requests.where(coconique_event: @event).count
  end

  test "withdrawn participation request does not block reapplication from event detail" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "最初の申請です" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    withdrawn_request_id = json_body.dig("data", "participation_request", "id")

    patch "/api/v1/coconique/participation_requests/#{withdrawn_request_id}/withdraw",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "withdrawn", json_body.dig("data", "participation_request", "status")

    get "/api/v1/coconique/events/#{@event.public_id}"

    assert_response :success
    assert_nil json_body.dig("data", "event", "requestStatus")

    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "再申請します" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    new_request_id = json_body.dig("data", "participation_request", "id")
    assert_not_equal withdrawn_request_id, new_request_id
    assert_equal "pending", json_body.dig("data", "participation_request", "status")
    assert_equal "再申請します", json_body.dig("data", "participation_request", "message")
    assert_equal 2, @user.coconique_participation_requests.where(coconique_event: @event).count

    get "/api/v1/coconique/events/#{@event.public_id}"

    assert_response :success
    assert_equal "pending", json_body.dig("data", "event", "requestStatus")
  end

  test "host can list participation requests for hosted event" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created

    login_as!(@host)

    get "/api/v1/coconique/events/#{@event.public_id}/participation_requests"

    assert_response :success
    request = json_body.dig("data", "participation_requests").first
    assert_not request.key?("message"), "一覧APIでは申請メッセージを返さない"
    assert_equal @user.email.split("@").first, request.dig("user", "displayName")
    assert_not request.dig("event").key?("meetingPlace"), "一覧APIでは集合場所を返さない"

    get "/api/v1/coconique/participation_requests/#{request["id"]}"

    assert_response :success
    assert_equal "参加したいです", json_body.dig("data", "participation_request", "message")
    assert json_body.dig("data", "participation_request", "event").key?("meetingPlace")
  end


  test "host sees reapplication as a new pending request while withdrawn history remains" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "一度目の申請です" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    withdrawn_request_id = json_body.dig("data", "participation_request", "id")

    patch "/api/v1/coconique/participation_requests/#{withdrawn_request_id}/withdraw",
      headers: json_headers(csrf_headers)

    assert_response :success

    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "再申請です" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    new_request_id = json_body.dig("data", "participation_request", "id")

    login_as!(@host)

    get "/api/v1/coconique/events/#{@event.public_id}/participation_requests?status=pending"

    assert_response :success
    pending_requests = json_body.dig("data", "participation_requests")
    assert_equal [new_request_id], pending_requests.map { |request| request["id"] }
    assert_equal "pending", pending_requests.first["status"]
    assert_equal "host", pending_requests.first["viewerRole"]

    get "/api/v1/coconique/events/#{@event.public_id}/participation_requests"

    assert_response :success
    statuses_by_id = json_body.dig("data", "participation_requests").to_h { |request| [request["id"], request["status"]] }
    assert_equal "withdrawn", statuses_by_id[withdrawn_request_id]
    assert_equal "pending", statuses_by_id[new_request_id]
  end

  test "dashboard includes host notice for pending request without exposing meeting place in public cards" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created

    login_as!(@host)

    get "/api/v1/coconique/dashboard"

    assert_response :success
    notices = json_body.dig("data", "dashboard", "host_notices")
    assert_equal 1, notices.length
    assert_equal @event.public_id, notices.first["event_id"]
    assert_equal 1, json_body.dig("data", "dashboard", "action_counts", "host_pending_requests")
  end

  test "host can list all participation requests across hosted events" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    login_as!(@host)

    get "/api/v1/coconique/participation_requests?role=host&status=pending"

    assert_response :success
    requests = json_body.dig("data", "participation_requests")
    assert requests.any? { |request| request["id"] == request_id && request["viewerRole"] == "host" }
  end

  test "host creates draft and publishes it" do
    login_as!(@host)

    post "/api/v1/coconique/events",
      params: event_params(title: "下書き予定", publish: false).to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    event_id = json_body.dig("data", "event", "id")
    assert_equal "draft", json_body.dig("data", "event", "status")

    patch "/api/v1/coconique/events/#{event_id}/publish",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "recruiting", json_body.dig("data", "event", "status")
  end

  test "non host cannot update hosted event" do
    patch "/api/v1/coconique/events/#{@event.public_id}",
      params: { title: "変更できないタイトル" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :forbidden
  end

  test "host can close and reopen event" do
    login_as!(@host)

    patch "/api/v1/coconique/events/#{@event.public_id}/close",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "closed", json_body.dig("data", "event", "status")

    patch "/api/v1/coconique/events/#{@event.public_id}/reopen",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "recruiting", json_body.dig("data", "event", "status")
  end


  test "closed and canceled events are hidden from member lists" do
    @event.update!(status: :closed, closed_at: Time.current)

    get "/api/v1/coconique/events"

    assert_response :success
    assert_not json_body.dig("data", "events").any? { |event| event["id"] == @event.public_id }

    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :unprocessable_entity
    assert_equal "この募集は停止されました。", json_body.dig("error", "message")
  end

  test "dashboard public cards do not expose meeting place" do
    get "/api/v1/coconique/dashboard"

    assert_response :success
    event = json_body.dig("data", "dashboard", "pickup_events").find { |row| row["id"] == @event.public_id }
    assert event
    assert_not event.key?("meetingPlace")
    assert_not event.key?("referenceUrl")
  end


  test "host approves pending participation request and participant can see meeting place" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    login_as!(@host)

    patch "/api/v1/coconique/participation_requests/#{request_id}/approve",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "approved", json_body.dig("data", "participation_request", "status")
    assert_equal 2, @event.reload.current_participants
    assert_equal "confirmed", @event.status
    assert_equal false, json_body.dig("data", "participation_request", "canApprove")

    get "/api/v1/coconique/events/#{@event.public_id}/participants"

    assert_response :success
    assert json_body.dig("data", "participants").any? { |request| request["id"] == request_id }

    login_as!(@user)

    get "/api/v1/coconique/participation_requests/#{request_id}"

    assert_response :success
    assert_equal "渋谷駅前", json_body.dig("data", "participation_request", "event", "meetingPlace")
    assert_equal false, json_body.dig("data", "participation_request", "event", "meetingPlaceIsHidden")
  end

  test "host rejects pending participation request" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "今回は相談したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    login_as!(@host)

    patch "/api/v1/coconique/participation_requests/#{request_id}/reject",
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "rejected", json_body.dig("data", "participation_request", "status")
    assert_equal 1, @event.reload.current_participants
  end

  test "host cannot approve when capacity is full" do
    @event.update!(current_participants: @event.capacity)

    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :unprocessable_entity
    assert_equal "この募集は定員に達しています。", json_body.dig("error", "message")
  end

  test "non host cannot approve request" do
    other = create_test_user!(email: "other-#{SecureRandom.hex(6)}@example.test")

    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    login_as!(other)

    patch "/api/v1/coconique/participation_requests/#{request_id}/approve",
      headers: json_headers(csrf_headers)

    assert_response :forbidden
  end


  test "approved participant can use event chat and pending participant cannot" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    get "/api/v1/coconique/events/#{@event.public_id}/chat_messages"
    assert_response :forbidden

    login_as!(@host)

    patch "/api/v1/coconique/participation_requests/#{request_id}/approve",
      headers: json_headers(csrf_headers)

    assert_response :success

    get "/api/v1/coconique/events/#{@event.public_id}/chat_messages"
    assert_response :success
    assert_equal "host", json_body.dig("data", "viewer_role")

    login_as!(@user)

    get "/api/v1/coconique/events/#{@event.public_id}/chat_messages"
    assert_response :success
    assert_equal "participant", json_body.dig("data", "viewer_role")
    assert_equal true, json_body.dig("data", "can_post")

    get "/api/v1/coconique/chat_rooms"
    assert_response :success
    room = json_body.dig("data", "chat_rooms").find { |row| row["eventId"] == @event.public_id }
    assert room.present?
    assert_equal "/api/v1/coconique/chat_rooms/#{@event.public_id}/messages", room["messagesPath"]

    get "/api/v1/coconique/chat_rooms/#{@event.public_id}/messages"
    assert_response :success
    assert_equal "participant", json_body.dig("data", "viewer_role")

    post "/api/v1/coconique/chat_rooms/#{@event.public_id}/messages",
      params: { body: "当日はよろしくお願いします！" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal "当日はよろしくお願いします！", json_body.dig("data", "chat_message", "body")
  end

  test "lost item chat can be posted only after event end" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    login_as!(@host)

    patch "/api/v1/coconique/participation_requests/#{request_id}/approve",
      headers: json_headers(csrf_headers)

    assert_response :success

    login_as!(@user)

    post "/api/v1/coconique/chat_rooms/#{@event.public_id}/messages",
      params: {
        body: "これはどなたの傘でしょうか？",
        kind: "lost_item",
        imageUrls: ["data:image/webp;base64,AAAA"]
      }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :unprocessable_entity
    assert_equal "LOST_ITEM_NOT_POSTABLE", json_body.dig("error", "code")

    @event.update!(
      starts_at: 2.hours.ago,
      ends_at: 1.hour.ago,
      recruitment_ends_at: 3.hours.ago,
      status: :confirmed
    )

    get "/api/v1/coconique/chat_rooms/#{@event.public_id}/messages"
    assert_response :success
    assert_equal "finished", json_body.dig("data", "event", "status")

    post "/api/v1/coconique/chat_rooms/#{@event.public_id}/messages",
      params: {
        body: "これはどなたの傘でしょうか？",
        kind: "lost_item",
        imageUrls: ["data:image/webp;base64,AAAA"]
      }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    assert_equal "lost_item", json_body.dig("data", "chat_message", "kind")
    assert_equal ["data:image/webp;base64,AAAA"], json_body.dig("data", "chat_message", "imageUrls")
  end



  test "dashboard shows unread chat notice and reading chat clears it" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    login_as!(@host)

    patch "/api/v1/coconique/participation_requests/#{request_id}/approve",
      headers: json_headers(csrf_headers)

    assert_response :success

    post "/api/v1/coconique/events/#{@event.public_id}/chat_messages",
      params: { body: "集合前に少し早めに来てください" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created

    login_as!(@user)

    get "/api/v1/coconique/dashboard"

    assert_response :success
    chat_notices = json_body.dig("data", "dashboard", "chat_notices")
    assert_equal 1, chat_notices.length
    assert_equal @event.public_id, chat_notices.first["event_id"]
    assert_operator chat_notices.first["count"], :>=, 1
    assert_operator json_body.dig("data", "dashboard", "action_counts", "unread_chat_messages"), :>=, 1

    get "/api/v1/coconique/events/#{@event.public_id}/chat_messages"

    assert_response :success

    get "/api/v1/coconique/dashboard"

    assert_response :success
    assert_empty json_body.dig("data", "dashboard", "chat_notices")
    assert_equal 0, json_body.dig("data", "dashboard", "action_counts", "unread_chat_messages")
  end

  test "full events are excluded from dashboard pickup candidates" do
    @event.update!(current_participants: @event.capacity)

    get "/api/v1/coconique/dashboard"

    assert_response :success
    pickup_events = json_body.dig("data", "dashboard", "pickup_events")
    assert_not pickup_events.any? { |event| event["id"] == @event.public_id }
  end

  test "event chat is limited to host and approved participants" do
    other = create_test_user!(email: "outsider-#{SecureRandom.hex(6)}@example.test")
    login_as!(other)

    get "/api/v1/coconique/events/#{@event.public_id}/chat_messages"

    assert_response :forbidden
    assert_equal "EVENT_CHAT_FORBIDDEN", json_body.dig("error", "code")
  end

  test "member profile exposes safe public fields and hosted events" do
    get "/api/v1/coconique/users/#{@host.id}/profile"

    assert_response :success
    profile = json_body.dig("data", "profile")
    assert_equal @host.id.to_s, profile["id"]
    assert profile["displayName"].present?
    assert_not profile.key?("email")
    assert_not profile.key?("fullName")
    assert_equal 1, profile["hostedEventsCount"]
    assert profile["publicHostedEvents"].any? { |event| event["id"] == @event.public_id }
  end


  test "host records attendance after event is finished" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    login_as!(@host)

    patch "/api/v1/coconique/participation_requests/#{request_id}/approve",
      headers: json_headers(csrf_headers)

    assert_response :success

    patch "/api/v1/coconique/events/#{@event.public_id}/finish",
      headers: json_headers(csrf_headers)

    assert_response :success

    get "/api/v1/coconique/events/#{@event.public_id}/participants"

    assert_response :success
    assert_equal "unconfirmed", json_body.dig("data", "participants").first["attendanceStatus"]

    patch "/api/v1/coconique/participation_requests/#{request_id}/attendance",
      params: { attendanceStatus: "attended" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :success
    assert_equal "attended", json_body.dig("data", "participation_request", "attendanceStatus")
    assert json_body.dig("data", "participation_request", "attendanceRecordedAt").present?
  end


  test "past approved event is automatically marked finished on next coconique request" do
    post "/api/v1/coconique/events/#{@event.public_id}/participation_requests",
      params: { message: "参加したいです" }.to_json,
      headers: json_headers(csrf_headers)

    assert_response :created
    request_id = json_body.dig("data", "participation_request", "id")

    login_as!(@host)

    patch "/api/v1/coconique/participation_requests/#{request_id}/approve",
      headers: json_headers(csrf_headers)

    assert_response :success

    @event.update!(
      starts_at: 30.minutes.ago,
      ends_at: 10.minutes.ago,
      recruitment_ends_at: 40.minutes.ago,
      status: :confirmed
    )

    get "/api/v1/coconique/events/#{@event.public_id}/participants"

    assert_response :success
    assert_equal "finished", json_body.dig("data", "event", "status")
    assert_equal "finished", @event.reload.status
  end

  private

  def event_params(title:, publish: true)
    {
      title: title,
      categoryKey: "walk",
      area: "東京都 中野区",
      venueName: "中野セントラルパーク",
      startsAt: 7.days.from_now.iso8601,
      endsAt: (7.days.from_now + 2.hours).iso8601,
      meetingPlace: "中野駅 北口",
      capacity: 4,
      minParticipants: 2,
      recruitmentEndsAt: 6.days.from_now.iso8601,
      summary: "テスト用の予定です。",
      costLabel: "各自負担",
      dressCode: "歩きやすい靴",
      hostMessage: "安心して参加できるように進行します。",
      targetMembers: ["初参加歓迎"],
      publish: publish
    }
  end
end

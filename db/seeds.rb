# db/seeds.rb

current_app_key = ENV.fetch("CURRENT_APP_KEY", "sample_app")

CreditProduct.find_or_create_by!(
  app_key: current_app_key,
  code: "deposit_1000"
) do |product|
  product.name = "デポジット 1,000円"
  product.description = "テスト用デポジット"
  product.amount_jpy = 1000
  product.credits = 1000
  product.active = true
  product.display_order = 1
end

CreditProduct.find_or_create_by!(
  app_key: current_app_key,
  code: "deposit_3000"
) do |product|
  product.name = "デポジット 3,000円"
  product.description = "テスト用デポジット"
  product.amount_jpy = 3000
  product.credits = 3000
  product.active = true
  product.display_order = 2
end

puts "Seed completed for app_key=#{current_app_key}"
# Coconique dashboard / event mock data for local development.
# These records match the initial Vue mock data shape and expose public_id as frontend event id.
coconique_events = [
  {
    public_id: "evt-kamakura-cafe-001",
    title: "神社とカフェをめぐる小さな旅",
    category_key: "walk",
    area: "東京都 世田谷区",
    starts_at: "2026-07-21T10:00:00+09:00",
    ends_at: "2026-07-21T13:30:00+09:00",
    meeting_place: "世田谷線沿線の神社前",
    image_url: "https://images.unsplash.com/photo-1545569341-9eb8b30979d9?auto=format&fit=crop&w=1200&q=80",
    capacity: 4,
    min_participants: 3,
    current_participants: 2,
    interested_count: 12,
    cost_label: "各自飲食代 1,000〜1,800円程度",
    dress_code: "歩きやすい靴・明るめの服装歓迎",
    host_display_name: "ココさん",
    host_age_group: "30代",
    host_message: "静かな神社と小さなカフェをゆっくり巡ります。詳しくない方も歓迎です。",
    summary: "午前中に集合して、混みすぎない道を選びながら散歩とカフェを楽しむ予定です。"
  },
  {
    public_id: "evt-museum-002",
    title: "築地でアートとじっくり楽しむ",
    category_key: "culture",
    area: "東京都 中央区",
    starts_at: "2026-07-24T14:00:00+09:00",
    ends_at: "2026-07-24T16:30:00+09:00",
    meeting_place: "築地駅 改札前",
    image_url: "https://images.unsplash.com/photo-1518998053901-5348d3961a04?auto=format&fit=crop&w=1200&q=80",
    capacity: 5,
    min_participants: 2,
    current_participants: 3,
    interested_count: 18,
    cost_label: "入館料 各自負担",
    dress_code: "ドレスコードなし",
    host_display_name: "みおさん",
    host_age_group: "40代",
    host_message: "作品に詳しくなくても大丈夫です。感じたことを軽く話せたら嬉しいです。",
    summary: "展示をそれぞれのペースで見て、最後にカフェで感想を共有します。"
  },
  {
    public_id: "evt-stadium-003",
    title: "リーダー経験を一緒に話し合おう！",
    category_key: "watching",
    area: "オンライン（Zoom）",
    starts_at: "2026-07-27T19:00:00+09:00",
    ends_at: "2026-07-27T21:00:00+09:00",
    meeting_place: "オンライン（Zoom）",
    image_url: "https://images.unsplash.com/photo-1522778119026-d647f0596c20?auto=format&fit=crop&w=1200&q=80",
    capacity: 6,
    min_participants: 3,
    current_participants: 4,
    interested_count: 29,
    cost_label: "無料",
    dress_code: "リラックスできる服装",
    host_display_name: "さくさん",
    host_age_group: "30代",
    host_message: "仕事や活動の中でのリーダー経験を、ゆるく話し合うオンライン会です。",
    summary: "Zoomで集まり、最近の悩みやうまくいった工夫を共有します。聞くだけ参加も歓迎です。"
  },
  {
    public_id: "evt-book-cafe-004",
    title: "静かなブックカフェで読書タイム",
    category_key: "cafe",
    area: "東京都 文京区",
    starts_at: "2026-07-29T11:00:00+09:00",
    ends_at: "2026-07-29T13:00:00+09:00",
    meeting_place: "茗荷谷駅 1番出口",
    image_url: "https://images.unsplash.com/photo-1526243741027-444d633d7365?auto=format&fit=crop&w=1200&q=80",
    capacity: 4,
    min_participants: 2,
    current_participants: 1,
    interested_count: 21,
    cost_label: "各自飲食代 800〜1,500円程度",
    dress_code: "落ち着いた服装歓迎",
    host_display_name: "ななさん",
    host_age_group: "30代",
    host_message: "読書好き同士で、無理に話しすぎず心地よく過ごせたら嬉しいです。",
    summary: "前半はそれぞれ読書、後半は気になった一文を少しだけ共有します。"
  },
  {
    public_id: "evt-night-walk-005",
    title: "夜景を眺めるゆる散歩",
    category_key: "walk",
    area: "東京都 港区",
    starts_at: "2026-08-01T18:30:00+09:00",
    ends_at: "2026-08-01T20:30:00+09:00",
    meeting_place: "芝公園駅 A4出口",
    image_url: "https://images.unsplash.com/photo-1514565131-fce0801e5785?auto=format&fit=crop&w=1200&q=80",
    capacity: 5,
    min_participants: 3,
    current_participants: 3,
    interested_count: 34,
    cost_label: "無料・カフェ利用時は各自負担",
    dress_code: "歩きやすい靴",
    host_display_name: "アキさん",
    host_age_group: "40代",
    host_message: "安全な大通り中心に、夜景を見ながらゆっくり歩きます。",
    summary: "日が落ちてから集合し、芝公園周辺を無理のない距離で散歩します。"
  },
  {
    public_id: "evt-retro-cinema-006",
    title: "レトロ映画を観て余韻を語る会",
    category_key: "culture",
    area: "東京都 新宿区",
    starts_at: "2026-08-03T15:00:00+09:00",
    ends_at: "2026-08-03T18:30:00+09:00",
    meeting_place: "新宿三丁目駅 C7出口",
    image_url: "https://images.unsplash.com/photo-1485846234645-a62644f84728?auto=format&fit=crop&w=1200&q=80",
    capacity: 4,
    min_participants: 2,
    current_participants: 2,
    interested_count: 16,
    cost_label: "映画チケット代 各自負担",
    dress_code: "ドレスコードなし",
    host_display_name: "レンさん",
    host_age_group: "30代",
    host_message: "詳しい解説よりも、感じたことをゆるく話す会にしたいです。",
    summary: "上映後、近くの喫茶店で30分ほど感想を話す予定です。"
  },
  {
    public_id: "evt-seasonal-fireworks-007",
    title: "小さな花火大会を遠くから眺めよう",
    category_key: "seasonal",
    area: "東京都 江東区",
    starts_at: "2026-08-08T17:30:00+09:00",
    ends_at: "2026-08-08T20:00:00+09:00",
    meeting_place: "豊洲駅 改札前",
    image_url: "https://images.unsplash.com/photo-1533294455009-a77b7557d2d1?auto=format&fit=crop&w=1200&q=80",
    capacity: 6,
    min_participants: 3,
    current_participants: 4,
    interested_count: 42,
    cost_label: "無料・飲み物は各自持参",
    dress_code: "暑さ対策できる服装",
    host_display_name: "ユイさん",
    host_age_group: "30代",
    host_message: "混雑しすぎない場所から、無理なく夏らしさを楽しみたいです。",
    summary: "駅集合後、少し離れた見晴らしの良い場所へ移動します。帰りも駅まで一緒に戻ります。"
  },
  {
    public_id: "evt-tea-salon-008",
    title: "紅茶サロンで午後のおしゃべり",
    category_key: "cafe",
    area: "東京都 渋谷区",
    starts_at: "2026-08-11T14:00:00+09:00",
    ends_at: "2026-08-11T16:00:00+09:00",
    meeting_place: "表参道駅 B2出口",
    image_url: "https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=1200&q=80",
    capacity: 4,
    min_participants: 2,
    current_participants: 2,
    interested_count: 27,
    cost_label: "各自飲食代 1,500〜2,500円程度",
    dress_code: "少しきれいめ歓迎",
    host_display_name: "ハルさん",
    host_age_group: "40代",
    host_message: "おいしい紅茶を飲みながら、最近気になることを軽く話しましょう。",
    summary: "予約可能なお店を候補にしています。人数確定後に席を押さえます。"
  },
  {
    public_id: "evt-online-learning-009",
    title: "学び直しの習慣をつくる作戦会議",
    category_key: "watching",
    area: "オンライン（Zoom）",
    starts_at: "2026-08-13T20:00:00+09:00",
    ends_at: "2026-08-13T21:30:00+09:00",
    meeting_place: "オンライン（Zoom）",
    image_url: "https://images.unsplash.com/photo-1516321318423-f06f85e504b3?auto=format&fit=crop&w=1200&q=80",
    capacity: 8,
    min_participants: 3,
    current_participants: 5,
    interested_count: 38,
    cost_label: "無料",
    dress_code: "カメラOFF参加OK",
    host_display_name: "マコさん",
    host_age_group: "30代",
    host_message: "資格・語学・制作など、続けたい学びを応援し合う会です。",
    summary: "今月やりたいことを小さく決めて、15分だけ集中する時間も作ります。"
  }
]

coconique_events.each do |attrs|
  event = CoconiqueEvent.find_or_initialize_by(public_id: attrs[:public_id])
  event.assign_attributes(attrs.merge(status: :recruiting, published_at: Time.zone.parse(attrs[:starts_at]) - 14.days))
  event.save!
end

puts "Seeded #{coconique_events.length} Coconique events"

# Coconique Step 6-2: Founder β subscription and host ticket products.
CoconiqueBilling.ensure_products!
puts "Seeded Coconique billing products for app_key=#{CoconiqueBilling::APP_KEY}"

class UserProfile < ApplicationRecord
  IDENTITY_GENDER_KEYS = %w[female male other no_answer].freeze

  PUBLIC_AGE_LABELS = %w[
    early_20s
    late_20s
    early_30s
    late_30s
    early_40s
    late_40s
    50s
    60s_or_over
    age_private
    age_unknown
  ].freeze

  CLUB_CATEGORY_KEYS = %w[culture walk watching cafe seasonal].freeze

  PARTICIPATION_STYLE_KEYS = %w[
    small_group
    purpose_first
    quiet_ok
    daytime
    no_alcohol
    same_gender_safe
    local_meetup
    beginner_friendly
  ].freeze

  belongs_to :user

  before_validation :set_defaults
  before_validation :normalize_values

  validates :display_name,
    presence: true,
    length: { minimum: 2, maximum: 40 }

  validates :legal_last_name,
    presence: true,
    length: { maximum: 60 },
    if: :validate_identity_fields?

  validates :legal_first_name,
    presence: true,
    length: { maximum: 60 },
    if: :validate_identity_fields?

  validates :legal_middle_name,
    length: { maximum: 80 },
    allow_blank: true,
    if: :validate_identity_fields?

  validates :legal_last_name_kana,
    presence: true,
    length: { maximum: 60 },
    format: { with: /\A[ァ-ヶー・\s]+\z/, message: "must be full-width katakana" },
    if: :validate_identity_fields?

  validates :legal_first_name_kana,
    presence: true,
    length: { maximum: 60 },
    format: { with: /\A[ァ-ヶー・\s]+\z/, message: "must be full-width katakana" },
    if: :validate_identity_fields?

  validates :legal_middle_name_kana,
    length: { maximum: 80 },
    format: { with: /\A[ァ-ヶー・\s]+\z/, message: "must be full-width katakana" },
    allow_blank: true,
    if: :validate_identity_fields?

  validate :legal_middle_name_kana_required_when_middle_name_present, if: :validate_identity_fields?

  validates :legal_full_name_raw,
    length: { maximum: 180 },
    allow_blank: true,
    if: :validate_identity_fields?

  validates :full_name,
    length: { maximum: 180 },
    allow_blank: true

  validates :locale,
    presence: true,
    inclusion: { in: %w[ja en] }

  validates :timezone,
    presence: true,
    length: { maximum: 80 }

  validates :identity_gender,
    presence: true,
    inclusion: { in: IDENTITY_GENDER_KEYS },
    if: :validate_identity_fields?

  validates :home_prefecture,
    presence: true,
    length: { maximum: 40 },
    if: :validate_identity_fields?

  validates :home_city,
    presence: true,
    length: { maximum: 80 },
    if: :validate_identity_fields?

  validates :public_age_label,
    inclusion: { in: PUBLIC_AGE_LABELS },
    allow_blank: true

  validates :profile_headline,
    length: { maximum: 60 },
    allow_blank: true

  validates :bio,
    length: { maximum: 500 },
    allow_blank: true

  validates :avatar_url,
    length: { maximum: 500_000 },
    allow_blank: true

  validate :public_age_label_is_reasonable_for_birth_date
  validate :json_array_fields_are_reasonable
  validate :club_love_levels_are_reasonable

  private

  def validate_identity_fields?
    validation_context != :public_profile_update
  end

  def set_defaults
    self.locale ||= "ja"
    self.timezone ||= "Asia/Tokyo"
    self.marketing_opt_in = false if marketing_opt_in.nil?
    self.interest_category_keys ||= []
    self.participation_style_keys ||= []
    self.preferred_areas ||= []
    self.conversation_topics ||= []
    self.communication_preferences ||= []
    self.club_love_levels ||= {}
  end

  def normalize_values
    self.display_name = display_name.to_s.strip
    self.legal_last_name = legal_last_name.to_s.strip.presence
    self.legal_first_name = legal_first_name.to_s.strip.presence
    self.legal_middle_name = legal_middle_name.to_s.strip.presence
    self.legal_last_name_kana = normalize_kana_value(legal_last_name_kana).presence
    self.legal_first_name_kana = normalize_kana_value(legal_first_name_kana).presence
    self.legal_middle_name_kana = normalize_kana_value(legal_middle_name_kana).presence
    self.identity_gender = normalize_identity_gender(identity_gender)
    self.home_prefecture = home_prefecture.to_s.strip.presence
    self.home_city = home_city.to_s.strip.presence

    if legal_last_name.blank? && legal_first_name.blank? && full_name.present?
      parts = full_name.to_s.strip.split(/\s+/, 3)
      self.legal_last_name = parts[0].presence
      self.legal_first_name = parts[1].presence
      self.legal_middle_name ||= parts[2].presence
    end

    generated_legal_full_name = [legal_last_name, legal_first_name, legal_middle_name].compact_blank.join(" ")
    self.legal_full_name_raw = legal_full_name_raw.to_s.strip.presence || generated_legal_full_name.presence
    self.full_name = generated_legal_full_name.presence || full_name.to_s.strip.presence
    self.locale = locale.to_s.strip.presence || "ja"
    self.timezone = timezone.to_s.strip.presence || "Asia/Tokyo"
    self.public_age_label = public_age_label.to_s.strip.presence
    self.profile_headline = profile_headline.to_s.strip.presence
    self.bio = bio.to_s.strip.presence
    self.avatar_url = avatar_url.to_s.strip.presence
    self.interest_category_keys = normalize_string_array(interest_category_keys).select { |key| CLUB_CATEGORY_KEYS.include?(key) }.first(5)
    self.participation_style_keys = normalize_string_array(participation_style_keys).select { |key| PARTICIPATION_STYLE_KEYS.include?(key) }.first(6)
    self.preferred_areas = normalize_string_array(preferred_areas).first(5)
    self.conversation_topics = normalize_string_array(conversation_topics).first(8)
    self.communication_preferences = normalize_string_array(communication_preferences).first(6)
    self.club_love_levels = normalize_club_love_levels(club_love_levels)
  end


  def normalize_identity_gender(value)
    key = value.to_s.strip.presence
    return key if IDENTITY_GENDER_KEYS.include?(key)

    nil
  end

  def normalize_kana_value(value)
    value.to_s.strip.tr("ぁ-ん", "ァ-ン").gsub(/[[:space:]]+/, " ")
  end

  def legal_middle_name_kana_required_when_middle_name_present
    return if legal_middle_name.blank? || legal_middle_name_kana.present?

    errors.add(:legal_middle_name_kana, "is required when legal_middle_name is present")
  end

  def normalize_string_array(value)
    Array(value).map { |item| item.to_s.strip }.reject(&:blank?).uniq
  end

  def normalize_club_love_levels(value)
    hash = value.is_a?(Hash) ? value : {}

    CLUB_CATEGORY_KEYS.each_with_object({}) do |key, normalized|
      level = hash[key] || hash[key.to_sym]
      next if level.blank?

      normalized[key] = [[level.to_i, 1].max, 5].min
    end
  end

  def json_array_fields_are_reasonable
    errors.add(:interest_category_keys, "is too long") if interest_category_keys.length > 5
    errors.add(:participation_style_keys, "is too long") if participation_style_keys.length > 6
    errors.add(:preferred_areas, "is too long") if preferred_areas.length > 5
    errors.add(:conversation_topics, "is too long") if conversation_topics.length > 8
    errors.add(:communication_preferences, "is too long") if communication_preferences.length > 6
  end

  def club_love_levels_are_reasonable
    return if club_love_levels.blank?

    invalid_key = club_love_levels.keys.find { |key| !CLUB_CATEGORY_KEYS.include?(key.to_s) }
    errors.add(:club_love_levels, "contains invalid category") if invalid_key.present?
  end

  def public_age_label_is_reasonable_for_birth_date
    return if identity_birth_date.blank? || public_age_label.blank?
    return if allowed_public_age_labels.include?(public_age_label)

    errors.add(:public_age_label, "is too far from identity birth date")
  end

  def allowed_public_age_labels
    always_allowed = %w[age_private age_unknown]
    age = age_from_identity_birth_date
    return always_allowed if age.blank?

    labels = always_allowed.dup
    exact_label = exact_public_age_label_for(age)
    labels << exact_label if exact_label.present?

    PUBLIC_AGE_LABELS.each do |label|
      range = age_range_for_public_age_label(label)
      next if range.blank?

      labels << label if (age - range.first).abs <= 1 || (age - range.last).abs <= 1
    end

    labels.uniq
  end

  def age_from_identity_birth_date
    today = Date.current
    age = today.year - identity_birth_date.year
    age -= 1 if today.month < identity_birth_date.month || (today.month == identity_birth_date.month && today.day < identity_birth_date.day)
    age
  end

  def exact_public_age_label_for(age)
    case age
    when 20..24 then "early_20s"
    when 25..29 then "late_20s"
    when 30..34 then "early_30s"
    when 35..39 then "late_30s"
    when 40..44 then "early_40s"
    when 45..49 then "late_40s"
    when 50..59 then "50s"
    when 60..120 then "60s_or_over"
    end
  end

  def age_range_for_public_age_label(label)
    case label
    when "early_20s" then 20..24
    when "late_20s" then 25..29
    when "early_30s" then 30..34
    when "late_30s" then 35..39
    when "early_40s" then 40..44
    when "late_40s" then 45..49
    when "50s" then 50..59
    when "60s_or_over" then 60..120
    end
  end
end

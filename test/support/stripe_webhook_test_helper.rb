module StripeWebhookTestHelper
  FakeStripeSession = Struct.new(:id, :payment_status, :payment_intent, :subscription, :customer, :invoice, keyword_init: true)
  FakeStripePrice = Struct.new(:id, :recurring, keyword_init: true)
  FakeStripeLine = Struct.new(:price, :period, keyword_init: true)
  FakeStripeLines = Struct.new(:data, keyword_init: true)
  FakeStripeInvoice = Struct.new(
    :id,
    :customer,
    :subscription,
    :payment_intent,
    :amount_paid,
    :currency,
    :billing_reason,
    :period_start,
    :period_end,
    :lines,
    :metadata,
    :subscription_details,
    keyword_init: true
  )
  FakeStripeSubscription = Struct.new(
    :id,
    :customer,
    :status,
    :current_period_start,
    :current_period_end,
    :cancel_at_period_end,
    :cancel_at,
    :canceled_at,
    keyword_init: true
  )

  class FakeStripeEvent
    attr_reader :id, :type, :api_version, :livemode, :data

    def initialize(id:, type:, object:, api_version: "2026-04-22.dahlia", livemode: false)
      @id = id
      @type = type
      @api_version = api_version
      @livemode = livemode
      @data = OpenStruct.new(object: object)
    end

    def to_hash
      {
        id: id,
        type: type,
        api_version: api_version,
        livemode: livemode,
        data: {
          object: object_to_hash(data.object)
        }
      }
    end

    private

    def object_to_hash(object)
      if object.respond_to?(:to_h)
        object.to_h.transform_values { |value| object_to_hash_value(value) }.compact
      else
        {}
      end
    end

    def object_to_hash_value(value)
      case value
      when Array
        value.map { |item| object_to_hash_value(item) }
      when Struct
        object_to_hash(value)
      when OpenStruct
        value.to_h.transform_values { |item| object_to_hash_value(item) }
      else
        value
      end
    end
  end

  def stub_stripe_event(event, &block)
    replace_stripe_construct_event(
      ->(*_args) { event },
      &block
    )
  end

  def stub_stripe_construct_event_error(error, &block)
    replace_stripe_construct_event(
      ->(*_args) { raise error },
      &block
    )
  end

  private

  def replace_stripe_construct_event(replacement)
    singleton_class = class << Stripe::Webhook; self; end
    original_method = Stripe::Webhook.method(:construct_event)

    singleton_class.define_method(:construct_event) do |*args|
      replacement.call(*args)
    end

    yield
  ensure
    singleton_class.define_method(:construct_event) do |*args|
      original_method.call(*args)
    end
  end
end

module StripeWebhookTestHelper
  FakeStripeSession = Struct.new(:id, :payment_status, :payment_intent, keyword_init: true)

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
          object: {
            id: data.object.id,
            payment_status: data.object.payment_status,
            payment_intent: data.object.payment_intent
          }
        }
      }
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
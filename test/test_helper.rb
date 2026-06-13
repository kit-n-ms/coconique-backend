ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"
require "securerandom"
require "ostruct"

Dir[Rails.root.join("test/support/**/*.rb")].sort.each { |file| require file }

class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)
  # fixtures :all
end

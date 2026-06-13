# config/initializers/cors.rb

allowed_origins = ENV.fetch(
  "CORS_ALLOWED_ORIGINS",
  "http://localhost:5173,http://127.0.0.1:5173"
).split(",").map(&:strip)

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*allowed_origins)

    resource "*",
      headers: :any,
      methods: [:get, :post, :patch, :put, :delete, :options, :head],
      credentials: true
  end
end
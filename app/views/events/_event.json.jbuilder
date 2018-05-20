json.extract! event, :id, :title, :date, :body, :admin_token, :created_at, :updated_at
json.url event_url(event, format: :json)

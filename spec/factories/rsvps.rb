FactoryBot.define do
  factory :rsvp do
    event
    sequence(:name) { |n| "Guest #{n}" }
    response { 'yes' }
  end
end

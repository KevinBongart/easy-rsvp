FactoryBot.define do
  factory :event do
    sequence(:title) { |n| "Garden party #{n}" }
    date { Date.current + 7.days }
    body { '<div>Bring something to share.</div>' }

    trait :unpublished do
      published { false }
    end

    trait :private_names do
      show_rsvp_names { false }
    end

    trait :timed do
      time_zone { 'Europe/Paris' }
      starts_at { Time.find_zone(time_zone).local(date.year, date.month, date.day, 18, 0) }
      ends_at { Time.find_zone(time_zone).local(date.year, date.month, date.day, 21, 0) }
    end
  end
end

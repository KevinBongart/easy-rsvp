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
  end
end

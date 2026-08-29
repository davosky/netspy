FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "user#{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    first_name { "Mario" }
    last_name { "Rossi" }

    trait :admin do
      admin { true }
    end

    trait :manager do
      manager { true }
    end

    trait :regular do
      regular { true }
    end
  end
end

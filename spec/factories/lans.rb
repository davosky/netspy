FactoryBot.define do
  factory :lan do
    sequence(:lan) { |n| "10.#{n / 254 % 254}.#{n % 254}.0/24" }
    ports { "1-1024" }
    timeout { 600 }
    primary { true }
    secondary { false }
    remote_client_ip { nil }
    remote_user { nil }
    binpath { nil }

    trait :primary do
      primary { true }
      secondary { false }
      remote_client_ip { nil }
      remote_user { nil }
    end

    trait :secondary do
      primary { false }
      secondary { true }
      remote_client_ip { "10.20.30.40" }
      remote_user { "netspy" }
    end
  end
end

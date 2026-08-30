FactoryBot.define do
  factory :lanscan do
    scanned_at { Time.current }
    target { "192.168.1.0/24" }
    sequence(:ip_address) { |n| "192.168.1.#{(n % 253) + 1}" }
    mac_address { "aa:bb:cc:dd:ee:ff" }
    open_ports { "22 80 443" }

    trait :no_mac do
      mac_address { nil }
    end
  end
end

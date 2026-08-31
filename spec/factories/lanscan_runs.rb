FactoryBot.define do
  factory :lanscan_run do
    association :lan, :primary
    target { "192.168.1.0/24" }
    ports { "1-1024" }
    timeout { 700 }
    status { "pending" }
    total_probes { 262_144 }
    hosts_found { 0 }

    trait :running do
      status { "running" }
      started_at { 30.seconds.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 2.minutes.ago }
      finished_at { 1.minute.ago }
      hosts_found { 4 }
    end

    trait :failed do
      status { "failed" }
      started_at { 2.minutes.ago }
      finished_at { 1.minute.ago }
      error_message { "boom" }
    end
  end
end

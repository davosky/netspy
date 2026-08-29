# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# First administrator. Credentials come exclusively from the environment
# (.env / ADMIN_*) so nothing sensitive lives in the repo.
if ENV["ADMIN_USERNAME"].present?
  admin = User.find_or_initialize_by(username: ENV.fetch("ADMIN_USERNAME"))

  admin.assign_attributes(
    email: ENV.fetch("ADMIN_EMAIL"),
    first_name: ENV["ADMIN_FIRST_NAME"],
    last_name: ENV["ADMIN_LAST_NAME"],
    gender: ENV["ADMIN_GENDER"],
    region: ENV["ADMIN_REGION"],
    province: ENV["ADMIN_PROVINCE"],
    category: ENV["ADMIN_CATEGORY"],
    admin: ActiveModel::Type::Boolean.new.cast(ENV.fetch("ADMIN_ADMIN", true))
  )
  admin.password = ENV.fetch("ADMIN_PASSWORD") if admin.new_record?
  admin.save!

  puts "Seeded admin user '#{admin.username}' (admin: #{admin.admin})."
else
  puts "ADMIN_USERNAME not set - skipping admin seed."
end

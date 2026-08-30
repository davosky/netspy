class User < ApplicationRecord
  # Devise handles password authentication; NetSpy signs in by username.
  # :validatable covers email presence/format/uniqueness and password length.
  # :registerable is intentionally omitted: only admins may create users (see Admin::UsersController).
  devise :database_authenticatable, :recoverable,
         :rememberable, :validatable, :lockable

  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { minimum: 3, maximum: 50 },
            format: { with: /\A[a-zA-Z0-9._-]+\z/ }

  def display_name
    [ first_name, last_name ].compact_blank.join(" ").presence || username
  end

  # Case-insensitive lookup so "Davo" and "davo" resolve to the same account.
  def self.find_for_database_authentication(conditions)
    login = conditions[:username].to_s.strip.downcase
    find_by("LOWER(username) = ?", login)
  end
end

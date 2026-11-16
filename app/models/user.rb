# Local profile for a HERGA Active Directory user.
#
# The User record supports Devise session persistence.
# Passwords are never stored or checked locally.

class User < ApplicationRecord
  # Devise manages session expiration.
  #
  # Database password authentication is deliberately
  # excluded.
  devise :timeoutable

  # Each AD username must have one local record.
  validates :username,
            presence: true,
            uniqueness: { case_sensitive: false }

  # Normalise usernames before validation.
  before_validation :normalise_username

  private

  def normalise_username
    self.username = username.to_s.strip.downcase
  end
end
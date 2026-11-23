# frozen_string_literal: true

module Infrastructure
  class NotificationLegalHoldManager
    class ReleaseDenied < StandardError; end

    def initialize(actor:)
      @actor = actor.to_s.strip
      raise ArgumentError, "Administrator identity required" if @actor.blank?
    end

    def release!(hold:, justification:)
      reason = justification.to_s.strip
      raise ReleaseDenied, "Release justification is required" if reason.blank?

      hold.with_lock do
        raise ReleaseDenied, "Legal hold is already released" unless hold.active?
        creator = hold.placed_by.to_s.strip
        raise ReleaseDenied, "Hold creator identity is missing" if creator.blank?
        if creator.casecmp?(@actor)
          raise ReleaseDenied, "Separation of duties: creator cannot release their own hold"
        end

        hold.update!(released_by: @actor, released_at: Time.current)
        Infrastructure::NotificationLegalHoldEvent.create!(
          notification_legal_hold: hold, action: "Released", actor: @actor,
          justification: reason, created_at: Time.current
        )
      end
      hold
    end
  end
end

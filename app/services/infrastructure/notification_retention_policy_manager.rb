# frozen_string_literal: true

module Infrastructure
  # Explicit, auditable transitions. No delete/archive action exists here.
  class NotificationRetentionPolicyManager
    class InvalidTransition < StandardError; end

    def initialize(actor:)
      @actor = actor.to_s.strip
      raise ArgumentError, "Actor is required" if @actor.blank?
    end

    def create!(name:, reference:, retention_days:)
      NotificationRetentionPolicy.transaction do
        policy = NotificationRetentionPolicy.create!(
          name: name, reference: reference, retention_days: retention_days,
          status: "Draft", version: 1
        )
        record!(policy, "Created", nil)
        policy
      end
    end

    def approve!(policy:, approval_reference:)
      raise ArgumentError, "Approval reference is required" if approval_reference.to_s.strip.blank?
      transition!(policy, from: "Draft", to: "Approved", action: "Approved") do |locked|
        # Approval reference must match the independently controlled policy reference.
        raise InvalidTransition, "Approval reference mismatch" unless locked.reference == approval_reference.to_s.strip
        locked.approved_by = @actor
        locked.approved_at = Time.current
      end
    end

    def suspend!(policy:)
      transition!(policy, from: "Approved", to: "Suspended", action: "Suspended") do |locked|
        locked.suspended_by = @actor
        locked.suspended_at = Time.current
      end
    end

    private

    def transition!(policy, from:, to:, action:)
      policy.with_lock do
        raise InvalidTransition, "Expected #{from}; got #{policy.status}" unless policy.status == from
        previous = policy.status
        yield policy
        policy.status = to
        policy.version += 1
        policy.save!
        record!(policy, action, previous)
      end
      policy
    end

    def record!(policy, action, previous)
      policy.events.create!(
        action: action, actor: @actor, from_status: previous,
        to_status: policy.status, policy_version: policy.version,
        created_at: Time.current
      )
    end
  end
end

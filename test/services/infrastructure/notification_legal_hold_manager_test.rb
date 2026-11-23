# frozen_string_literal: true
require "test_helper"

module Infrastructure
  class NotificationLegalHoldManagerTest < ActiveSupport::TestCase
    def build_hold(creator: "creator")
      NotificationLegalHold.new(placed_by: creator, placed_at: Time.current)
    end

    test "rejects blank actor" do
      assert_raises(ArgumentError) { NotificationLegalHoldManager.new(actor: " ") }
    end

    test "rejects blank justification before database access" do
      assert_raises(NotificationLegalHoldManager::ReleaseDenied) do
        NotificationLegalHoldManager.new(actor: "reviewer").release!(hold: build_hold, justification: " ")
      end
    end

    test "refuses creator as reviewer, case insensitive" do
      hold = build_hold(creator: "Admin.One")
      def hold.with_lock
        yield
      end
      assert_raises(NotificationLegalHoldManager::ReleaseDenied) do
        NotificationLegalHoldManager.new(actor: "admin.one").release!(hold: hold, justification: "Case closed")
      end
    end

    test "rejects already released hold" do
      hold = build_hold
      hold.released_at = Time.current
      def hold.with_lock
        yield
      end
      assert_raises(NotificationLegalHoldManager::ReleaseDenied) do
        NotificationLegalHoldManager.new(actor: "reviewer").release!(hold: hold, justification: "Case closed")
      end
    end
  end
end

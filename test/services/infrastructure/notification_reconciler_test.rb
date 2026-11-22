# frozen_string_literal: true

require "test_helper"

class InfrastructureNotificationReconcilerTest < ActiveSupport::TestCase
  test "notifications are disabled without an activation timestamp" do
    previous_enabled = ENV["HERGA_NOTIFICATIONS_ENABLED"]
    previous_start = ENV["HERGA_NOTIFICATIONS_START_AT"]
    ENV["HERGA_NOTIFICATIONS_ENABLED"] = "true"
    ENV.delete("HERGA_NOTIFICATIONS_START_AT")

    assert_not Infrastructure::NotificationSettings.enabled?
    assert_equal({ enabled: false, created: 0 }, Infrastructure::NotificationReconciler.new.call)
  ensure
    ENV["HERGA_NOTIFICATIONS_ENABLED"] = previous_enabled
    ENV["HERGA_NOTIFICATIONS_START_AT"] = previous_start
  end

  test "notification recipient is the configured HERGA mailbox" do
    assert_equal "info@hergafarmsgroup.com", Infrastructure::NotificationSettings::RECIPIENT
  end
end

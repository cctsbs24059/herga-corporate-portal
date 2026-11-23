# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class NotificationGovernanceEvidenceBundleTest < ActiveSupport::TestCase
    FakeReport = Class.new do
      MAX_ROWS_PER_SECTION = 5_000
      SECTIONS = %w[summary policies policy_events legal_holds legal_hold_events].freeze

      def csv(section:)
        "id,value\n1,#{section}\n"
      end

      def section_counts
        { "policies" => 2, "policy_events" => 1, "legal_holds" => 1, "legal_hold_events" => 1 }
      end
    end

    test "builds verifiable bundle with explicit truncation" do
      bytes = NotificationGovernanceEvidenceBundle.new(report: FakeReport.new).build
      manifest = NotificationGovernanceEvidenceBundle.verify(bytes)
      assert_equal 1, manifest.fetch("format_version")
      assert_equal 5, manifest.fetch("sections").length
      assert_equal true, manifest.fetch("sections")[1].fetch("truncated")
    end

    test "rejects malformed archives" do
      assert_raises(NotificationGovernanceEvidenceBundle::VerificationError) do
        NotificationGovernanceEvidenceBundle.verify("invalid archive")
      end
    end
  end
end

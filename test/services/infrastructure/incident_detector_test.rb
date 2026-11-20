
# frozen_string_literal: true

require "test_helper"

class Infrastructure::IncidentDetectorTest < ActiveSupport::TestCase
  setup do
    @asset = InfrastructureAsset.create!(
      hostname: "HERGA-INCIDENT-TEST",
      asset_type: "Windows Server",
      environment: "Test",
      status: "Active",
      source: "Manual"
    )

    @base_time = Time.current.change(usec: 0)
  end

  # ------------------------------------------------------------
  # TEST 1: Incident threshold
  # ------------------------------------------------------------

  test "does not create an incident before three consecutive failures" do
    2.times do |index|
      check = create_check(
        "Unreachable",
        at: @base_time + index.minutes
      )

      detect(check)
    end

    assert_equal 0, incidents.count
  end

  # ------------------------------------------------------------
  # TEST 2: Automatic incident creation
  # ------------------------------------------------------------

  test "creates a critical incident after three consecutive failures" do
    create_failure_sequence

    assert_equal 1, incidents.count

    incident = incidents.first

    assert_equal "Open", incident.status
    assert_equal "Critical", incident.severity
    assert_equal InfrastructureIncident::TYPE_ICMP,
                 incident.incident_type
    assert_equal 3, incident.consecutive_failures

    assert_equal 1, event_count(incident, "Created")
  end

  # ------------------------------------------------------------
  # TEST 3: Duplicate incident prevention
  # ------------------------------------------------------------

  test "does not create duplicate unresolved incidents" do
    5.times do |index|
      detect(
        create_check(
          "Unreachable",
          at: @base_time + index.minutes
        )
      )
    end

    assert_equal 1, incidents.count
    assert_equal 1, incidents.where(status: "Open").count
    assert_equal 5, incidents.first.consecutive_failures

    assert_equal 1, event_count(incidents.first, "Created")
  end

  # ------------------------------------------------------------
  # TEST 4: Automatic recovery
  # ------------------------------------------------------------

  test "automatically resolves an incident after successful connectivity" do
    create_failure_sequence

    incident = incidents.first

    detect(
      create_check(
        "Reachable",
        at: @base_time + 4.minutes
      )
    )

    incident.reload

    assert_equal "Resolved", incident.status
    assert_equal "Connectivity restored",
                 incident.resolution_reason
    assert_not_nil incident.resolved_at
    assert_not incident.suppress_until_recovery?

    assert_equal 1, event_count(incident, "Recovered")
  end

  # ------------------------------------------------------------
  # TEST 5: Manual resolution suppression
  # ------------------------------------------------------------

  test "manual resolution suppresses further incidents while unreachable" do
    create_failure_sequence

    incident = incidents.first

    manually_resolve(incident)

    3.times do |index|
      detect(
        create_check(
          "Unreachable",
          at: @base_time + (index + 4).minutes
        )
      )
    end

    assert_equal 1, incidents.count
    assert_equal 0, incidents.where(status: "Open").count
    assert incident.reload.suppress_until_recovery?
  end

  # ------------------------------------------------------------
  # TEST 6: Suppression cleared by recovery
  # ------------------------------------------------------------

  test "successful connectivity clears manual suppression" do
    create_failure_sequence

    incident = incidents.first

    manually_resolve(incident)

    assert incident.reload.suppress_until_recovery?

    detect(
      create_check(
        "Reachable",
        at: @base_time + 4.minutes
      )
    )

    assert_not incident.reload.suppress_until_recovery?
    assert_equal 1, incidents.count
    assert_equal 0, incidents.where(status: "Open").count
  end

  # ------------------------------------------------------------
  # TEST 7: New incident after recovery
  # ------------------------------------------------------------

  test "creates a new incident after recovery and three new failures" do
    create_failure_sequence

    original = incidents.first

    manually_resolve(original)

    detect(
      create_check(
        "Reachable",
        at: @base_time + 4.minutes
      )
    )

    assert_not original.reload.suppress_until_recovery?

    3.times do |index|
      detect(
        create_check(
          "Unreachable",
          at: @base_time + (index + 5).minutes
        )
      )
    end

    assert_equal 2, incidents.count
    assert_equal 1, incidents.where(status: "Open").count
    assert_equal 1, incidents.where(status: "Resolved").count

    new_incident = incidents.find_by!(status: "Open")

    assert_not_equal original.id, new_incident.id
    assert_equal "Critical", new_incident.severity
    assert_equal 3, new_incident.consecutive_failures
    assert_equal 1, event_count(new_incident, "Created")
  end

  # ------------------------------------------------------------
  # TEST 8: Ignore outdated monitoring results
  # ------------------------------------------------------------

  test "ignores outdated monitoring results" do
    old_check = create_check(
      "Unreachable",
      at: @base_time
    )

    create_check(
      "Reachable",
      at: @base_time + 1.minute
    )

    detect(old_check)

    assert_equal 0, incidents.count
    assert_equal 0, InfrastructureIncidentEvent.count
  end

  # ------------------------------------------------------------
  # TEST 9: Retired asset handling
  # ------------------------------------------------------------

  test "retired asset resolves an existing incident" do
    create_failure_sequence

    incident = incidents.first

    @asset.update!(status: "Retired")

    detect(
      create_check(
        "Unreachable",
        at: @base_time + 4.minutes
      )
    )

    incident.reload

    assert_equal "Resolved", incident.status
    assert_equal "Asset retired", incident.resolution_reason
    assert_not_nil incident.resolved_at

    assert_equal 1, event_count(incident, "Retired")
  end

  private

  # ------------------------------------------------------------
  # Helper: Create an ICMP connectivity result
  # ------------------------------------------------------------

  def create_check(status, at:)
    InfrastructureConnectivityResult.create!(
      infrastructure_asset: @asset,
      icmp_status: status,
      checked_at: at
    )
  end

  # ------------------------------------------------------------
  # Helper: Execute the incident detector
  # ------------------------------------------------------------

  def detect(check)
    Infrastructure::IncidentDetector.new(
      @asset,
      connectivity_result: check
    ).call
  end

  # ------------------------------------------------------------
  # Helper: Query incidents belonging to the test asset
  # ------------------------------------------------------------

  def incidents
    InfrastructureIncident.where(
      infrastructure_asset_id: @asset.id
    )
  end

  # ------------------------------------------------------------
  # Helper: Query incident audit events
  # ------------------------------------------------------------

  def event_count(incident, event_type)
    InfrastructureIncidentEvent.where(
      infrastructure_incident_id: incident.id,
      event_type: event_type
    ).count
  end

  # ------------------------------------------------------------
  # Helper: Simulate three consecutive ICMP failures
  # ------------------------------------------------------------

  def create_failure_sequence
    Infrastructure::HealthEvaluator::CRITICAL_FAILURE_COUNT.times do |index|
      detect(
        create_check(
          "Unreachable",
          at: @base_time + index.minutes
        )
      )
    end
  end

  # ------------------------------------------------------------
  # Helper: Simulate manual incident resolution
  # ------------------------------------------------------------

  def manually_resolve(incident)
    incident.update!(
      status: "Resolved",
      resolved_at: Time.current,
      resolution_reason: "Manually resolved",
      suppress_until_recovery: true
    )
  end
end

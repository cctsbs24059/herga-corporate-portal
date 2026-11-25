# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "csv"
require "digest"

class NotificationGovernanceEvidenceSecurityTest <
  ActionDispatch::IntegrationTest

  include Devise::Test::IntegrationHelpers

  ComplianceReport =
    Infrastructure::NotificationGovernanceComplianceReport

  EvidenceBundle =
    Infrastructure::NotificationGovernanceEvidenceBundle

  SECTIONS = %w[
    summary
    policies
    policy_events
    legal_holds
    legal_hold_events
  ].freeze

  AUTHORISED_ROLES = {
    portal_administrator: [:portal_admin],
    security_administrator: [:security_admin],
    auditor: [:auditor],
    multi_role_auditor: [
      :infrastructure_admin,
      :auditor
    ]
  }.freeze

  DENIED_ROLES = {
    infrastructure_administrator: [:infrastructure_admin],
    employee: [:employee],
    multi_role_employee: [
      :infrastructure_admin,
      :employee
    ]
  }.freeze

  setup do
    @user = User.create!(
      username: "evidence-rbac-#{SecureRandom.hex(8)}",
      admin: false
    )
  end

  teardown do
    sign_out @user
  end

  # ==========================================================
  # SECTION A - AUTHORISED COMPLIANCE DASHBOARD ACCESS
  # ==========================================================

  AUTHORISED_ROLES.each do |label, roles|

    test "#{label} can access compliance dashboard" do
      as_roles(roles) do
        get infrastructure_notification_governance_compliance_path

        assert_response :success

        assert_select "#notification-governance-compliance"
      end
    end

  end

  # ==========================================================
  # SECTION B - UNAUTHORISED COMPLIANCE DASHBOARD ACCESS
  # ==========================================================

  DENIED_ROLES.each do |label, roles|

    test "#{label} cannot access compliance dashboard" do
      as_roles(roles) do
        get infrastructure_notification_governance_compliance_path

        assert_redirected_to root_path

        assert_no_attachment
      end
    end

  end

  # ==========================================================
  # SECTION C - AUTHORISED CSV EXPORTS
  # ==========================================================

  AUTHORISED_ROLES.each do |label, roles|

    SECTIONS.each do |section|

      test "#{label} can export #{section} CSV" do
        as_roles(roles) do
          get csv_path(section)

          assert_csv_response(section)
        end
      end

    end

  end

  # ==========================================================
  # SECTION D - UNAUTHORISED DIRECT CSV EXPORTS
  # ==========================================================

  DENIED_ROLES.each do |label, roles|

    SECTIONS.each do |section|

      test "#{label} cannot export #{section} CSV" do
        as_roles(roles) do
          get csv_path(section)

          assert_redirected_to root_path

          assert_no_attachment
        end
      end

    end

  end

  # ==========================================================
  # SECTION E - AUTHORISED EVIDENCE ARCHIVE DOWNLOADS
  # ==========================================================

  AUTHORISED_ROLES.each do |label, roles|

    test "#{label} can download governance evidence archive" do
      as_roles(roles) do
        get evidence_bundle_path

        assert_bundle_response
      end
    end

  end

  # ==========================================================
  # SECTION F - UNAUTHORISED EVIDENCE ARCHIVE DOWNLOADS
  # ==========================================================

  DENIED_ROLES.each do |label, roles|

    test "#{label} cannot download governance evidence archive" do
      as_roles(roles) do
        get evidence_bundle_path

        assert_redirected_to root_path

        assert_no_attachment
      end
    end

  end

  # ==========================================================
  # SECTION G - EXPORT SECTION VALIDATION
  # ==========================================================

  AUTHORISED_ROLES.each do |label, roles|

    test "#{label} cannot export unsupported section" do
      as_roles(roles) do
        get csv_path("unsupported")

        assert_response :bad_request

        assert_no_attachment
      end
    end

  end

  test "unauthorised user is rejected before section validation" do
    as_roles([:employee]) do
      get csv_path("unsupported")

      assert_redirected_to root_path

      assert_no_attachment
    end
  end

  test "export section identifiers are case sensitive" do
    as_roles([:auditor]) do
      get csv_path("SUMMARY")

      assert_response :bad_request

      assert_no_attachment
    end
  end

  # ==========================================================
  # SECTION H - DIRECTORY FAILURE AND FAIL-CLOSED ACCESS
  # ==========================================================

  {
    unavailable_directory: nil,
    empty_roles: [],
    unknown_role: [:unknown_role]
  }.each do |label, roles|

    test "#{label} prevents compliance dashboard access" do
      as_roles(roles) do
        get infrastructure_notification_governance_compliance_path

        assert_redirected_to new_user_session_path

        assert_no_attachment
      end
    end

    SECTIONS.each do |section|

      test "#{label} prevents #{section} CSV export" do
        as_roles(roles) do
          get csv_path(section)

          assert_redirected_to new_user_session_path

          assert_no_attachment
        end
      end

    end

    test "#{label} prevents evidence archive download" do
      as_roles(roles) do
        get evidence_bundle_path

        assert_redirected_to new_user_session_path

        assert_no_attachment
      end
    end

  end

  # ==========================================================
  # SECTION I - LOCAL ADMINISTRATOR BYPASS PREVENTION
  # ==========================================================

  test "local administrator flag cannot grant dashboard access" do
    @user.update!(admin: true)

    as_roles([:employee]) do
      get infrastructure_notification_governance_compliance_path

      assert_redirected_to root_path
    end
  end

  SECTIONS.each do |section|

    test "local administrator flag cannot grant #{section} export" do
      @user.update!(admin: true)

      as_roles([:employee]) do
        get csv_path(section)

        assert_redirected_to root_path

        assert_no_attachment
      end
    end

  end

  test "local administrator flag cannot grant archive download" do
    @user.update!(admin: true)

    as_roles([:employee]) do
      get evidence_bundle_path

      assert_redirected_to root_path

      assert_no_attachment
    end
  end

  test "local administrator flag cannot override directory failure" do
    @user.update!(admin: true)

    as_roles(nil) do
      get evidence_bundle_path

      assert_redirected_to new_user_session_path

      assert_no_attachment
    end
  end

  test "auditor does not require local administrator flag" do
    assert_equal false, @user.admin

    as_roles([:auditor]) do
      get csv_path("summary")

      assert_csv_response("summary")

      get evidence_bundle_path

      assert_bundle_response
    end
  end

  # ==========================================================
  # SECTION J - UNAUTHENTICATED REQUESTS
  # ==========================================================

  test "guest cannot access compliance dashboard" do
    get infrastructure_notification_governance_compliance_path

    assert_redirected_to new_user_session_path
  end

  SECTIONS.each do |section|

    test "guest cannot export #{section} CSV" do
      get csv_path(section)

      assert_redirected_to new_user_session_path

      assert_no_attachment
    end

  end

  test "guest cannot download evidence archive" do
    get evidence_bundle_path

    assert_redirected_to new_user_session_path

    assert_no_attachment
  end

  # ==========================================================
  # SECTION K - LIVE PERMISSION REVOCATION
  # ==========================================================

  test "CSV permission revocation takes effect on next request" do
    sign_in @user

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      [:auditor]
    ) do
      get csv_path("summary")

      assert_csv_response("summary")
    end

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      [:employee]
    ) do
      get csv_path("summary")

      assert_redirected_to root_path

      assert_no_attachment
    end
  end

  test "archive permission revocation takes effect on next request" do
    sign_in @user

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      [:auditor]
    ) do
      get evidence_bundle_path

      assert_bundle_response
    end

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      [:infrastructure_admin]
    ) do
      get evidence_bundle_path

      assert_redirected_to root_path

      assert_no_attachment
    end
  end

  test "directory outage terminates previously authorised session" do
    sign_in @user

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      [:auditor]
    ) do
      get csv_path("summary")

      assert_csv_response("summary")
    end

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      nil
    ) do
      get evidence_bundle_path

      assert_redirected_to new_user_session_path

      assert_no_attachment
    end

    # Directory recovery alone must not restore a
    # session that has already been terminated.

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      [:auditor]
    ) do
      get csv_path("summary")

      assert_redirected_to new_user_session_path
    end
  end

  test "directory roles are resolved once per evidence request" do
    sign_in @user

    calls = 0

    resolver = lambda do |username|
      calls += 1

      assert_equal @user.username, username

      [:auditor]
    end

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      resolver
    ) do
      get csv_path("summary")

      assert_csv_response("summary")

      assert_equal 1, calls

      get evidence_bundle_path

      assert_bundle_response

      assert_equal 2, calls
    end
  end

  # ==========================================================
  # SECTION L - GOVERNANCE INTERFACE SECURITY
  # ==========================================================

  AUTHORISED_ROLES.each do |label, roles|

    test "#{label} sees authorised evidence export controls" do
      as_roles(roles) do
        get infrastructure_notification_governance_compliance_path

        assert_response :success

        assert_select(
          "a[href='#{evidence_bundle_path}']",
          minimum: 1
        )

        SECTIONS.each do |section|
          assert_select(
            "a[href='#{csv_path(section)}']",
            minimum: 1
          )
        end
      end
    end

  end

  # ==========================================================
  # SECTION M - HTTP RESPONSE CONFIDENTIALITY
  # ==========================================================

  SECTIONS.each do |section|

    test "#{section} CSV response prevents caching" do
      as_roles([:auditor]) do
        get csv_path(section)

        assert_response :success

        assert_cache_protection
      end
    end

  end

  test "evidence archive response prevents caching" do
    as_roles([:auditor]) do
      get evidence_bundle_path

      assert_response :success

      assert_cache_protection
    end
  end

  test "invalid export response prevents caching" do
    as_roles([:auditor]) do
      get csv_path("unsupported")

      assert_response :bad_request

      assert_cache_protection
    end
  end

  test "denied evidence response prevents caching" do
    as_roles([:employee]) do
      get evidence_bundle_path

      assert_redirected_to root_path

      assert_cache_protection
    end
  end

  # ==========================================================
  # SECTION N - EXPORT GENERATION SECURITY BOUNDARY
  # ==========================================================

  test "unauthorised CSV request never constructs report" do
    as_roles([:employee]) do

      forbidden_constructor = lambda do |*args, **kwargs|
        flunk "Unauthorised request constructed compliance report"
      end

      ComplianceReport.stub(
        :new,
        forbidden_constructor
      ) do
        get csv_path("summary")

        assert_redirected_to root_path
      end
    end
  end

  test "unauthorised archive request never constructs bundle" do
    as_roles([:infrastructure_admin]) do

      forbidden_constructor = lambda do |*args, **kwargs|
        flunk "Unauthorised request constructed evidence bundle"
      end

      EvidenceBundle.stub(
        :new,
        forbidden_constructor
      ) do
        get evidence_bundle_path

        assert_redirected_to root_path
      end
    end
  end

  test "invalid section never constructs compliance report" do
    as_roles([:auditor]) do

      forbidden_constructor = lambda do |*args, **kwargs|
        flunk "Invalid export section constructed compliance report"
      end

      ComplianceReport.stub(
        :new,
        forbidden_constructor
      ) do
        get csv_path("unsupported")

        assert_response :bad_request
      end
    end
  end

  # ==========================================================
  # SECTION O - GOVERNANCE RECORD INTEGRITY
  # ==========================================================

  test "CSV exports do not modify governance records" do
    as_roles([:auditor]) do

      before = governance_snapshot

      SECTIONS.each do |section|
        get csv_path(section)

        assert_csv_response(section)
      end

      assert_equal before, governance_snapshot
    end
  end

  test "archive generation does not modify governance records" do
    as_roles([:auditor]) do

      before = governance_snapshot

      get evidence_bundle_path

      assert_bundle_response

      assert_equal before, governance_snapshot
    end
  end

  # ==========================================================
  # TEST HELPERS
  # ==========================================================

  private

  def as_roles(roles)
    sign_in @user

    ActiveDirectoryAuthenticator.stub(
      :current_roles,
      roles
    ) do
      yield
    end
  end

  def csv_path(section)
    infrastructure_notification_governance_compliance_export_path(
      section: section
    )
  end

  def evidence_bundle_path
    infrastructure_notification_governance_evidence_bundle_path
  end

  def assert_csv_response(section)
    assert_response :success

    assert_equal "text/csv", response.media_type

    disposition = response.headers.fetch(
      "Content-Disposition",
      ""
    )

    assert_includes disposition, "attachment"

    assert_match(
      /herga-governance-#{Regexp.escape(section)}-\d{8}T\d{6}Z\.csv/,
      disposition
    )

    assert_operator response.body.bytesize, :>, 0

    rows = CSV.parse(response.body, headers: true)

    assert_kind_of CSV::Table, rows

    assert_equal expected_headers(section), rows.headers
  end

  def assert_bundle_response
    assert_response :success

    assert_equal "application/gzip", response.media_type

    disposition = response.headers.fetch(
      "Content-Disposition",
      ""
    )

    assert_includes disposition, "attachment"

    assert_match(
      /herga-governance-evidence-\d{8}T\d{6}Z\.tar\.gz/,
      disposition
    )

    assert_operator response.body.bytesize, :>, 0

    manifest = EvidenceBundle.verify(response.body)

    assert_equal(
      SECTIONS,
      manifest.fetch("sections").map do |section|
        section.fetch("section")
      end
    )
  end

  def assert_no_attachment
    disposition = response.headers.fetch(
      "Content-Disposition",
      ""
    )

    refute_includes disposition, "attachment"

    refute_equal "text/csv", response.media_type

    refute_equal "application/gzip", response.media_type
  end

  def assert_cache_protection
    cache_control = response.headers.fetch(
      "Cache-Control",
      ""
    )

    assert_includes(
      cache_control.split(",").map(&:strip),
      "no-store"
    )

    assert_equal(
      "no-cache",
      response.headers["Pragma"]
    )

    assert_equal(
      "nosniff",
      response.headers["X-Content-Type-Options"]
    )
  end

  def expected_headers(section)
    {
      "summary" => %w[
        metric value assessed_at
      ],

      "policies" => %w[
        id reference name status retention_days version
        approved_by approved_at suspended_by suspended_at
        created_at
      ],

      "policy_events" => %w[
        id policy_id action actor from_status to_status
        policy_version created_at
      ],

      "legal_holds" => %w[
        id notification_id reference reason placed_by
        placed_at released_by released_at
      ],

      "legal_hold_events" => %w[
        id legal_hold_id action actor justification
        created_at
      ]
    }.fetch(section)
  end

  def governance_snapshot
    [
      Infrastructure::NotificationRetentionPolicy,
      Infrastructure::NotificationRetentionEvent,
      Infrastructure::NotificationLegalHold,
      Infrastructure::NotificationLegalHoldEvent
    ].to_h do |model|

      [
        model.name,
        model.order(:id).map(&:attributes)
      ]

    end
  end
end
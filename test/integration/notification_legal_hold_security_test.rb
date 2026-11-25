# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "securerandom"

class NotificationLegalHoldSecurityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  Hold = Infrastructure::NotificationLegalHold
  Event = Infrastructure::NotificationLegalHoldEvent
  Manager = Infrastructure::NotificationLegalHoldManager

  setup do
    @user = User.create!(
      username: "hold-rbac-#{SecureRandom.hex(8)}",
      admin: false
    )

    @notification = InfrastructureNotification.create!(
      event_key: "legal-hold-#{SecureRandom.hex(12)}",
      event_type: "IncidentOpened",
      source_type: "InfrastructureIncident",
      source_id: 1,
      recipient: "legal-hold-test@example.com",
      occurred_at: Time.current,
      status: "Pending"
    )

    @hold = create_hold(actor: "independent-creator")
  end

  teardown do
    sign_out @user
  end

  # ============================================================
  # SECTION A - GOVERNANCE READ ACCESS
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin],
    auditor: [:auditor],
    multi_role_auditor: [:infrastructure_admin, :auditor]
  }.each do |name, roles|

    test "#{name} can review legal hold register" do
      as_roles(roles) do
        get infrastructure_notification_legal_holds_path

        assert_response :success

        assert_select "#notification-legal-holds"
        assert_select "#legal-hold-register"
        assert_select "#legal-hold-audit-summary"
        assert_select "#legal-hold-#{@hold.id}"
      end
    end
  end

  {
    employee: [:employee],
    infrastructure_admin: [:infrastructure_admin]
  }.each do |name, roles|

    test "#{name} cannot review legal hold register" do
      as_roles(roles) do
        get infrastructure_notification_legal_holds_path

        assert_redirected_to root_path
      end
    end
  end

  # ============================================================
  # SECTION B - AUTHORISED REGISTRATION
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin]
  }.each do |name, roles|

    test "#{name} can access registration form" do
      as_roles(roles) do
        get new_infrastructure_notification_legal_hold_path

        assert_response :success
        assert_select "#new-notification-legal-hold"
      end
    end

    test "#{name} can register legal hold with audit evidence" do
      reference = unique_reference

      as_roles(roles) do
        assert_difference -> { Hold.count }, 1 do
          assert_difference -> { Event.count }, 1 do
            assert_no_difference -> { InfrastructureNotification.count } do

              post infrastructure_notification_legal_holds_path,
                   params: registration_params(reference: reference)

            end
          end
        end

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )

        hold = Hold.find_by!(reference: reference)

        assert hold.active?
        assert_equal @notification.id,
                     hold.infrastructure_notification_id

        assert_equal @user.username, hold.placed_by
        assert_equal "Preserve notification evidence", hold.reason

        assert_not_nil hold.placed_at
        assert_nil hold.released_by
        assert_nil hold.released_at

        event = events_for(hold).sole

        assert_equal "Placed", event.action
        assert_equal @user.username, event.actor
        assert_equal hold.reason, event.justification
        assert_not_nil event.created_at
      end
    end
  end

  # ============================================================
  # SECTION C - UNAUTHORISED MANAGEMENT
  # ============================================================

  {
    employee: [:employee],
    infrastructure_admin: [:infrastructure_admin],
    auditor: [:auditor],
    multi_role_auditor: [:infrastructure_admin, :auditor]
  }.each do |name, roles|

    test "#{name} cannot access registration form" do
      as_roles(roles) do
        get new_infrastructure_notification_legal_hold_path

        assert_redirected_to root_path
      end
    end

    test "#{name} cannot register hold through direct request" do
      as_roles(roles) do
        assert_registration_unchanged do
          post infrastructure_notification_legal_holds_path,
               params: registration_params

          assert_redirected_to root_path
        end
      end
    end

    test "#{name} cannot release hold through direct request" do
      as_roles(roles) do
        assert_hold_unchanged(@hold) do
          patch release_infrastructure_notification_legal_hold_path(@hold),
                params: {
                  justification: "Unauthorised release"
                }

          assert_redirected_to root_path
        end
      end
    end
  end

  # ============================================================
  # SECTION D - AUTHORISED RELEASE
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin]
  }.each do |name, roles|

    test "#{name} can independently release legal hold" do
      original_creator = @hold.placed_by
      original_placed_at = @hold.reload.placed_at
      original_reason = @hold.reason

      original_event = events_for(@hold).sole.attributes.deep_dup

      original_notification = @notification.reload.attributes.deep_dup

      as_roles(roles) do
        assert_difference -> { events_for(@hold).count }, 1 do
          assert_no_difference -> { Hold.count } do
            assert_no_difference -> { InfrastructureNotification.count } do

              patch release_infrastructure_notification_legal_hold_path(@hold),
                    params: {
                      justification: "Investigation completed"
                    }

            end
          end
        end

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )

        @hold.reload

        assert_not @hold.active?

        assert_equal @user.username, @hold.released_by
        assert_not_nil @hold.released_at

        assert_equal original_creator, @hold.placed_by
        assert_equal original_placed_at, @hold.placed_at
        assert_equal original_reason, @hold.reason

        assert_equal original_notification,
                     @notification.reload.attributes

        assert_equal original_event,
                     events_for(@hold).order(:id).first.attributes

        event = events_for(@hold).order(:id).last

        assert_equal "Released", event.action
        assert_equal @user.username, event.actor
        assert_equal "Investigation completed", event.justification
        assert_not_nil event.created_at
      end
    end
  end

  test "release justification is normalised" do
    as_roles([:security_admin]) do
      patch release_infrastructure_notification_legal_hold_path(@hold),
            params: {
              justification: "  Investigation completed  "
            }

      assert_redirected_to(
        infrastructure_notification_legal_holds_path
      )

      assert_not @hold.reload.active?

      assert_equal "Investigation completed",
                   events_for(@hold).order(:id).last.justification
    end
  end

  # ============================================================
  # SECTION E - SEGREGATION OF DUTIES
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin]
  }.each do |name, roles|

    test "#{name} cannot release own legal hold" do
      own_hold = create_hold(actor: @user.username)

      as_roles(roles) do
        assert_hold_unchanged(own_hold) do
          patch release_infrastructure_notification_legal_hold_path(own_hold),
                params: {
                  justification: "Attempted self-release"
                }

          assert_redirected_to(
            infrastructure_notification_legal_holds_path
          )
        end
      end
    end
  end

  test "self release comparison is case insensitive" do
    own_hold = create_hold(actor: @user.username.upcase)

    as_roles([:portal_admin]) do
      assert_hold_unchanged(own_hold) do
        patch release_infrastructure_notification_legal_hold_path(own_hold),
              params: {
                justification: "Case variation self-release"
              }

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )
      end
    end
  end

  test "self release comparison ignores surrounding whitespace" do
    own_hold = create_hold(
      actor: "  #{@user.username}  "
    )

    as_roles([:security_admin]) do
      assert_hold_unchanged(own_hold) do
        patch release_infrastructure_notification_legal_hold_path(own_hold),
              params: {
                justification: "Whitespace variation self-release"
              }

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )
      end
    end
  end

  test "missing creator identity prevents release" do
    # Deliberately simulate an inconsistent legacy record.
    # Normal model validation would reject this value.
    @hold.update_columns(placed_by: "")

    as_roles([:portal_admin]) do
      assert_hold_unchanged(@hold) do
        patch release_infrastructure_notification_legal_hold_path(@hold),
              params: {
                justification: "Release without creator evidence"
              }

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )
      end
    end
  end

  # ============================================================
  # SECTION F - RELEASE VALIDATION
  # ============================================================

  test "blank release justification is rejected" do
    as_roles([:portal_admin]) do
      assert_hold_unchanged(@hold) do
        patch release_infrastructure_notification_legal_hold_path(@hold),
              params: {
                justification: "   "
              }

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )
      end
    end
  end

  test "missing release justification is rejected" do
    as_roles([:security_admin]) do
      assert_hold_unchanged(@hold) do
        patch release_infrastructure_notification_legal_hold_path(@hold)

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )
      end
    end
  end

  test "empty release justification is rejected" do
    as_roles([:security_admin]) do
      assert_hold_unchanged(@hold) do
        patch release_infrastructure_notification_legal_hold_path(@hold),
              params: {
                justification: ""
              }

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )
      end
    end
  end

  test "released hold cannot be released again" do
    release_hold(@hold)

    as_roles([:portal_admin]) do
      assert_hold_unchanged(@hold) do
        patch release_infrastructure_notification_legal_hold_path(@hold),
              params: {
                justification: "Duplicate release attempt"
              }

        assert_redirected_to(
          infrastructure_notification_legal_holds_path
        )
      end

      assert_equal 1,
                   events_for(@hold).where(action: "Released").count
    end
  end

  # ============================================================
  # SECTION G - REGISTRATION VALIDATION
  # ============================================================

  test "registration requires existing notification" do
    as_roles([:security_admin]) do
      assert_registration_unchanged do
        params = registration_params

        params[:legal_hold][:infrastructure_notification_id] =
          InfrastructureNotification.maximum(:id).to_i + 1

        post infrastructure_notification_legal_holds_path,
             params: params

        assert_response :unprocessable_entity
      end
    end
  end

  test "registration requires reference" do
    as_roles([:portal_admin]) do
      assert_registration_unchanged do
        params = registration_params
        params[:legal_hold][:reference] = ""

        post infrastructure_notification_legal_holds_path,
             params: params

        assert_response :unprocessable_entity
      end
    end
  end

  test "registration requires reason" do
    as_roles([:security_admin]) do
      assert_registration_unchanged do
        params = registration_params
        params[:legal_hold][:reason] = " "

        post infrastructure_notification_legal_holds_path,
             params: params

        assert_response :unprocessable_entity
      end
    end
  end

  test "duplicate legal hold reference is rejected" do
    as_roles([:portal_admin]) do
      assert_registration_unchanged do
        post infrastructure_notification_legal_holds_path,
             params: registration_params(
               reference: @hold.reference
             )

        assert_response :unprocessable_entity
      end
    end
  end

  # ============================================================
  # SECTION H - MASS ASSIGNMENT PROTECTION
  # ============================================================

  test "registration cannot inject forged actor or release metadata" do
    reference = unique_reference

    as_roles([:security_admin]) do
      params = registration_params(reference: reference)

      params[:legal_hold].merge!(
        placed_by: "forged-creator",
        placed_at: 10.years.ago,
        released_by: "forged-reviewer",
        released_at: Time.current
      )

      post infrastructure_notification_legal_holds_path,
           params: params

      assert_redirected_to(
        infrastructure_notification_legal_holds_path
      )

      hold = Hold.find_by!(reference: reference)

      assert_equal @user.username, hold.placed_by

      assert_in_delta Time.current.to_f,
                      hold.placed_at.to_f,
                      60

      assert hold.active?
      assert_nil hold.released_by
      assert_nil hold.released_at

      event = events_for(hold).sole

      assert_equal "Placed", event.action
      assert_equal @user.username, event.actor
    end
  end

  test "release cannot inject forged actor metadata" do
    as_roles([:portal_admin]) do
      patch release_infrastructure_notification_legal_hold_path(@hold),
            params: {
              justification: "Authorised release",
              released_by: "forged-reviewer",
              actor: "forged-actor",
              released_at: 10.years.ago
            }

      assert_redirected_to(
        infrastructure_notification_legal_holds_path
      )

      @hold.reload

      assert_equal @user.username, @hold.released_by

      assert_in_delta Time.current.to_f,
                      @hold.released_at.to_f,
                      60

      assert_equal @user.username,
                   events_for(@hold).order(:id).last.actor
    end
  end

  # ============================================================
  # SECTION I - PERMISSION-AWARE INTERFACE
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin]
  }.each do |name, roles|

    test "#{name} sees registration button" do
      as_roles(roles) do
        get infrastructure_notification_legal_holds_path

        assert_response :success

        assert_select "#register-legal-hold-button", count: 1
        assert_select "#legal-holds-read-only", count: 0
      end
    end

    test "#{name} sees independent release form" do
      as_roles(roles) do
        get infrastructure_notification_legal_holds_path

        assert_response :success

        assert_select(
          "#legal-hold-release-form-#{@hold.id}",
          count: 1
        )

        assert_select(
          "#legal-hold-justification-#{@hold.id}",
          count: 1
        )
      end
    end
  end

  {
    auditor: [:auditor],
    multi_role_auditor: [:infrastructure_admin, :auditor]
  }.each do |name, roles|

    test "#{name} sees read only register" do
      as_roles(roles) do
        get infrastructure_notification_legal_holds_path

        assert_response :success

        assert_select "#register-legal-hold-button", count: 0
        assert_select ".legal-hold-release-form", count: 0
        assert_select "#legal-holds-read-only", count: 1
        assert_select "#legal-hold-audit-summary", count: 1

        assert_select(
          "#legal-hold-read-only-#{@hold.id}",
          count: 1
        )
      end
    end
  end

  test "creator sees self release restriction" do
    own_hold = create_hold(actor: @user.username)

    as_roles([:portal_admin]) do
      get infrastructure_notification_legal_holds_path

      assert_response :success

      assert_select(
        "#legal-hold-release-form-#{own_hold.id}",
        count: 0
      )

      assert_select(
        "#legal-hold-self-release-blocked-#{own_hold.id}",
        count: 1
      )
    end
  end

  test "case insensitive creator cannot see release form" do
    own_hold = create_hold(actor: @user.username.upcase)

    as_roles([:security_admin]) do
      get infrastructure_notification_legal_holds_path

      assert_response :success

      assert_select(
        "#legal-hold-release-form-#{own_hold.id}",
        count: 0
      )

      assert_select(
        "#legal-hold-self-release-blocked-#{own_hold.id}",
        count: 1
      )
    end
  end

  test "missing creator identity hides release form" do
    @hold.update_columns(placed_by: "")

    as_roles([:portal_admin]) do
      get infrastructure_notification_legal_holds_path

      assert_response :success

      assert_select(
        "#legal-hold-release-form-#{@hold.id}",
        count: 0
      )

      assert_select(
        "#legal-hold-identity-blocked-#{@hold.id}",
        count: 1
      )
    end
  end

  {
    portal_admin: [:portal_admin],
    auditor: [:auditor]
  }.each do |name, roles|

    test "#{name} can review released hold evidence" do
      release_hold(@hold)

      as_roles(roles) do
        get infrastructure_notification_legal_holds_path

        assert_response :success

        assert_select(
          "#legal-hold-release-form-#{@hold.id}",
          count: 0
        )

        assert_select(
          "#legal-hold-release-evidence-#{@hold.id}",
          count: 1
        )

        assert_select "#legal-hold-audit-summary", count: 1
      end
    end
  end

  # ============================================================
  # SECTION J - FAIL-CLOSED DIRECTORY SECURITY
  # ============================================================

  {
    directory_unavailable: nil,
    no_portal_roles: []
  }.each do |name, roles|

    test "#{name} prevents register access" do
      as_roles(roles) do
        get infrastructure_notification_legal_holds_path

        assert_redirected_to new_user_session_path
      end
    end

    test "#{name} prevents registration form access" do
      as_roles(roles) do
        get new_infrastructure_notification_legal_hold_path

        assert_redirected_to new_user_session_path
      end
    end

    test "#{name} prevents legal hold registration" do
      as_roles(roles) do
        assert_registration_unchanged do
          post infrastructure_notification_legal_holds_path,
               params: registration_params

          assert_redirected_to new_user_session_path
        end
      end
    end

    test "#{name} prevents legal hold release" do
      as_roles(roles) do
        assert_hold_unchanged(@hold) do
          patch release_infrastructure_notification_legal_hold_path(@hold),
                params: {
                  justification: "Directory failure release"
                }

          assert_redirected_to new_user_session_path
        end
      end
    end
  end

  # ============================================================
  # SECTION K - LOCAL PRIVILEGE ESCALATION PREVENTION
  # ============================================================

  test "stale local administrator cannot register legal hold" do
    @user.update!(admin: true)

    as_roles([:employee]) do
      assert_registration_unchanged do
        post infrastructure_notification_legal_holds_path,
             params: registration_params

        assert_redirected_to root_path
      end
    end
  end

  test "stale local administrator cannot release legal hold" do
    @user.update!(admin: true)

    as_roles([:employee]) do
      assert_hold_unchanged(@hold) do
        patch release_infrastructure_notification_legal_hold_path(@hold),
              params: {
                justification: "Local privilege bypass attempt"
              }

        assert_redirected_to root_path
      end
    end
  end

  test "stale local administrator with auditor role remains read only" do
    @user.update!(admin: true)

    as_roles([:auditor]) do
      get infrastructure_notification_legal_holds_path

      assert_response :success

      assert_select "#register-legal-hold-button", count: 0
      assert_select ".legal-hold-release-form", count: 0
      assert_select "#legal-holds-read-only", count: 1
    end
  end

  test "security administrator does not require local admin flag" do
    assert_equal false, @user.admin

    as_roles([:security_admin]) do
      patch release_infrastructure_notification_legal_hold_path(@hold),
            params: {
              justification: "Authorised AD governance release"
            }

      assert_redirected_to(
        infrastructure_notification_legal_holds_path
      )

      assert_not @hold.reload.active?
      assert_equal false, @user.reload.admin
    end
  end

  # ============================================================
  # SECTION L - UNAUTHENTICATED REQUESTS
  # ============================================================

  test "guest cannot access legal hold register" do
    get infrastructure_notification_legal_holds_path

    assert_redirected_to new_user_session_path
  end

  test "guest cannot access registration form" do
    get new_infrastructure_notification_legal_hold_path

    assert_redirected_to new_user_session_path
  end

  test "guest cannot register legal hold" do
    assert_registration_unchanged do
      post infrastructure_notification_legal_holds_path,
           params: registration_params

      assert_redirected_to new_user_session_path
    end
  end

  test "guest cannot release legal hold" do
    assert_hold_unchanged(@hold) do
      patch release_infrastructure_notification_legal_hold_path(@hold),
            params: {
              justification: "Unauthenticated release"
            }

      assert_redirected_to new_user_session_path
    end
  end

  # ============================================================
  # SECTION M - AUDIT CONSISTENCY
  # ============================================================

  test "successful release produces consistent audit evidence" do
    verifier = Infrastructure::NotificationLegalHoldAuditVerifier

    before = verifier.new.call

    as_roles([:security_admin]) do
      patch release_infrastructure_notification_legal_hold_path(@hold),
            params: {
              justification: "Audit consistency validation"
            }

      assert_redirected_to(
        infrastructure_notification_legal_holds_path
      )

      assert_not @hold.reload.active?

      after = verifier.new.call

      assert_equal before[:active_holds] - 1,
                   after[:active_holds]

      assert_equal before[:released_holds] + 1,
                   after[:released_holds]

      assert_equal before[:release_events] + 1,
                   after[:release_events]

      assert_equal before[:released_without_event],
                   after[:released_without_event]

      assert_equal before[:active_with_release_event],
                   after[:active_with_release_event]

      assert_equal before[:multiple_release_events],
                   after[:multiple_release_events]
    end
  end

  # ============================================================
  # TEST HELPERS
  # ============================================================

  private

  def unique_reference
    "HOLD-RBAC-#{SecureRandom.hex(10).upcase}"
  end

  def registration_params(reference: unique_reference)
    {
      legal_hold: {
        infrastructure_notification_id: @notification.id,
        reference: reference,
        reason: "Preserve notification evidence"
      }
    }
  end

  def create_hold(actor:)
    Hold.transaction do
      hold = Hold.create!(
        infrastructure_notification: @notification,
        reference: unique_reference,
        reason: "Legal hold security validation",
        placed_by: actor,
        placed_at: Time.current
      )

      Event.create!(
        notification_legal_hold: hold,
        action: "Placed",
        actor: actor,
        justification: hold.reason,
        created_at: Time.current
      )

      hold
    end
  end

  def events_for(hold)
    Event.where(notification_legal_hold_id: hold.id)
  end

  def release_hold(hold)
    Manager.new(
      actor: "independent-reviewer"
    ).release!(
      hold: hold,
      justification: "Independent review completed"
    )

    hold.reload
  end

  def as_roles(roles)
    sign_in @user

    ActiveDirectoryAuthenticator.stub(:current_roles, roles) do
      yield
    end
  end

  def assert_registration_unchanged
    original_notification = @notification.reload.attributes.deep_dup

    assert_no_difference -> { Hold.count } do
      assert_no_difference -> { Event.count } do
        assert_no_difference -> { InfrastructureNotification.count } do
          yield
        end
      end
    end

    assert_equal original_notification,
                 @notification.reload.attributes
  end

  def assert_hold_unchanged(hold)
    original_attributes = hold.reload.attributes.deep_dup

    original_events = events_for(hold)
                      .order(:id)
                      .map(&:attributes)
                      .deep_dup

    original_notification = @notification.reload.attributes.deep_dup

    assert_no_difference -> { Hold.count } do
      assert_no_difference -> { Event.count } do
        assert_no_difference -> { InfrastructureNotification.count } do
          yield
        end
      end
    end

    assert_equal original_attributes,
                 hold.reload.attributes

    assert_equal original_events,
                 events_for(hold).order(:id).map(&:attributes)

    assert_equal original_notification,
                 @notification.reload.attributes
  end
end
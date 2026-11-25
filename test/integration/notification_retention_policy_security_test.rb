# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "securerandom"

class NotificationRetentionPolicySecurityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  Policy = Infrastructure::NotificationRetentionPolicy
  Event = Infrastructure::NotificationRetentionEvent
  Manager = Infrastructure::NotificationRetentionPolicyManager

  setup do
    @user = User.create!(
      username: "retention-rbac-#{SecureRandom.hex(8)}",
      admin: false
    )

    @creator = "independent-creator"

    @policy = create_policy(actor: @creator)
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

    test "#{name} can review retention policy listing" do
      as_roles(roles) do
        get infrastructure_notification_retention_policies_path

        assert_response :success
        assert_select "#retention-policies"
      end
    end

    test "#{name} can review policy details and audit history" do
      as_roles(roles) do
        get infrastructure_notification_retention_policy_path(@policy)

        assert_response :success
        assert_select "#retention-policy-detail"
        assert_select "#retention-policy-audit-history"
      end
    end
  end

  {
    employee: [:employee],
    infrastructure_admin: [:infrastructure_admin]
  }.each do |name, roles|

    test "#{name} cannot review retention policies" do
      as_roles(roles) do
        get infrastructure_notification_retention_policies_path

        assert_redirected_to root_path
      end
    end

    test "#{name} cannot review individual policy" do
      as_roles(roles) do
        get infrastructure_notification_retention_policy_path(@policy)

        assert_redirected_to root_path
      end
    end
  end

  # ============================================================
  # SECTION B - AUTHORISED POLICY CREATION
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin]
  }.each do |name, roles|

    test "#{name} can access new policy form" do
      as_roles(roles) do
        get new_infrastructure_notification_retention_policy_path

        assert_response :success
      end
    end

    test "#{name} can create draft with audit evidence" do
      reference = unique_reference

      as_roles(roles) do
        assert_difference -> { Policy.count }, 1 do
          assert_difference -> { Event.count }, 1 do
            post infrastructure_notification_retention_policies_path,
                 params: {
                   policy: {
                     name: "Authorised retention policy",
                     reference: reference,
                     retention_days: 365
                   }
                 }
          end
        end

        policy = Policy.find_by!(reference: reference)

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(policy)
        )

        assert_equal "Draft", policy.status
        assert_equal 1, policy.version
        assert_equal 365, policy.retention_days
        assert_nil policy.approved_by
        assert_nil policy.approved_at
        assert_not policy.disposal_authorized?

        event = policy.events.first

        assert_equal "Created", event.action
        assert_equal @user.username, event.actor
        assert_nil event.from_status
        assert_equal "Draft", event.to_status
        assert_equal 1, event.policy_version
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

    test "#{name} cannot access new policy form" do
      as_roles(roles) do
        get new_infrastructure_notification_retention_policy_path

        assert_redirected_to root_path
      end
    end

    test "#{name} cannot create policy through direct request" do
      as_roles(roles) do
        assert_no_difference -> { Policy.count } do
          assert_no_difference -> { Event.count } do
            post infrastructure_notification_retention_policies_path,
                 params: {
                   policy: {
                     name: "Unauthorised policy",
                     reference: unique_reference,
                     retention_days: 365
                   }
                 }
          end
        end

        assert_redirected_to root_path
      end
    end

    test "#{name} cannot approve policy through direct request" do
      as_roles(roles) do
        assert_policy_unchanged(@policy) do
          patch approve_infrastructure_notification_retention_policy_path(@policy),
                params: {
                  approval_reference: @policy.reference
                }

          assert_redirected_to root_path
        end
      end
    end

    test "#{name} cannot suspend policy through direct request" do
      approve_policy(@policy)

      as_roles(roles) do
        assert_policy_unchanged(@policy) do
          patch suspend_infrastructure_notification_retention_policy_path(@policy)

          assert_redirected_to root_path
        end
      end
    end
  end

  # ============================================================
  # SECTION D - APPROVAL AND SEGREGATION OF DUTIES
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin]
  }.each do |name, roles|

    test "#{name} can independently approve draft" do
      as_roles(roles) do
        assert_difference -> { @policy.events.count }, 1 do
          patch approve_infrastructure_notification_retention_policy_path(@policy),
                params: {
                  approval_reference: @policy.reference
                }
        end

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )

        @policy.reload

        assert_equal "Approved", @policy.status
        assert_equal 2, @policy.version
        assert_equal @user.username, @policy.approved_by
        assert_not_nil @policy.approved_at
        assert_not @policy.disposal_authorized?

        event = @policy.events.order(:id).last

        assert_equal "Approved", event.action
        assert_equal @user.username, event.actor
        assert_equal "Draft", event.from_status
        assert_equal "Approved", event.to_status
        assert_equal 2, event.policy_version
      end
    end

    test "#{name} cannot approve own draft" do
      own_policy = create_policy(actor: @user.username)

      as_roles(roles) do
        assert_policy_unchanged(own_policy) do
          patch approve_infrastructure_notification_retention_policy_path(own_policy),
                params: {
                  approval_reference: own_policy.reference
                }

          assert_redirected_to(
            infrastructure_notification_retention_policy_path(own_policy)
          )
        end
      end
    end
  end

  test "creator comparison is case insensitive" do
    own_policy = create_policy(actor: @user.username.upcase)

    as_roles([:portal_admin]) do
      assert_policy_unchanged(own_policy) do
        patch approve_infrastructure_notification_retention_policy_path(own_policy),
              params: {
                approval_reference: own_policy.reference
              }

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(own_policy)
        )
      end
    end
  end

  test "approval without creation evidence is rejected" do
    legacy_policy = Policy.create!(
      name: "Legacy policy",
      reference: unique_reference,
      retention_days: 365,
      status: "Draft",
      version: 1
    )

    as_roles([:security_admin]) do
      assert_policy_unchanged(legacy_policy) do
        patch approve_infrastructure_notification_retention_policy_path(legacy_policy),
              params: {
                approval_reference: legacy_policy.reference
              }

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(legacy_policy)
        )
      end
    end
  end

  test "incorrect approval reference is rejected" do
    as_roles([:portal_admin]) do
      assert_policy_unchanged(@policy) do
        patch approve_infrastructure_notification_retention_policy_path(@policy),
              params: {
                approval_reference: "INCORRECT-REFERENCE"
              }

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )
      end
    end
  end

  test "missing approval reference is rejected" do
    as_roles([:security_admin]) do
      assert_policy_unchanged(@policy) do
        patch approve_infrastructure_notification_retention_policy_path(@policy)

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )
      end
    end
  end

  test "blank approval reference is rejected" do
    as_roles([:portal_admin]) do
      assert_policy_unchanged(@policy) do
        patch approve_infrastructure_notification_retention_policy_path(@policy),
              params: {
                approval_reference: " "
              }

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )
      end
    end
  end

  test "approved policy cannot be approved again" do
    approve_policy(@policy)

    as_roles([:portal_admin]) do
      assert_policy_unchanged(@policy) do
        patch approve_infrastructure_notification_retention_policy_path(@policy),
              params: {
                approval_reference: @policy.reference
              }

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )
      end
    end
  end

  # ============================================================
  # SECTION E - POLICY SUSPENSION
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin]
  }.each do |name, roles|

    test "#{name} can suspend approved policy" do
      approve_policy(@policy)

      previous_approver = @policy.reload.approved_by
      previous_approval_time = @policy.approved_at

      as_roles(roles) do
        assert_difference -> { @policy.events.count }, 1 do
          patch suspend_infrastructure_notification_retention_policy_path(@policy)
        end

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )

        @policy.reload

        assert_equal "Suspended", @policy.status
        assert_equal 3, @policy.version
        assert_equal @user.username, @policy.suspended_by
        assert_not_nil @policy.suspended_at
        assert_equal previous_approver, @policy.approved_by
        assert_equal previous_approval_time, @policy.approved_at
        assert_not @policy.disposal_authorized?

        event = @policy.events.order(:id).last

        assert_equal "Suspended", event.action
        assert_equal @user.username, event.actor
        assert_equal "Approved", event.from_status
        assert_equal "Suspended", event.to_status
        assert_equal 3, event.policy_version
      end
    end
  end

  test "draft policy cannot be suspended" do
    as_roles([:portal_admin]) do
      assert_policy_unchanged(@policy) do
        patch suspend_infrastructure_notification_retention_policy_path(@policy)

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )
      end
    end
  end

  test "suspended policy cannot be suspended again" do
    suspend_policy(@policy)

    as_roles([:security_admin]) do
      assert_policy_unchanged(@policy) do
        patch suspend_infrastructure_notification_retention_policy_path(@policy)

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )
      end
    end
  end

  test "suspended policy cannot be approved again" do
    suspend_policy(@policy)

    as_roles([:portal_admin]) do
      assert_policy_unchanged(@policy) do
        patch approve_infrastructure_notification_retention_policy_path(@policy),
              params: {
                approval_reference: @policy.reference
              }

        assert_redirected_to(
          infrastructure_notification_retention_policy_path(@policy)
        )
      end
    end
  end

  # ============================================================
  # SECTION F - PERMISSION-AWARE INTERFACE
  # ============================================================

  {
    portal_admin: [:portal_admin],
    security_admin: [:security_admin]
  }.each do |name, roles|

    test "#{name} sees new policy button" do
      as_roles(roles) do
        get infrastructure_notification_retention_policies_path

        assert_response :success
        assert_select "#new-retention-policy-button", count: 1
        assert_select "#retention-policies-read-only", count: 0
      end
    end

    test "#{name} sees independent approval form" do
      as_roles(roles) do
        get infrastructure_notification_retention_policy_path(@policy)

        assert_response :success
        assert_select "#retention-policy-approval-form", count: 1
        assert_select "#retention-policy-read-only", count: 0
      end
    end

    test "#{name} sees suspension form for approved policy" do
      approve_policy(@policy)

      as_roles(roles) do
        get infrastructure_notification_retention_policy_path(@policy)

        assert_response :success
        assert_select "#retention-policy-suspension-form", count: 1
        assert_select "#retention-policy-approval-form", count: 0
      end
    end
  end

  test "auditor cannot see new policy button" do
    as_roles([:auditor]) do
      get infrastructure_notification_retention_policies_path

      assert_response :success
      assert_select "#new-retention-policy-button", count: 0
      assert_select "#retention-policies-read-only", count: 1
    end
  end

  test "auditor cannot see approval form" do
    as_roles([:auditor]) do
      get infrastructure_notification_retention_policy_path(@policy)

      assert_response :success
      assert_select "#retention-policy-approval-form", count: 0
      assert_select "#retention-policy-suspension-form", count: 0
      assert_select "#retention-policy-read-only", count: 1
      assert_select "#retention-policy-audit-history", count: 1
    end
  end

  test "auditor cannot see suspension form" do
    approve_policy(@policy)

    as_roles([:auditor]) do
      get infrastructure_notification_retention_policy_path(@policy)

      assert_response :success
      assert_select "#retention-policy-suspension-form", count: 0
      assert_select "#retention-policy-read-only", count: 1
      assert_select "#retention-policy-audit-history", count: 1
    end
  end

  test "multi role auditor remains read only" do
    as_roles([:infrastructure_admin, :auditor]) do
      get infrastructure_notification_retention_policy_path(@policy)

      assert_response :success
      assert_select "#retention-policy-read-only", count: 1
      assert_select "#retention-policy-approval-form", count: 0
      assert_select "#retention-policy-suspension-form", count: 0
    end
  end

  test "creator sees independent approval restriction" do
    own_policy = create_policy(actor: @user.username)

    as_roles([:portal_admin]) do
      get infrastructure_notification_retention_policy_path(own_policy)

      assert_response :success
      assert_select "#retention-policy-approval-form", count: 0
      assert_select "#retention-policy-approval-blocked", count: 1
    end
  end

  test "missing creation evidence hides approval form" do
    legacy_policy = Policy.create!(
      name: "Legacy policy",
      reference: unique_reference,
      retention_days: 365,
      status: "Draft",
      version: 1
    )

    as_roles([:security_admin]) do
      get infrastructure_notification_retention_policy_path(legacy_policy)

      assert_response :success
      assert_select "#retention-policy-approval-form", count: 0
      assert_select "#retention-policy-approval-blocked", count: 1
    end
  end

  test "suspended policy exposes no lifecycle management forms" do
    suspend_policy(@policy)

    as_roles([:portal_admin]) do
      get infrastructure_notification_retention_policy_path(@policy)

      assert_response :success
      assert_select "#retention-policy-approval-form", count: 0
      assert_select "#retention-policy-suspension-form", count: 0
      assert_select "#retention-policy-suspended", count: 1
      assert_select "#retention-policy-audit-history", count: 1
    end
  end

  # ============================================================
  # SECTION G - FAIL-CLOSED DIRECTORY SECURITY
  # ============================================================

  {
    directory_unavailable: nil,
    no_portal_roles: []
  }.each do |name, roles|

    test "#{name} prevents policy listing access" do
      as_roles(roles) do
        get infrastructure_notification_retention_policies_path

        assert_redirected_to new_user_session_path
      end
    end

    test "#{name} prevents policy approval" do
      as_roles(roles) do
        assert_policy_unchanged(@policy) do
          patch approve_infrastructure_notification_retention_policy_path(@policy),
                params: {
                  approval_reference: @policy.reference
                }

          assert_redirected_to new_user_session_path
        end
      end
    end

    test "#{name} prevents policy suspension" do
      approve_policy(@policy)

      as_roles(roles) do
        assert_policy_unchanged(@policy) do
          patch suspend_infrastructure_notification_retention_policy_path(@policy)

          assert_redirected_to new_user_session_path
        end
      end
    end

    test "#{name} prevents policy creation" do
      as_roles(roles) do
        assert_no_difference -> { Policy.count } do
          assert_no_difference -> { Event.count } do
            post infrastructure_notification_retention_policies_path,
                 params: {
                   policy: {
                     name: "Directory failure policy",
                     reference: unique_reference,
                     retention_days: 365
                   }
                 }
          end
        end

        assert_redirected_to new_user_session_path
      end
    end
  end

  # ============================================================
  # SECTION H - LOCAL PRIVILEGE ESCALATION PREVENTION
  # ============================================================

  test "stale local administrator cannot approve policy" do
    @user.update!(admin: true)

    as_roles([:employee]) do
      assert_policy_unchanged(@policy) do
        patch approve_infrastructure_notification_retention_policy_path(@policy),
              params: {
                approval_reference: @policy.reference
              }

        assert_redirected_to root_path
      end
    end
  end

  test "stale local administrator with auditor role remains read only" do
    @user.update!(admin: true)

    as_roles([:auditor]) do
      get infrastructure_notification_retention_policy_path(@policy)

      assert_response :success
      assert_select "#retention-policy-read-only", count: 1
      assert_select "#retention-policy-approval-form", count: 0
      assert_select "#retention-policy-suspension-form", count: 0
    end
  end

  test "security administrator does not require local administrator flag" do
    assert_equal false, @user.admin

    as_roles([:security_admin]) do
      patch approve_infrastructure_notification_retention_policy_path(@policy),
            params: {
              approval_reference: @policy.reference
            }

      assert_redirected_to(
        infrastructure_notification_retention_policy_path(@policy)
      )

      assert_equal "Approved", @policy.reload.status
      assert_equal false, @user.reload.admin
    end
  end

  # ============================================================
  # SECTION I - UNAUTHENTICATED REQUESTS
  # ============================================================

  test "guest cannot approve policy" do
    assert_policy_unchanged(@policy) do
      patch approve_infrastructure_notification_retention_policy_path(@policy),
            params: {
              approval_reference: @policy.reference
            }

      assert_redirected_to new_user_session_path
    end
  end

  test "guest cannot suspend policy" do
    approve_policy(@policy)

    assert_policy_unchanged(@policy) do
      patch suspend_infrastructure_notification_retention_policy_path(@policy)

      assert_redirected_to new_user_session_path
    end
  end

  test "guest cannot create policy" do
    assert_no_difference -> { Policy.count } do
      assert_no_difference -> { Event.count } do
        post infrastructure_notification_retention_policies_path,
             params: {
               policy: {
                 name: "Guest policy",
                 reference: unique_reference,
                 retention_days: 365
               }
             }
      end
    end

    assert_redirected_to new_user_session_path
  end

  # ============================================================
  # SECTION J - MASS ASSIGNMENT PROTECTION
  # ============================================================

  test "policy creation cannot inject approval metadata" do
    reference = unique_reference

    as_roles([:security_admin]) do
      post infrastructure_notification_retention_policies_path,
           params: {
             policy: {
               name: "Mass assignment security test",
               reference: reference,
               retention_days: 365,
               status: "Approved",
               version: 99,
               approved_by: "forged-approver",
               approved_at: Time.current,
               suspended_by: "forged-actor",
               suspended_at: Time.current
             }
           }

      policy = Policy.find_by!(reference: reference)

      assert_redirected_to(
        infrastructure_notification_retention_policy_path(policy)
      )

      assert_equal "Draft", policy.status
      assert_equal 1, policy.version
      assert_nil policy.approved_by
      assert_nil policy.approved_at
      assert_nil policy.suspended_by
      assert_nil policy.suspended_at
      assert_equal 1, policy.events.count
      assert_equal "Created", policy.events.first.action
      assert_not policy.disposal_authorized?
    end
  end

  # ============================================================
  # TEST HELPERS
  # ============================================================

  private

  def unique_reference
    "RBAC-#{SecureRandom.hex(10).upcase}"
  end

  def create_policy(actor:)
    Manager.new(actor: actor).create!(
      name: "Retention security validation",
      reference: unique_reference,
      retention_days: 365
    )
  end

  def approve_policy(policy)
    Manager.new(actor: "independent-reviewer").approve!(
      policy: policy,
      approval_reference: policy.reference
    )

    policy.reload
  end

  def suspend_policy(policy)
    approve_policy(policy)

    Manager.new(actor: "independent-reviewer").suspend!(
      policy: policy
    )

    policy.reload
  end

  def as_roles(roles)
    sign_in @user

    ActiveDirectoryAuthenticator.stub(:current_roles, roles) do
      yield
    end
  end

  def assert_policy_unchanged(policy)
    original_attributes = policy.reload.attributes.deep_dup

    original_events = policy.events
                            .order(:id)
                            .map(&:attributes)
                            .deep_dup

    assert_no_difference -> { Event.count } do
      yield
    end

    assert_equal original_attributes, policy.reload.attributes

    assert_equal original_events,
                 policy.events.reload.order(:id).map(&:attributes)
  end
end
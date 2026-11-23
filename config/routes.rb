
# frozen_string_literal: true

# ============================================================
# HERGA CORPORATE PORTAL
# Application Routing Configuration
# ============================================================

Rails.application.routes.draw do

  # ==========================================================
  # 1. AUTHENTICATION - DEVISE / ACTIVE DIRECTORY
  # ==========================================================

  devise_for :users,
             skip: :all,
             controllers: {
               sessions: "users/sessions"
             }

  devise_scope :user do
    get "users/sign_in",
        to: "users/sessions#new",
        as: :new_user_session

    post "users/sign_in",
         to: "users/sessions#create",
         as: :user_session

    delete "users/sign_out",
           to: "users/sessions#destroy",
           as: :destroy_user_session
  end

  # ==========================================================
  # 2. MAIN DASHBOARD
  # ==========================================================

  root "dashboard#index"

  get "dashboard",
      to: "dashboard#index"

  # ==========================================================
  # 3. CORPORATE APPLICATION DIRECTORY
  # ==========================================================

  resources :portal_applications,
            only: [:index]

  # ==========================================================
  # 4. ACTIVE DIRECTORY
  # ==========================================================

  resources :directory_users,
            only: [:index, :show]

  resources :directory_groups,
            only: [:index, :show]

  resources :directory_computers,
            only: [:index, :show]

  # ==========================================================
  # 5. INFRASTRUCTURE ASSET MANAGEMENT
  # ==========================================================

  resources :infrastructure_assets do
    collection do
      post :sync_active_directory
      post :check_all_connectivity
    end

    member do
      get :history
      patch :retire
      post :check_connectivity
    end
  end

  # ==========================================================
  # 6. INFRASTRUCTURE INCIDENT MANAGEMENT
  # ==========================================================

  resources :infrastructure_incidents,
            only: [:index, :show] do
    member do
      patch :acknowledge
      patch :assign
      patch :resolve
    end
  end

  # ==========================================================
  # 7. INFRASTRUCTURE MONITORING & REPORTING
  # ==========================================================

  namespace :infrastructure do

    # --------------------------------------------------------
    # Phase 2D.8.2.6
    # Infrastructure Monitoring Dashboard
    # --------------------------------------------------------

    get "monitoring",
        to: "monitoring#index",
        as: :monitoring

    # --------------------------------------------------------
    # Phase 2D.8.2.3 - 2D.8.2.5
    # Infrastructure Availability Reporting
    # --------------------------------------------------------

    get "availability",
        to: "availability#index",
        as: :availability

    # --------------------------------------------------------
    # Phase 2D.8.2.7
    # Infrastructure Availability Alert Management
    # --------------------------------------------------------

    resources :availability_alerts,
              only: [:index, :show] do
      member do
        patch :acknowledge
      end
    end

    # --------------------------------------------------------
    # Phase 2D.8.2.10
    # Operational Audit & Reporting
    # --------------------------------------------------------

    get "operational_reports",
        to: "operational_reports#index",
        as: :operational_reports

    # --------------------------------------------------------
    # Phase 2D.8.2.11
    # Infrastructure Monitoring Analytics & Trends
    # --------------------------------------------------------

    get "analytics",
        to: "analytics#index",
        as: :analytics

    # --------------------------------------------------------
    # Phase 2D.8.2.12
    # Infrastructure Executive Dashboard
    # --------------------------------------------------------

    get "executive_dashboard",
        to: "executive_dashboard#index",
        as: :executive_dashboard

    # ========================================================
    # NOTIFICATION MANAGEMENT
    # ========================================================
    #
    # Static notification routes must precede the dynamic
    # notifications resource.
    # ========================================================

    # --------------------------------------------------------
    # Phase 2D.8.4.3.4
    # Advanced Notification Failure Investigation
    # --------------------------------------------------------

    get "notifications/job_failures",
        to: "notification_job_failures#index",
        as: :notification_job_failures

    get "notifications/job_failures/:id",
        to: "notification_job_failures#show",
        as: :notification_job_failure,
        constraints: { id: /\d+/ }

    # --------------------------------------------------------
    # Phase 2D.8.4.3.5
    # Notification Operational Analytics & Trends
    # --------------------------------------------------------

    get "notifications/analytics",
        to: "notification_analytics#index",
        as: :notification_analytics

    # --------------------------------------------------------
    # Phase 2D.8.4.3.6
    # Notification Reporting & CSV Export
    # --------------------------------------------------------

    get "notifications/reports",
        to: "notification_reports#index",
        as: :notification_reports

    # --------------------------------------------------------
    # Phase 2D.8.4.3.7 - 2D.8.4.3.8
    # Notification Operations & Health Indicators
    # --------------------------------------------------------

    get "notifications/operations",
        to: "notification_operations#index",
        as: :notification_operations

    # --------------------------------------------------------
    # Phase 2D.8.4.3.9 - 2D.8.4.3.10
    # Notification Retention Assessment & Governance
    #
    # Read-only retention assessment dashboard.
    # --------------------------------------------------------

    get "notifications/retention",
        to: "notification_retention#index",
        as: :notification_retention

    # --------------------------------------------------------
    # Phase 2D.8.4.3.11.2c
    # Retention Governance Security Verification
    #
    # Read-only administrator security dashboard.
    #
    # Includes:
    #   - Policy approval evidence assessment
    #   - Legal hold audit consistency
    #   - Append-only audit trigger verification
    #   - Governance security findings
    #
    # Does not modify policies or legal holds.
    # Does not enable notification disposal.
    # --------------------------------------------------------

    get "notifications/governance_security",
        to: "notification_governance_security#index",
        as: :notification_governance_security

    # ========================================================
    # Phase 2D.8.4.3.11.2d - 2D.8.4.3.11.2e
    # GOVERNANCE COMPLIANCE REPORTING & EVIDENCE INTEGRITY
    # ========================================================
    #
    # Administrator-only access enforced by controller.
    #
    # Includes:
    #   - Consolidated governance compliance dashboard
    #   - Retention policy evidence
    #   - Policy audit events
    #   - Legal hold lifecycle evidence
    #   - Legal hold audit events
    #   - Individual CSV exports
    #   - Consolidated TAR.GZ evidence archive
    #   - JSON integrity manifest with SHA-256 checksums
    #
    # Read-only reporting functionality.
    # No automatic deletion or archival.
    # ========================================================

    # --------------------------------------------------------
    # Governance Compliance Dashboard
    # --------------------------------------------------------

    get "notifications/governance_compliance",
        to: "notification_governance_compliance#index",
        as: :notification_governance_compliance

    # --------------------------------------------------------
    # Phase 2D.8.4.3.11.2e
    # Consolidated Governance Evidence Bundle
    #
    # Must precede the dynamic CSV export route.
    # --------------------------------------------------------

    get "notifications/governance_compliance/evidence_bundle",
        to: "notification_governance_compliance#evidence_bundle",
        as: :notification_governance_evidence_bundle

    # --------------------------------------------------------
    # Individual Governance Evidence CSV Export
    # --------------------------------------------------------

    get "notifications/governance_compliance/export/:section",
        to: "notification_governance_compliance#export",
        as: :notification_governance_compliance_export

    # ========================================================
    # Phase 2D.8.4.3.11.1 - 2D.8.4.3.11.2a
    # RETENTION GOVERNANCE ADMINISTRATION
    # ========================================================
    #
    # Administrator-only access enforced by controllers.
    #
    # Retention policies:
    #   - List policies
    #   - View policy details and audit history
    #   - Create draft policies
    #   - Approve policies
    #   - Suspend policies
    #   - Enforce independent policy approval
    #
    # No automatic deletion or archival.
    # ========================================================

    resources :notification_retention_policies,
              only: [:index, :show, :new, :create] do

      member do
        patch :approve
        patch :suspend
      end

    end

    # ========================================================
    # Phase 2D.8.4.3.11.1 - 2D.8.4.3.11.2b
    # LEGAL HOLD GOVERNANCE
    # ========================================================
    #
    # Administrator-only access enforced by controllers.
    #
    # Legal holds:
    #   - List registered legal holds
    #   - Register new legal holds
    #   - Release legal holds through controlled workflow
    #   - Enforce separation of duties for release
    #   - Record release justification and audit evidence
    #
    # Releasing a legal hold does not delete notifications.
    # ========================================================

    resources :notification_legal_holds,
              only: [:index, :new, :create] do

      member do
        patch :release
      end

    end

    # --------------------------------------------------------
    # Phase 2D.8.2.13
    # Infrastructure Notifications & Escalation
    #
    # Phase 2D.8.3.2
    # Notification Centre & Delivery Audit Trail
    #
    # Phase 2D.8.4.3.3
    # Notification Processing Diagnostics
    #
    # Keep this dynamic resource after the static
    # notification routes.
    # --------------------------------------------------------

    resources :notifications,
              only: [:index, :show],
              constraints: { id: /\d+/ }

  end

  # ==========================================================
  # 8. PORTAL ADMINISTRATION
  # ==========================================================

  namespace :admin do
    resources :portal_applications,
              except: [:show]
  end

  # ==========================================================
  # 9. APPLICATION HEALTH CHECK
  # ==========================================================

  get "up",
      to: "rails/health#show",
      as: :rails_health_check

end

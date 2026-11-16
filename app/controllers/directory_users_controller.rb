
# frozen_string_literal: true

class DirectoryUsersController < ApplicationController
  before_action :require_portal_administrator

  PER_PAGE = 25

  def index
    @heading = "Active Directory Users"
    @query = params[:q].to_s.strip.first(100)

    directory = ActiveDirectory::UserDirectory.new

    # Retrieve the bounded AD directory results.
    all_users = directory.users(query: @query)

    # Number of users returned by LDAP.
    @user_count = all_users.length

    # Calculate page count.
    @total_pages = [(@user_count.to_f / PER_PAGE).ceil, 1].max

    # Validate page number.
    @current_page = params[:page].to_i
    @current_page = 1 if @current_page < 1
    @current_page = @total_pages if @current_page > @total_pages

    # Select only users for the current page.
    offset = (@current_page - 1) * PER_PAGE

    @users = all_users.slice(offset, PER_PAGE) || []

    # Calculate account statistics across returned results.
    @enabled_count = all_users.count { |u| u.enabled == true }
    @disabled_count = all_users.count { |u| u.enabled == false }
    @unknown_count = all_users.count { |u| u.enabled.nil? }

    @directory_error = false

  rescue ActiveDirectory::UserDirectory::DirectoryError,
         Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         Timeout::Error,
         KeyError => e

    Rails.logger.error(
      "Directory user listing failed: #{e.class}: #{e.message}"
    )

    @users = []
    @user_count = 0
    @total_pages = 1
    @current_page = 1
    @enabled_count = 0
    @disabled_count = 0
    @unknown_count = 0
    @directory_error = true
  end

  def show
    directory = ActiveDirectory::UserDirectory.new

    @user = directory.find(params[:id])

    if @user.nil?
      redirect_to directory_users_path,
                  alert: "Directory user not found."
      return
    end

  rescue ActiveDirectory::UserDirectory::DirectoryError,
         Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         Timeout::Error,
         KeyError => e

    Rails.logger.error(
      "Directory user lookup failed: #{e.class}: #{e.message}"
    )

    redirect_to directory_users_path,
                alert: "Active Directory is currently unavailable."
  end
end

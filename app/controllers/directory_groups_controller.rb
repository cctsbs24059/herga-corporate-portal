
# frozen_string_literal: true

class DirectoryGroupsController < ApplicationController
  before_action :require_portal_administrator

  PER_PAGE = 25

  def index
    @heading = "Active Directory Security Groups"
    @query = params[:q].to_s.strip.first(100)

    directory = ActiveDirectory::GroupDirectory.new
    all_groups = directory.groups(query: @query)

    @group_count = all_groups.length
    @global_count = all_groups.count { |g| g.scope == "Global" }
    @universal_count = all_groups.count { |g| g.scope == "Universal" }
    @domain_local_count = all_groups.count { |g| g.scope == "Domain Local" }

    @total_pages = [
      (@group_count.to_f / PER_PAGE).ceil, 1
    ].max

    @current_page = params[:page].to_i
    @current_page = 1 if @current_page < 1
    @current_page = @total_pages if @current_page > @total_pages

    offset = (@current_page - 1) * PER_PAGE
    @groups = all_groups.slice(offset, PER_PAGE) || []

    @directory_error = false

  rescue ActiveDirectory::GroupDirectory::DirectoryError,
         Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         Timeout::Error,
         KeyError => e

    Rails.logger.error(
      "AD group directory failed: #{e.class}: #{e.message}"
    )

    @groups = []
    @group_count = 0
    @global_count = 0
    @universal_count = 0
    @domain_local_count = 0
    @total_pages = 1
    @current_page = 1
    @directory_error = true
  end

  def show
    @heading = "Security Group Details"

    directory = ActiveDirectory::GroupDirectory.new
    @group = directory.find(params[:id])

    unless @group
      redirect_to directory_groups_path,
                  alert: "Security group not found."
      return
    end

  rescue ActiveDirectory::GroupDirectory::DirectoryError,
         Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         Timeout::Error,
         KeyError => e

    Rails.logger.error(
      "AD group lookup failed: #{e.class}: #{e.message}"
    )

    redirect_to directory_groups_path,
                alert: "Active Directory is currently unavailable."
  end
end

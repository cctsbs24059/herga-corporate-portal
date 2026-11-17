
# frozen_string_literal: true

class DirectoryComputersController < ApplicationController
  before_action :require_portal_administrator

  PER_PAGE = 25

  def index
    @heading = "Active Directory Computers"
    @query = params[:q].to_s.strip.first(100)

    directory = ActiveDirectory::ComputerDirectory.new
    all_computers = directory.computers(query: @query)

    @computer_count = all_computers.length
    @enabled_count = all_computers.count(&:enabled)
    @disabled_count = @computer_count - @enabled_count

    @windows_count = all_computers.count do |computer|
      computer.operating_system.downcase.include?("windows")
    end

    @total_pages = [
      (@computer_count.to_f / PER_PAGE).ceil, 1
    ].max

    @current_page = params[:page].to_i
    @current_page = 1 if @current_page < 1
    @current_page = @total_pages if @current_page > @total_pages

    offset = (@current_page - 1) * PER_PAGE
    @computers = all_computers.slice(offset, PER_PAGE) || []

    @directory_error = false

  rescue ActiveDirectory::ComputerDirectory::DirectoryError,
         Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         Timeout::Error,
         KeyError => e

    Rails.logger.error(
      "AD computer directory failed: #{e.class}: #{e.message}"
    )

    @computers = []
    @computer_count = 0
    @enabled_count = 0
    @disabled_count = 0
    @windows_count = 0
    @total_pages = 1
    @current_page = 1
    @directory_error = true
  end

  def show
    @heading = "Computer Details"

    directory = ActiveDirectory::ComputerDirectory.new
    @computer = directory.find(params[:id])

    unless @computer
      redirect_to directory_computers_path,
                  alert: "Computer account not found."
      return
    end

  rescue ActiveDirectory::ComputerDirectory::DirectoryError,
         Net::LDAP::Error,
         OpenSSL::SSL::SSLError,
         IOError,
         SystemCallError,
         Timeout::Error,
         KeyError => e

    Rails.logger.error(
      "AD computer lookup failed: #{e.class}: #{e.message}"
    )

    redirect_to directory_computers_path,
                alert: "Active Directory is currently unavailable."
  end
end

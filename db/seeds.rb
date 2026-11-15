
# ==============================================
# HERGA CORPORATE PORTAL - INITIAL SEED DATA
# ==============================================

# Define the initial HERGA corporate applications.
#
# All applications are initially inactive because
# their final URLs have not yet been verified.

applications = [

  # Existing PXtool application.
  {
    name: "PXtool",
    description: "HERGA media and information management",
    url: "https://corp-central.herga.net:3004",
    category: "Business Applications",
    icon: "images",
    active: false,
    position: 1
  },

  # Planned Network Operations Centre.
  {
    name: "Network Operations Centre",
    description: "Enterprise infrastructure monitoring",
    url: "https://noc.herga.net",
    category: "IT Operations",
    icon: "server",
    active: false,
    position: 2
  },

  # Planned Configuration Management Database.
  {
    name: "Configuration Management Database",
    description: "IT infrastructure asset management",
    url: "https://cmdb.herga.net",
    category: "IT Operations",
    icon: "database",
    active: false,
    position: 3
  },

  # Planned IT Service Desk.
  {
    name: "IT Service Desk",
    description: "IT incidents and service requests",
    url: "https://helpdesk.herga.net",
    category: "IT Services",
    icon: "headset",
    active: false,
    position: 4
  }

]

# Create or update the application records.
applications.each do |attributes|

  # Find an existing record by name.
  # If it does not exist, initialise a new record.
  application = PortalApplication.find_or_initialize_by(
    name: attributes[:name]
  )

  # Apply the application attributes and save.
  application.update!(attributes)

end

# Display confirmation in the terminal.
puts "HERGA Portal application records loaded successfully."

# Display the total number of registered applications.
puts "Total applications: #{PortalApplication.count}"

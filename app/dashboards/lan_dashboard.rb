require "administrate/base_dashboard"

class LanDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    lan: Field::String,
    ports: Field::String,
    timeout: Field::Number,
    primary: Field::Boolean,
    secondary: Field::Boolean,
    remote_client_ip: Field::String,
    remote_user: Field::String,
    binpath: Field::String,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    lan
    primary
    secondary
    remote_client_ip
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    lan
    ports
    timeout
    primary
    secondary
    remote_client_ip
    remote_user
    binpath
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    lan
    ports
    timeout
    primary
    secondary
    remote_client_ip
    remote_user
    binpath
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(lan)
    lan.lan
  end
end

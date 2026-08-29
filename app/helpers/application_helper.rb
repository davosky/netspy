module ApplicationHelper
  # Maps Rails/Devise flash keys onto Bootstrap contextual classes.
  FLASH_BOOTSTRAP_CLASSES = {
    "notice" => "success",
    "success" => "success",
    "alert" => "danger",
    "error" => "danger",
    "warning" => "warning"
  }.freeze

  def flash_bootstrap_class(type)
    FLASH_BOOTSTRAP_CLASSES.fetch(type.to_s, "info")
  end
end

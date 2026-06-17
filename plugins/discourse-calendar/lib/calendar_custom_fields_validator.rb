# frozen_string_literal: true

class CalendarCustomFieldsValidator
  NAME_FORMAT = /\A[a-z0-9]+([_.-][a-z0-9]+)*\z/i

  def initialize(opts = {})
    @opts = opts
  end

  def valid_value?(val)
    @error_message = nil
    return true if val.blank?

    names = val.split("|").reject(&:blank?)

    if names.any? { |name| !name.match?(NAME_FORMAT) }
      @error_message = I18n.t("site_settings.discourse_post_event_allowed_custom_fields_invalid")
      return false
    end

    attributes =
      names.map { |name| DiscoursePostEvent::EventParser.custom_field_data_attribute(name) }

    if attributes.uniq.length != attributes.length
      @error_message = I18n.t("site_settings.discourse_post_event_allowed_custom_fields_collision")
      return false
    end

    reserved = DiscoursePostEvent::EventParser.valid_option_attributes
    if attributes.any? { |attribute| reserved.include?(attribute) }
      @error_message = I18n.t("site_settings.discourse_post_event_allowed_custom_fields_reserved")
      return false
    end

    true
  end

  def error_message
    @error_message
  end
end

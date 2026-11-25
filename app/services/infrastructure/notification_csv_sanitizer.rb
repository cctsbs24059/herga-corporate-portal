# frozen_string_literal: true

module Infrastructure
  # Shared spreadsheet formula injection protection.
  #
  # Neutralises potentially executable spreadsheet cells
  # without modifying the underlying database records.
  #
  # This is a defence-in-depth control and does not guarantee
  # safe interpretation by every spreadsheet application.
  class NotificationCsvSanitizer
    FORMULA_PREFIX = /\A[\p{Space}\p{Cc}\p{Cf}]*[=+@\-＝＋＠－]/u.freeze

    CONTROL_PREFIX = /\A[\p{Space}\p{Cf}]*[\p{Cc}]/u.freeze

    class << self
      def sanitize(value)
        return value unless value.is_a?(String)

        if value.match?(FORMULA_PREFIX) ||
           value.match?(CONTROL_PREFIX)
          "'#{value}"
        else
          value
        end
      end

      def sanitize_row(values)
        values.map { |value| sanitize(value) }
      end
    end
  end
end
# frozen_string_literal: true

require "test_helper"
require "csv"

module Infrastructure
  class NotificationCsvSanitizerTest < ActiveSupport::TestCase
    Sanitizer = NotificationCsvSanitizer

    # ==========================================================
    # SECTION A - STANDARD FORMULA TRIGGERS
    # ==========================================================

    test "neutralises equals formula prefix" do
      assert_equal "'=1+1",
                   Sanitizer.sanitize("=1+1")
    end

    test "neutralises plus formula prefix" do
      assert_equal "'+123",
                   Sanitizer.sanitize("+123")
    end

    test "neutralises minus formula prefix" do
      assert_equal "'-123",
                   Sanitizer.sanitize("-123")
    end

    test "neutralises at sign formula prefix" do
      assert_equal "'@SUM(A1:A5)",
                   Sanitizer.sanitize("@SUM(A1:A5)")
    end

    # ==========================================================
    # SECTION B - WHITESPACE PREFIXES
    # ==========================================================

    test "neutralises space prefixed formula" do
      value = " =1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises multiple space prefixed formula" do
      value = "    +123"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises tab prefixed formula" do
      value = "\t=1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises carriage return prefixed formula" do
      value = "\r=1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises line feed prefixed formula" do
      value = "\n=1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises mixed whitespace prefixed formula" do
      value = " \t\r\n @SUM(A1:A5)"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    # ==========================================================
    # SECTION C - CONTROL CHARACTER PREFIXES
    # ==========================================================

    test "neutralises null prefixed formula" do
      value = "\u0000=1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises escape prefixed formula" do
      value = "\u001B+123"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises delete prefixed formula" do
      value = "\u007F-123"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises leading tab without formula" do
      value = "\tHERGA"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises leading carriage return without formula" do
      value = "\rHERGA"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises leading line feed without formula" do
      value = "\nHERGA"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    # ==========================================================
    # SECTION D - UNICODE FORMULA PREFIXES
    # ==========================================================

    test "neutralises full width equals sign" do
      value = "＝1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises full width plus sign" do
      value = "＋123"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises full width minus sign" do
      value = "－123"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises full width at sign" do
      value = "＠SUM(A1:A5)"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises non breaking space prefixed formula" do
      value = "\u00A0=1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises zero width space prefixed formula" do
      value = "\u200B=1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises byte order mark prefixed formula" do
      value = "\uFEFF=1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    test "neutralises ideographic space prefixed formula" do
      value = "\u3000=1+1"

      assert_equal "'#{value}",
                   Sanitizer.sanitize(value)
    end

    # ==========================================================
    # SECTION E - ORDINARY TEXT PRESERVATION
    # ==========================================================

    test "preserves ordinary governance reference" do
      assert_equal "HERGA-RP-001",
                   Sanitizer.sanitize("HERGA-RP-001")
    end

    test "preserves ordinary governance status" do
      assert_equal "Approved",
                   Sanitizer.sanitize("Approved")
    end

    test "preserves internal equals character" do
      value = "Retention period = 365 days"

      assert_equal value,
                   Sanitizer.sanitize(value)
    end

    test "preserves email address" do
      value = "auditor@example.invalid"

      assert_equal value,
                   Sanitizer.sanitize(value)
    end

    test "preserves ordinary unicode text" do
      value = "Révision de conformité"

      assert_equal value,
                   Sanitizer.sanitize(value)
    end

    test "preserves ordinary leading spaces" do
      value = "  HERGA Corporate Portal"

      assert_equal value,
                   Sanitizer.sanitize(value)
    end

    test "preserves empty string" do
      assert_equal "",
                   Sanitizer.sanitize("")
    end

    test "preserves already neutralised formula" do
      value = "'=1+1"

      assert_equal value,
                   Sanitizer.sanitize(value)
    end

    # ==========================================================
    # SECTION F - DATA TYPE PRESERVATION
    # ==========================================================

    test "preserves positive integer" do
      result = Sanitizer.sanitize(365)

      assert_equal 365, result
      assert_kind_of Integer, result
    end

    test "preserves negative integer" do
      result = Sanitizer.sanitize(-123)

      assert_equal(-123, result)
      assert_kind_of Integer, result
    end

    test "preserves floating point number" do
      result = Sanitizer.sanitize(12.5)

      assert_equal 12.5, result
      assert_kind_of Float, result
    end

    test "preserves nil" do
      assert_nil Sanitizer.sanitize(nil)
    end

    test "preserves boolean values" do
      assert_equal true, Sanitizer.sanitize(true)
      assert_equal false, Sanitizer.sanitize(false)
    end

    # ==========================================================
    # SECTION G - ROW SANITISATION AND DATA INTEGRITY
    # ==========================================================

    test "sanitises mixed row without modifying original values" do
      original = [
        1,
        "HERGA",
        "=1+1",
        -123,
        nil,
        "＠SUM(A1:A5)"
      ]

      snapshot = original.map do |value|
        value.is_a?(String) ? value.dup : value
      end

      result = Sanitizer.sanitize_row(original)

      assert_equal [
        1,
        "HERGA",
        "'=1+1",
        -123,
        nil,
        "'＠SUM(A1:A5)"
      ], result

      assert_equal snapshot, original
      refute_same original, result
    end

    test "sanitisation is idempotent" do
      value = "\t=1+1"

      first_result = Sanitizer.sanitize(value)
      second_result = Sanitizer.sanitize(first_result)

      assert_equal first_result, second_result
    end

    test "sanitised values survive CSV serialisation" do
      original = [
        "HERGA",
        "=1+1",
        "Reason, with comma",
        "Reason with \"quotes\"",
        "Line one\nLine two",
        "\t+123"
      ]

      sanitised = Sanitizer.sanitize_row(original)

      csv = CSV.generate do |output|
        output << sanitised
      end

      parsed = CSV.parse(csv).first

      assert_equal sanitised, parsed
      assert_equal "'=1+1", parsed[1]
      assert_equal "Reason, with comma", parsed[2]
      assert_equal "Reason with \"quotes\"", parsed[3]
      assert_equal "Line one\nLine two", parsed[4]
      assert_equal "'\t+123", parsed[5]
    end
  end
end
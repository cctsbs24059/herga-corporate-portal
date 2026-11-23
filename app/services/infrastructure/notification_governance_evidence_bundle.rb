
# frozen_string_literal: true

require "csv"
require "digest"
require "json"
require "rubygems/package"
require "stringio"
require "time"
require "zlib"

module Infrastructure
  # ============================================================
  # HERGA CORPORATE PORTAL
  # Governance Audit Evidence Bundle
  #
  # Phase 2D.8.4.3.11.2e
  #
  # Responsibilities:
  #   - Generate read-only governance evidence snapshots
  #   - Package CSV reports into a TAR.GZ archive
  #   - Generate an accompanying JSON integrity manifest
  #   - Calculate SHA-256 checksums for each evidence file
  #   - Identify truncated evidence exports
  #   - Verify archive contents against their manifest
  #
  # Security:
  #   - Does not modify governance records
  #   - Does not delete or archive notifications
  #   - Does not digitally sign evidence
  #   - Controller must enforce administrator access
  # ============================================================

  class NotificationGovernanceEvidenceBundle

    VERSION = 1

    MAX_BUNDLE_BYTES = 25 * 1024 * 1024

    class VerificationError < StandardError; end

    class BundleTooLarge < StandardError; end

    # ==========================================================
    # INITIALIZATION
    # ==========================================================

    def initialize(
      report: NotificationGovernanceComplianceReport.new,
      generated_at: Time.current
    )
      @report = report
      @generated_at = generated_at.utc
    end

    # ==========================================================
    # BUILD EVIDENCE BUNDLE
    # ==========================================================

    def build
      files = {}

      # Use the production report's defined sections rather
      # than requiring the injected report class to define
      # a SECTIONS constant.

      NotificationGovernanceComplianceReport::SECTIONS.each do |section|
        files["#{section}.csv"] = @report.csv(section: section).b
      end

      counts = @report.section_counts

      sections = NotificationGovernanceComplianceReport::SECTIONS.map do |section|

        content = files.fetch("#{section}.csv")

        total = if section == "summary"
                  nil
                else
                  counts.fetch(section)
                end

        rows = CSV.parse(content, headers: true).length

        {
          section: section,
          file: "#{section}.csv",
          exported_rows: rows,
          total_rows_at_assessment: total,
          truncated: !total.nil? && rows < total,
          sha256: Digest::SHA256.hexdigest(content),
          bytes: content.bytesize
        }

      end

      # ========================================================
      # INTEGRITY MANIFEST
      # ========================================================

      manifest = {
        format_version: VERSION,
        generated_at_utc: @generated_at.iso8601(6),

        export_limit_per_section:
          NotificationGovernanceComplianceReport::MAX_ROWS_PER_SECTION,

        sections: sections,

        warning: (
          "SHA-256 detects changes relative to this manifest; " \
          "this bundle is not digitally signed."
        )
      }

      files["manifest.json"] = JSON.pretty_generate(manifest).b

      # ========================================================
      # MAXIMUM BUNDLE SIZE
      # ========================================================

      total_bytes = files.values.sum(&:bytesize)

      if total_bytes > MAX_BUNDLE_BYTES
        raise BundleTooLarge,
              "Evidence exceeds the maximum bundle size"
      end

      # ========================================================
      # GENERATE COMPRESSED TAR ARCHIVE
      # ========================================================

      io = StringIO.new("".b)

      Zlib::GzipWriter.wrap(io) do |gzip|

        Gem::Package::TarWriter.new(gzip) do |tar|

          files.each do |name, content|

            tar.add_file_simple(
              name,
              0o600,
              content.bytesize
            ) do |entry|
              entry.write(content)
            end

          end

        end

      end

      io.string
    end

    # ==========================================================
    # VERIFY EVIDENCE BUNDLE
    # ==========================================================

    def self.verify(bytes)
      files = {}

      # ========================================================
      # EXTRACT ARCHIVE ENTRIES
      # ========================================================

      Zlib::GzipReader.wrap(StringIO.new(bytes.b)) do |gzip|

        Gem::Package::TarReader.new(gzip) do |tar|

          tar.each do |entry|

            name = entry.full_name

            unless name.match?(/\A(?:manifest\.json|[a-z_]+\.csv)\z/)
              raise VerificationError, "Unexpected archive entry"
            end

            if files.key?(name)
              raise VerificationError, "Duplicate archive entry"
            end

            if files.length >= 6
              raise VerificationError, "Archive contains too many files"
            end

            if entry.header.size > MAX_BUNDLE_BYTES
              raise VerificationError, "Oversized archive entry"
            end

            files[name] = entry.read

          end

        end

      end

      # ========================================================
      # VALIDATE TOTAL ARCHIVE SIZE
      # ========================================================

      total_bytes = files.values.sum(&:bytesize)

      if total_bytes > MAX_BUNDLE_BYTES
        raise VerificationError, "Oversized archive"
      end

      # ========================================================
      # PARSE AND VALIDATE MANIFEST
      # ========================================================

      manifest = JSON.parse(files.fetch("manifest.json"))

      unless manifest.fetch("format_version") == VERSION
        raise VerificationError, "Unsupported manifest version"
      end

      sections = manifest.fetch("sections")

      expected = NotificationGovernanceComplianceReport::SECTIONS.map do |section|
        "#{section}.csv"
      end

      actual = sections.map do |row|
        row.fetch("file")
      end

      unless actual == expected
        raise VerificationError, "Invalid section inventory"
      end

      unless files.keys.sort == (expected + ["manifest.json"]).sort
        raise VerificationError, "Unexpected archive files"
      end

      # ========================================================
      # VERIFY FILE CHECKSUMS, SIZES AND RECORD COUNTS
      # ========================================================

      sections.each do |section|

        filename = section.fetch("file")

        content = files.fetch(filename)

        actual_checksum = Digest::SHA256.hexdigest(content)

        expected_checksum = section.fetch("sha256")

        unless actual_checksum == expected_checksum
          raise VerificationError,
                "Checksum mismatch: #{filename}"
        end

        unless content.bytesize == section.fetch("bytes")
          raise VerificationError, "Size mismatch"
        end

        actual_rows = CSV.parse(
          content,
          headers: true
        ).length

        unless actual_rows == section.fetch("exported_rows")
          raise VerificationError, "Row count mismatch"
        end

      end

      # Return the verified manifest.
      manifest

    rescue KeyError,
           JSON::ParserError,
           CSV::MalformedCSVError,
           Zlib::Error,
           Gem::Package::TarInvalidError,
           EOFError,
           ArgumentError => e

      raise VerificationError,
            "Invalid evidence bundle: #{e.message}"

    end

  end
end

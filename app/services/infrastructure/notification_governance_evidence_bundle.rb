# frozen_string_literal: true

require "csv"
require "digest"
require "json"
require "openssl"
require "rubygems/package"
require "stringio"
require "time"
require "zlib"

module Infrastructure
  # Read-only CSV evidence archive. Signed bundles contain a detached RSA-PSS
  # signature over the exact manifest.json bytes. Trust is established only
  # through a separately provisioned public key, never a key inside the archive.
  class NotificationGovernanceEvidenceBundle
    VERSION = 1
    MAX_BUNDLE_BYTES = 25 * 1024 * 1024
    SIGNATURE_FILE = "manifest.sig"
    SIGNATURE_ALGORITHM = "RSA-PSS-SHA256"

    class VerificationError < StandardError; end
    class BundleTooLarge < StandardError; end
    class SigningError < StandardError; end

    def initialize(report: NotificationGovernanceComplianceReport.new,
                   generated_at: Time.current,
                   signing_key_path: ENV["HERGA_EVIDENCE_SIGNING_KEY_PATH"])
      @report = report
      @generated_at = generated_at.utc
      @signing_key_path = signing_key_path
    end

    def build
      files = {}
      sections_list = NotificationGovernanceComplianceReport::SECTIONS
      sections_list.each { |section| files["#{section}.csv"] = @report.csv(section: section).b }
      counts = @report.section_counts
      sections = sections_list.map do |section|
        content = files.fetch("#{section}.csv")
        total = section == "summary" ? nil : counts.fetch(section)
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
      manifest = {
        format_version: VERSION,
        generated_at_utc: @generated_at.iso8601(6),
        export_limit_per_section: NotificationGovernanceComplianceReport::MAX_ROWS_PER_SECTION,
        sections: sections,
        warning: "SHA-256 checksums alone do not authenticate an unsigned archive."
      }

      if @signing_key_path && !@signing_key_path.empty?
        key = load_private_key(@signing_key_path)
        manifest[:signature] = {
          algorithm: SIGNATURE_ALGORITHM,
          key_id: Digest::SHA256.hexdigest(key.public_to_der)
        }
        manifest_bytes = JSON.pretty_generate(manifest).b
        files["manifest.json"] = manifest_bytes
        files[SIGNATURE_FILE] = key.sign_pss("SHA256", manifest_bytes, salt_length: :digest, mgf1_hash: "SHA256")
      else
        files["manifest.json"] = JSON.pretty_generate(manifest).b
      end

      raise BundleTooLarge, "Evidence exceeds the maximum bundle size" if files.values.sum(&:bytesize) > MAX_BUNDLE_BYTES
      io = StringIO.new("".b)
      Zlib::GzipWriter.wrap(io) do |gzip|
        Gem::Package::TarWriter.new(gzip) do |tar|
          files.each do |name, content|
            tar.add_file_simple(name, 0o600, content.bytesize) { |entry| entry.write(content) }
          end
        end
      end
      io.string
    end

    # Without a trusted public key, signed archives fail closed. Legacy
    # unsigned archives can be checked for internal consistency only, and are
    # explicitly labelled unsigned in the returned manifest.
    def self.verify(bytes, public_key_path: ENV["HERGA_EVIDENCE_VERIFY_KEY_PATH"],
                    require_signature: false)
      raise VerificationError, "Oversized compressed archive" if bytes.bytesize > MAX_BUNDLE_BYTES
      files = {}
      total_bytes = 0
      Zlib::GzipReader.wrap(StringIO.new(bytes.b)) do |gzip|
        Gem::Package::TarReader.new(gzip) do |tar|
          tar.each do |entry|
            name = entry.full_name
            unless name.match?(/\A(?:manifest\.json|manifest\.sig|[a-z_]+\.csv)\z/) && entry.file?
              raise VerificationError, "Unexpected archive entry"
            end
            raise VerificationError, "Duplicate archive entry" if files.key?(name)
            raise VerificationError, "Archive contains too many files" if files.length >= 7
            size = entry.header.size
            raise VerificationError, "Oversized archive entry" if size > MAX_BUNDLE_BYTES || total_bytes + size > MAX_BUNDLE_BYTES
            files[name] = entry.read
            total_bytes += files.fetch(name).bytesize
          end
        end
      end

      manifest_bytes = files.fetch("manifest.json")
      manifest = JSON.parse(manifest_bytes)
      raise VerificationError, "Unsupported manifest version" unless manifest.fetch("format_version") == VERSION
      sections = manifest.fetch("sections")
      expected = NotificationGovernanceComplianceReport::SECTIONS.map { |section| "#{section}.csv" }
      raise VerificationError, "Invalid section inventory" unless sections.map { |row| row.fetch("file") } == expected
      raise VerificationError, "Invalid section identifiers" unless sections.map { |row| row.fetch("section") } == NotificationGovernanceComplianceReport::SECTIONS

      signature_info = manifest["signature"]
      if signature_info
        raise VerificationError, "Missing detached signature" unless files.key?(SIGNATURE_FILE)
        raise VerificationError, "Unsupported signature algorithm" unless signature_info.fetch("algorithm") == SIGNATURE_ALGORITHM
        raise VerificationError, "Trusted public key is required" if public_key_path.to_s.empty?
        public_key = OpenSSL::PKey.read(File.binread(public_key_path))
        raise VerificationError, "Expected RSA public key" unless public_key.is_a?(OpenSSL::PKey::RSA)
        key_id = Digest::SHA256.hexdigest(public_key.public_to_der)
        raise VerificationError, "Untrusted signing key" unless signature_info.fetch("key_id") == key_id
        valid = public_key.verify_pss("SHA256", files.fetch(SIGNATURE_FILE), manifest_bytes,
                                      salt_length: :digest, mgf1_hash: "SHA256")
        raise VerificationError, "Invalid evidence signature" unless valid
      else
        raise VerificationError, "Unexpected detached signature" if files.key?(SIGNATURE_FILE)
        raise VerificationError, "Signature required" if require_signature
      end

      expected_files = expected + ["manifest.json"] + (signature_info ? [SIGNATURE_FILE] : [])
      raise VerificationError, "Unexpected archive files" unless files.keys.sort == expected_files.sort
      sections.each do |section|
        content = files.fetch(section.fetch("file"))
        raise VerificationError, "Checksum mismatch: #{section.fetch('file')}" unless Digest::SHA256.hexdigest(content) == section.fetch("sha256")
        raise VerificationError, "Size mismatch" unless content.bytesize == section.fetch("bytes")
        raise VerificationError, "Row count mismatch" unless CSV.parse(content, headers: true).length == section.fetch("exported_rows")
      end
      manifest.merge("verification_status" => signature_info ? "signature_verified" : "unsigned_legacy_integrity_only")
    rescue KeyError, TypeError, JSON::ParserError, CSV::MalformedCSVError, Zlib::Error,
           Gem::Package::TarInvalidError, EOFError, ArgumentError, OpenSSL::PKey::PKeyError,
           Errno::ENOENT, Errno::EACCES => e
      raise VerificationError, "Invalid evidence bundle: #{e.message}"
    end

    private

    def load_private_key(path)
      key = OpenSSL::PKey.read(File.binread(path))
      unless key.is_a?(OpenSSL::PKey::RSA) && key.private?
        raise SigningError, "RSA private signing key required"
      end
      raise SigningError, "RSA signing key must be at least 3072 bits" if key.n.num_bits < 3072
      key
    rescue OpenSSL::PKey::PKeyError, Errno::ENOENT, Errno::EACCES => e
      raise SigningError, "Cannot load evidence signing key: #{e.class}"
    end
  end
end

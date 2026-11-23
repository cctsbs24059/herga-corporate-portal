# frozen_string_literal: true

require "test_helper"
require "tempfile"

module Infrastructure
  class NotificationGovernanceEvidenceSigningTest < ActiveSupport::TestCase
    FakeReport = Class.new do
      def csv(section:)
        "id,value\n1,#{section}\n"
      end

      def section_counts
        { "policies" => 2, "policy_events" => 1, "legal_holds" => 1, "legal_hold_events" => 1 }
      end
    end

    setup do
      @private_key = OpenSSL::PKey::RSA.generate(3072)
      @private_file = Tempfile.new("herga-private")
      @public_file = Tempfile.new("herga-public")
      @private_file.write(@private_key.to_pem)
      @private_file.flush
      @public_file.write(@private_key.public_key.to_pem)
      @public_file.flush
    end

    teardown do
      @private_file.close!
      @public_file.close!
    end

    test "signed evidence verifies with trusted public key" do
      bytes = signed_bundle
      result = NotificationGovernanceEvidenceBundle.verify(bytes, public_key_path: @public_file.path, require_signature: true)
      assert_equal "signature_verified", result.fetch("verification_status")
      assert_equal 5, result.fetch("sections").length
    end

    test "signed evidence requires a trusted key" do
      assert_raises(NotificationGovernanceEvidenceBundle::VerificationError) do
        NotificationGovernanceEvidenceBundle.verify(signed_bundle, public_key_path: nil)
      end
    end

    test "signed evidence rejects a different public key" do
      other = Tempfile.new("herga-other-public")
      other.write(OpenSSL::PKey::RSA.generate(3072).public_key.to_pem)
      other.flush
      assert_raises(NotificationGovernanceEvidenceBundle::VerificationError) do
        NotificationGovernanceEvidenceBundle.verify(signed_bundle, public_key_path: other.path)
      end
    ensure
      other&.close!
    end

    test "legacy unsigned evidence is explicitly labelled" do
      bytes = NotificationGovernanceEvidenceBundle.new(report: FakeReport.new, signing_key_path: nil).build
      result = NotificationGovernanceEvidenceBundle.verify(bytes)
      assert_equal "unsigned_legacy_integrity_only", result.fetch("verification_status")
      assert_raises(NotificationGovernanceEvidenceBundle::VerificationError) do
        NotificationGovernanceEvidenceBundle.verify(bytes, require_signature: true)
      end
    end

    test "tampered signed manifest fails signature verification" do
      bytes = signed_bundle
      entries = extract(bytes)
      entries["manifest.json"] = entries.fetch("manifest.json").sub("SHA-256", "SHA-257")
      assert_raises(NotificationGovernanceEvidenceBundle::VerificationError) do
        NotificationGovernanceEvidenceBundle.verify(repack(entries), public_key_path: @public_file.path)
      end
    end

    private

    def signed_bundle
      NotificationGovernanceEvidenceBundle.new(report: FakeReport.new, signing_key_path: @private_file.path).build
    end

    def extract(bytes)
      files = {}
      Zlib::GzipReader.wrap(StringIO.new(bytes)) do |gzip|
        Gem::Package::TarReader.new(gzip) { |tar| tar.each { |entry| files[entry.full_name] = entry.read } }
      end
      files
    end

    def repack(files)
      io = StringIO.new("".b)
      Zlib::GzipWriter.wrap(io) do |gzip|
        Gem::Package::TarWriter.new(gzip) do |tar|
          files.each { |name, content| tar.add_file_simple(name, 0o600, content.bytesize) { |entry| entry.write(content) } }
        end
      end
      io.string
    end
  end
end

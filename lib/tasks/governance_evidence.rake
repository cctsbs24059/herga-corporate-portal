# frozen_string_literal: true

namespace :herga do
  namespace :governance do
    desc "Verify governance evidence (FILE=/path/archive.tar.gz; HERGA_EVIDENCE_VERIFY_KEY_PATH=/path/public.pem; REQUIRE_SIGNATURE=1)"
    task verify_evidence: :environment do
      path = ENV.fetch("FILE")
      manifest = Infrastructure::NotificationGovernanceEvidenceBundle.verify(
        File.binread(path), require_signature: ENV["REQUIRE_SIGNATURE"] == "1"
      )
      puts "Verification status: #{manifest.fetch('verification_status')}"
      puts "Verified #{manifest.fetch('sections').length} CSV sections."
      manifest.fetch("sections").each do |section|
        puts "#{section.fetch('file')}: #{section.fetch('exported_rows')} rows; truncated=#{section.fetch('truncated')}"
      end
    end
  end
end

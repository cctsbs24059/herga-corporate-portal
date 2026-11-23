# frozen_string_literal: true

namespace :herga do
  namespace :governance do
    desc "Verify a governance evidence archive (FILE=/path/to/archive.tar.gz)"
    task verify_evidence: :environment do
      path = ENV.fetch("FILE")
      manifest = Infrastructure::NotificationGovernanceEvidenceBundle.verify(File.binread(path))
      puts "Verified #{manifest.fetch('sections').length} CSV sections."
      manifest.fetch("sections").each do |section|
        puts "#{section.fetch('file')}: #{section.fetch('exported_rows')} rows; truncated=#{section.fetch('truncated')}"
      end
    end
  end
end

#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "pathname"

VERSION_PATTERN = /\A\d+\.\d+\.\d+\z/

version = ARGV.fetch(0) do
  warn "Usage: scripts/update-release-metadata.rb <version>"
  exit 64
end

unless VERSION_PATTERN.match?(version)
  warn "Error: Version must use semantic versioning (for example, 0.2.0)."
  exit 64
end

root = Pathname(__dir__).parent
project_path = root.join("project.yml")
changelog_path = root.join("CHANGELOG.md")
site_path = root.join("docs/index.html")

project = project_path.read
current_version = project[/MARKETING_VERSION:\s*"([^"]+)"/, 1]
current_build = project[/CURRENT_PROJECT_VERSION:\s*"(\d+)"/, 1]

unless current_version && current_build
  warn "Error: Could not read the current version and build from project.yml."
  exit 1
end

if current_version != version
  project.sub!(/MARKETING_VERSION:\s*"[^"]+"/, "MARKETING_VERSION: \"#{version}\"")
  project.sub!(/CURRENT_PROJECT_VERSION:\s*"\d+"/, "CURRENT_PROJECT_VERSION: \"#{current_build.to_i + 1}\"")
  project_path.write(project)
end

changelog = changelog_path.read
release_heading = "## v#{version}"
unless changelog.include?(release_heading)
  replacement = "## Unreleased\n\n#{release_heading} — #{Date.today.iso8601}\n\n"
  unless changelog.sub!(/^## Unreleased[ \t]*\n(?:[ \t]*\n)*/, replacement)
    warn "Error: CHANGELOG.md does not contain an Unreleased section."
    exit 1
  end
  changelog_path.write(changelog)
end

site = site_path.read
site.sub!(
  %r{href="(?:https://github\.com/arvindang/murmur/releases/download/v\d+\.\d+\.\d+/)?Murmur-\d+\.\d+\.\d+\.dmg"},
  "href=\"Murmur-#{version}.dmg\""
)
site.sub!(/Download Murmur v\d+\.\d+\.\d+/, "Download Murmur v#{version}")

unless site.include?("href=\"Murmur-#{version}.dmg\"") && site.include?("Download Murmur v#{version}")
  warn "Error: Could not update the marketing-page download link."
  exit 1
end

site_path.write(site)

puts "Prepared release metadata for v#{version}."

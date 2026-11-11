#!/usr/bin/env bash
set -e

# Ensure we are in the project root (one level up from scripts/)
cd "$(dirname "$0")/.."

# Load .env variables
if [ -f .env ]; then
  set -a
  source .env
  set +a
else
  echo "❌ .env file not found! Please create one based on .env.example"
  exit 1
fi

echo "🚀 Starting iOS Deployment..."
echo "This script will export the game locally using Godot and then use Fastlane to build and upload."

# Check if Fastlane is installed
if ! command -v fastlane &> /dev/null; then
    echo "❌ Fastlane not found. Please install it (e.g. 'brew install fastlane' or 'gem install fastlane')."
    exit 1
fi

# Run Fastlane
bundle install
bundle exec fastlane release

echo "✅ Deployment finished successfully!"

cask "disk-checker" do
  version "0.1.2"
  sha256 "05fcea022895956b263c5a7b716a6a9a2de91e3fff72a416abbb0c2e7ee280c8"

  url "https://github.com/praveen902012/mac-diskchecker/releases/download/v0.1.2/Disk-Checker-0.1.2-arm64.zip"
  name "Disk Checker"
  desc "Explore Mac storage and move selected files and screenshots to Trash"
  homepage "https://github.com/praveen902012/mac-diskchecker"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Disk Checker.app"
end

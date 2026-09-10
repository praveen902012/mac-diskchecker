cask "disk-checker" do
  version "0.1.1"
  sha256 "8453b0a02f78ef277eadbef76566fc1e36c719befbcf821208b2b22ebfe4713c"

  url "https://github.com/praveen902012/mac-diskchecker/releases/download/v0.1.1/Disk-Checker-0.1.1-arm64.zip"
  name "Disk Checker"
  desc "Explore Mac storage and move selected files and screenshots to Trash"
  homepage "https://github.com/praveen902012/mac-diskchecker"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Disk Checker.app"
end

cask "disk-checker" do
  version "0.1.0"
  sha256 "a222f7031eee7965785a894e1adeef7cbd7804646c724bdc1a5913f644d9cc95"

  url "https://github.com/praveen902012/mac-diskchecker/releases/download/v0.1.0/Disk-Checker-0.1.0-arm64.zip"
  name "Disk Checker"
  desc "Explore Mac storage and move selected files and screenshots to Trash"
  homepage "https://github.com/praveen902012/mac-diskchecker"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Disk Checker.app"
end

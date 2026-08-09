module Cresium
  VERSION = "0.1.0"
  GIT_SHA = {{ `git rev-parse --short HEAD`.chomp.stringify }}
end

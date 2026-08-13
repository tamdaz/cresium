module Cresium
  VERSION = {{ `shards version`.stringify }}
  GIT_SHA = {{ `git rev-parse --short HEAD`.chomp.stringify }}
end

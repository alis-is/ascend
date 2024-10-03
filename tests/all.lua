TEST = require "u-test"

DISABLE_CLEANUP = false --- disable to see the tmp directory

require "core-single"
require "core-multi"
require "isolation"
require "healtchecks"
require "logs"
require "asctl"
require "advanced"

TEST.summary()

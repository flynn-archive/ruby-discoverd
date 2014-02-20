# Since both Celluloid and Minitest use at_exit hooks, we need to ensure
# that the Minitest hook runs before the Celluloid one (so Celluloid has
# not shutdown when the tests run), so we need to require Minitest *after*
# Celluloid (as at_exit hooks are called in reverse order)
require "discover"
require "minitest/autorun"

# Only log Celluloid errors
Celluloid.logger.level = Logger::ERROR

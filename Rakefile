require "bundler/gem_tasks"

desc "Run all tests by default"
task :default => "test:integration"

namespace :test do
  # If HAS_DEPENDENCIES is set then we just run the tests, otherwise we spin up a
  # Docker container with all the dependencies installed and run the tests inside that
  if ENV["HAS_DEPENDENCIES"]
    require "rake/testtask"

    Rake::TestTask.new(:integration) do |t|
      t.libs << "test"
      t.pattern = "test/integration/test_*.rb"
    end
  else
    desc "Run the integration tests in a Docker container"
    task :integration => :build_image do
      exec "docker run -i -t -e HAS_DEPENDENCIES=true discoverd-ruby-test"
    end

    desc "Build the Docker image for running tests"
    task :build_image => [:docker, "tmp/.build_base_image", :build_test_image]

    # This task builds the base Docker image which has etcd, discoverd & gem dependencies.
    #
    # We use a file task as we only want to rebuild if the base dependencies change (so we
    # don't have to install those dependencies every time we run the tests)
    BASE_IMAGE_FILE_DEPENDENCIES = %w(
      Dockerfile.base
      Gemfile
      Gemfile.lock
      discover.gemspec
    )
    file "tmp/.build_base_image" => BASE_IMAGE_FILE_DEPENDENCIES do
      FileUtils.ln_sf "Dockerfile.base", "Dockerfile"

      unless system "docker build -rm=true -t discoverd-ruby-base ."
        fail "failed to build the test Docker image, exiting"
      end

      FileUtils.touch "tmp/.build_base_image"
    end

    # The test image gets rebuilt every time we run the tests to ensure
    # we are testing the correct code
    task :build_test_image do
      FileUtils.ln_sf "Dockerfile.test", "Dockerfile"

      unless system "docker build -rm=true -t discoverd-ruby-test ."
        fail "failed to build the test Docker image, exiting"
      end
    end

    task :docker do
      unless system("docker version >/dev/null")
        fail "Docker is required to run the integration tests, but it is not available. Exiting"
      end
    end

    def fail(msg)
      $stderr.puts "*** ERROR ***"
      $stderr.puts msg
      $stderr.puts "*************"
      exit 1
    end
  end
end

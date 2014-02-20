require "bundler/gem_tasks"

namespace :test do
  desc "Run the integration tests in a Docker container"
  task :integration => :build_image do
    exec "docker run -i -t discoverd-ruby-test"
  end

  desc "Build the Docker image for running tests"
  task :build_image => :docker do
    system "docker build -rm=true -t discoverd-ruby-test ."
  end

  task :docker do
    unless system("docker version >/dev/null")
      $stderr.puts "*** ERROR ***"
      $stderr.puts "Docker is required to run the integration tests, but it is not available. Exiting"
      $stderr.puts "*************"
      exit 1
    end
  end
end

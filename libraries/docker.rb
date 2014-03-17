module Opscode
  module Docker
    # Load the docker-api gem to use Docker API directly
    def initialize(name, run_context=nil)
      #super
      begin
        require 'docker'
      rescue LoadError
        Chef::Log.error("Missing gem 'docker-api'. Use the default docker recipe to install it first.")
      end
    end
  end
end

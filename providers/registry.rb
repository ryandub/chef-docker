require 'chef/mixin/shell_out'
require 'json'
include Chef::Mixin::ShellOut
include Helpers::Docker

class CommandTimeout < RuntimeError; end

def load_current_resource
  @current_resource = Chef::Resource::DockerRegistry.new(@new_resource.name)
  @current_resource.name(@new_resource.name)
  @current_resource.email(@new_resource.email)
  @current_resource.password(@new_resource.password)
  if logged_in?(@current_resource.name, @current_resource.email)
    @current_resource.exists = true
  end
end

action :login do
  unless @current_resource.exists
    login
    new_resource.updated_by_last_action(true)
  end
end

def docker_cmd(cmd, timeout = new_resource.cmd_timeout)
  execute_cmd('docker ' + cmd, timeout)
end

def execute_cmd(cmd, timeout = new_resource.cmd_timeout)
  Chef::Log.debug('Executing: ' + cmd)
  begin
    shell_out(cmd, :timeout => timeout)
  rescue Mixlib::ShellOut::CommandTimeout
    raise CommandTimeout, <<-EOM

Command timed out:
#{cmd}

Please adjust node registry_cmd_timeout attribute or this docker_registry cmd_timeout attribute if necessary.
EOM
  end
end

def logged_in?(name, email)
  # Read auth file from user home
  dockercfg = ::File.join(ENV['HOME'], '.dockercfg')
  if ::File.exists?(dockercfg)
    auth = JSON.parse(::File.read(dockercfg))
    registry = ::File.join(name, '/v1/')
    if auth.has_key?(registry)
      if auth[registry].has_value?(email) && auth[registry].has_key?('auth')
        true
      end
    end
  end
end

def login
  login_args = cli_args(
    'e' => new_resource.email,
    'p' => new_resource.password,
    'u' => new_resource.username
  )
  docker_cmd("login #{login_args} #{new_resource.server}")
end

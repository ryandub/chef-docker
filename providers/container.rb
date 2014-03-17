include Helpers::Docker
include Opscode::Docker

def load_current_resource
  @current_resource = Chef::Resource::DockerContainer.new(new_resource)
  wait_until_ready!
  ids = Docker::Container.all(:all => true).map { |container| container.id }
  ids.each do |id|
    container = Docker::Container.get(id)
    command = container.json['Config']['Cmd'].join(" ")
    image_id = container.json['Image']
    image_name = container.json['Config']['Image']
    name = container.json['Name'].gsub("/","")
    created = container.json['Created']
    status = status?(container.json['State'])
    if container_image_matches?(image_id, image_name) && container_command_matches_if_exists?(command) && container_name_matches_if_exists?(name)
      Chef::Log.debug('Matched docker container: ' + 'ID: ' + id + ' ImageID: ' + image_id + ' Command: ' + command + ' Name: ' + name)
      @current_resource.container_name(name)
      @current_resource.created(created)
      @current_resource.id(id)
      @current_resource.status(status)
    end
  end
  @current_resource
end

action :commit do
  if exists?
    commit
    new_resource.updated_by_last_action(true)
  end
end

action :cp do
  if exists?
    cp
    new_resource.updated_by_last_action(true)
  end
end

action :export do
  if exists?
    export
    new_resource.updated_by_last_action(true)
  end
end

action :kill do
  if running?
    kill
    new_resource.updated_by_last_action(true)
  end
end

action :redeploy do
  stop if running?
  remove if exists?
  run
  new_resource.updated_by_last_action(true)
end

action :remove do
  if running?
    stop
    new_resource.updated_by_last_action(true)
  end
  if exists?
    remove
    new_resource.updated_by_last_action(true)
  end
end

action :restart do
  if exists?
    restart
    new_resource.updated_by_last_action(true)
  end
end

action :run do
  unless running?
    if exists?
      start
    else
      run
    end
    new_resource.updated_by_last_action(true)
  end
end

action :start do
  unless running?
    start
    new_resource.updated_by_last_action(true)
  end
end

action :stop do
  if running?
    stop
    new_resource.updated_by_last_action(true)
  end
end

action :wait do
  if running?
    wait
    new_resource.updated_by_last_action(true)
  end
end

def cidfile
  if service?
    new_resource.cidfile || "/var/run/#{service_name}.cid"
  else
    new_resource.cidfile
  end
end

def commit
  options = {
    'author' => new_resource.author,
    'tag' => new_resource.tag,
    'repo' => new_resource.repo,
    'm' => new_resource.message,
    'run' => new_resource.run
  }

  image = current_resource.commit(options = options)
  Chef::Log.debug("Docker container #{current_resource.id} committed to image #{image.id}.")
end

def container_command_matches_if_exists?(command)
  return false if new_resource.command && command != new_resource.command
  true
end

def container_id_matches?(id)
  id.start_with?(new_resource.id)
end

def container_image_matches?(image_id, image_name)
  image_id.include?(new_resource.image) || image_name.include?(new_resource.image)
end

def container_name_matches_if_exists?(name)
  return false if new_resource.container_name && new_resource.container_name != name
  true
end

def container_name
  if service?
    new_resource.container_name || new_resource.image.gsub(/^.*\//, '')
  else
    new_resource.container_name
  end
end

# def container_ports_match(port)
#   return false if

def cp
  File.open(new_resource.destination, 'w') do |f|
    container = Docker::Container.get(@current_resource.id)
    container.copy(new_resource.source) { |chunk| file.write(chunk) }
  end
end

def exists?
  @current_resource.id
end

def export
  File.open(new_resource.destination, 'w') do |f|
    container = Docker::Container.get(@current_resource.id)
    container.export { |chunk| file.write(chunk) }
  end
end

def get_ports
  ports = {}
  exposed_ports = {}
  published_ports = {}
  [*new_resource.port].each do |port|
    # If port is a Fixnum, don't publish.
    if port.is_a?(Fixnum)
      exposed_ports["#{port}/tcp"] = {}
    elsif port.include?(":")
      port = port.split(":")
      # Allow binding by IP addresses.
      if port[0].include?(".")
        hostIP = port[0]
        port[0] = port[1]
        port[1] = port[2]
      end
      exposed_ports["#{port[1]}/tcp"] = {}
      # If port was ':<port>' publish the same port on the host.
      if port[0].empty?
        published_ports["#{port[1]}/tcp"] = [{"HostPort" => "#{port[1]}"}]
      else
        if hostIP
          published_ports["#{port[1]}/tcp"] = [{"HostPort" => "#{port[0]}",
                                                "HostIp" => "#{hostIP}"}]
        else
          published_ports["#{port[1]}/tcp"] = [{"HostPort" => "#{port[0]}"}]
        end
      end
    else
      exposed_ports["#{port}/tcp"] = {}
    end
  end
  ports['exposed_ports'] = exposed_ports
  ports['published_ports'] = published_ports
  return ports
end

def get_volumes
  volumes = {}
  cont_volumes = [*new_resource.volume].map { |v| v.split(":")[1] }
  cont_volumes.each do |v|
    volumes[v] = {}
  end
  return volumes
end

def kill
  if service?
    service_stop
  else
    container = Docker::Container.get(@current_resource.id)
    container.kill
  end
end

def remove
  container = Docker::Container.get(@current_resource.id)
  container.delete
  service_remove if service?
end

def restart
  if service?
    service_restart
  else
    container = Docker::Container.get(@current_resource.id)
    container.restart
  end
end

def run

  attach = new_resource.detach ? false : true

  ports = get_ports
  volumes = get_volumes
  command = new_resource.command.split(" ") unless new_resource.command.nil?

  create_options = {
    'AttachStdin' => attach,
    'AttachStdout' => attach,
    'AttachStdErr' => attach,
    'Cmd' => command,
    'Dns' => new_resource.dns,
    'Env' => [*new_resource.env],
    'ExposedPorts' => ports['exposed_ports'],
    'Entrypoint' => new_resource.entrypoint,
    'Hostname' => new_resource.hostname,
    'Image' => new_resource.image,
    'Memory' => new_resource.memory,
    'name' => new_resource.container_name,
    'OpenStdin' => new_resource.stdin,
    'Tty' => new_resource.tty,
    'User' => new_resource.user || "",
    'Volumes' => volumes,
    'VolumesFrom' => new_resource.volumes_from || "",
    'WorkingDir' => new_resource.working_directory || ""
  }

  container = Docker::Container.create(create_options)

  start_options = {
    'Binds' => [*new_resource.volume],
    'LxcConf' => [*new_resource.lxc_conf],
    'PortBindings' => ports['published_ports'],
    'PublishAllPorts' => new_resource.publish_exposed_ports,
    'Privileged' => new_resource.privileged
  }

  container.start(start_options)

  new_resource.id(container.id)
  service_create if service?
end

def running?
  return true if (@current_resource.status && @current_resource.status != "stopped")
  return false
end

def service?
  new_resource.init_type
end

def service_action(actions)
  if new_resource.init_type == 'runit'
    runit_service service_name do
      run_template_name 'docker-container'
      action actions
    end
  else
    service service_name do
      case new_resource.init_type
      when 'systemd'
        provider Chef::Provider::Service::Systemd
      when 'upstart'
        provider Chef::Provider::Service::Upstart
      end
      supports :status => true, :restart => true, :reload => true
      action actions
    end
  end
end

def service_create
  case new_resource.init_type
  when 'runit'
    service_create_runit
  when 'systemd'
    service_create_systemd
  when 'sysv'
    service_create_sysv
  when 'upstart'
    service_create_upstart
  end
end

def service_create_runit
  runit_service service_name do
    cookbook new_resource.cookbook
    default_logger true
    options(
      'service_name' => service_name
    )
    run_template_name service_template
  end
end

def service_create_systemd
  template "/usr/lib/systemd/system/#{service_name}.socket" do
    if new_resource.socket_template.nil?
      source 'docker-container.socket.erb'
    else
      source new_resource.socket_template
    end
    cookbook new_resource.cookbook
    mode '0644'
    owner 'root'
    group 'root'
    variables(
      :service_name => service_name,
      :sockets => sockets
    )
    not_if port.empty?
  end

  template "/usr/lib/systemd/system/#{service_name}.service" do
    source service_template
    cookbook new_resource.cookbook
    mode '0644'
    owner 'root'
    group 'root'
    variables(
      :cmd_timeout => new_resource.cmd_timeout,
      :service_name => service_name
    )
  end

  service_action([:start, :enable])
end

def service_create_sysv
  template "/etc/init.d/#{service_name}" do
    source service_template
    cookbook new_resource.cookbook
    mode '0755'
    owner 'root'
    group 'root'
    variables(
      :cmd_timeout => new_resource.cmd_timeout,
      :service_name => service_name
    )
  end

  service_action([:start, :enable])
end

def service_create_upstart
  # The upstart init script requires inotifywait, which is in inotify-tools
  package 'inotify-tools'

  template "/etc/init/#{service_name}.conf" do
    source service_template
    cookbook new_resource.cookbook
    mode '0600'
    owner 'root'
    group 'root'
    variables(
      :cmd_timeout => new_resource.cmd_timeout,
      :service_name => service_name
    )
  end

  service_action([:start, :enable])
end

def service_name
  container_name
end

def service_remove
  case new_resource.init_type
  when 'runit'
    service_remove_runit
  when 'systemd'
    service_remove_systemd
  when 'sysv'
    service_remove_sysv
  when 'upstart'
    service_remove_upstart
  end
end

def service_remove_runit
  runit_service service_name do
    action :disable
  end
end

def service_remove_systemd
  service_action([:stop, :disable])

  %w{service socket}.each do |f|
    file "/usr/lib/systemd/system/#{service_name}.#{f}" do
      action :delete
    end
  end
end

def service_remove_sysv
  service_action([:stop, :disable])

  file "/etc/init.d/#{service_name}" do
    action :delete
  end
end

def service_remove_upstart
  service_action([:stop, :disable])

  file "/etc/init/#{service_name}" do
    action :delete
  end
end

def service_restart
  service_action([:restart])
end

def service_start
  service_action([:start])
end

def service_stop
  service_action([:stop])
end

def service_template
  return new_resource.init_template unless new_resource.init_template.nil?
  case new_resource.init_type
  when 'runit'
    'docker-container'
  when 'systemd'
    'docker-container.service.erb'
  when 'upstart'
    'docker-container.conf.erb'
  when 'sysv'
    'docker-container.sysv.erb'
  end
end

def sockets
  return [] if port.empty?
  [*port].map { |p| p.gsub!(/.*:/, '') }
end

def start
  if service?
    service_create
  else

    ports = get_ports

    start_options = {
      'Binds' => [*new_resource.volume],
      'LxcConf' => [*new_resource.lxc_conf],
      'PortBindings' => ports['published_ports'],
      'PublishAllPorts' => new_resource.publish_exposed_ports,
      'Privileged' => new_resource.privileged
    }

    container = Docker::Container.get(@current_resource.id)
    container.start(start_options)
  end
end

def status?(state)
  return "ghost" if state['Ghost']
  return "running" if state['Running']
  return "stopped" if !state['Running']
end

def stop
  stop_args = cli_args(
    't' => new_resource.cmd_timeout
  )
  if service?
    service_stop
  else
    container = Docker::Container.get(@current_resource.id)
    container.stop
  end
end

def wait
  container = Docker::Container.get(@current_resource.id)
  container.wait
end

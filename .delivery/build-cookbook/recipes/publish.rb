################################################################################
# Welcome to the publish phase
#
# This is run as the delivery build user and is where most of the magic happens.
# Here, we need to build our shipable package and put it somewhere to consume
# it.
#
#
################################################################################

include_recipe 'chef-sugar::default'
include_recipe 'delivery-truck::publish'

load_delivery_chef_config

ENV['AWS_CONFIG_FILE'] = File.join(node['delivery']['workspace']['root'], 'aws_config')

require 'chef/provisioning/aws_driver'
with_driver 'aws'

software_version = Time.now.strftime('%F_%H%M')
build_name = "#{node['delivery']['change']['project']}-#{software_version}"
artifact_bucket = "#{node['delivery']['change']['project'].gsub(/_/, '-')}-artifacts"

aws_s3_bucket artifact_bucket do
  enable_website_hosting false
  website_options :index_document => {
    :suffix => "index.html"
  },
  :error_document => {
    :key => "not_found.html"
  }
end

include_recipe 'cia_infra::bundler_install_deps'

file File.join(node['delivery_builder']['repo'], 'version.txt') do
  content build_name
end

execute "create the tarball" do
  command "tar cvzf #{node['delivery']['workspace']['cache']}/#{build_name}.tar.gz --exclude .git --exclude .delivery ."
  cwd node['delivery']['workspace']['repo']
end

execute "upload the tarball" do
  command "aws s3 cp --acl public-read #{node['delivery']['workspace']['cache']}/#{build_name}.tar.gz s3://#{artifact_bucket}/"
  cwd node['delivery']['workspace']['repo']
end

checksum = ''
ruby_block 'get checksum' do
  block do
    checksum = `shasum -a 256 #{node['delivery']['workspace']['cache']}/#{build_name}.tar.gz`.split[0]
  end
end

ruby_block 'upload data bag' do
  block do
    load_delivery_chef_config
    dbag = Chef::DataBag.new
    dbag.name(node['delivery']['change']['project'])
    dbag.save
    dbag_data = {
      'id' => software_version,
      'version' => software_version,
      'artifact_location' => "https://s3.amazonaws.com/#{artifact_bucket}/#{build_name}.tar.gz",
      'artifact_checksum' => checksum,
      'artifact_type' => 'http',
      'delivery_data' => node['delivery']
    }
    dbag_item = Chef::DataBagItem.new
    dbag_item.data_bag(dbag.name)
    dbag_item.raw_data = dbag_data
    dbag_item.save
  end
end

ruby_block 'set the version in the env' do
  block do
    load_delivery_chef_config
    begin
      to_env = Chef::Environment.load(get_acceptance_environment)
    rescue Net::HTTPServerException => http_e
      raise http_e unless http_e.response.code == "404"
      Chef::Log.info("Creating Environment #{get_acceptance_environment}")
      to_env = Chef::Environment.new()
      to_env.name(get_acceptance_environment)
      to_env.create
    end

    to_env.override_attributes['applications'] ||= {}
    to_env.override_attributes['applications'][node['delivery']['change']['project']] = software_version
    to_env.save
    ::Chef::Log.info("Set #{node['delivery']['change']['project']}'s version to #{software_version} in #{node['delivery']['change']['project']}.")
  end
end

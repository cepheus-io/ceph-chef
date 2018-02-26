#
# Author: Hans Chris Jones <chris.jones@lambdastack.io>
# Copyright 2017, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# NOTE: Only run this recipe after Ceph is running and *ONLY* on Mon nodes.

directory "/var/lib/ceph/mgr/#{node['ceph']['cluster']}-#{node['hostname']}" do
  owner node['ceph']['owner']
  group node['ceph']['group']
  mode node['ceph']['mode']
  recursive true
  action :create
  not_if "test -d /var/lib/ceph/mgr/#{node['ceph']['cluster']}-#{node['hostname']}"
end

keyring = "/var/lib/ceph/mgr/#{node['ceph']['cluster']}-#{node['hostname']}/keyring"

execute 'format ceph-mgr-secret as keyring' do
  command lazy { "ceph-authtool --create-keyring #{keyring} --name=mgr.#{node['hostname']} --add-key=#{node['ceph']['monitor-secret']} --cap mon 'allow profile mgr' > #{keyring}" }
  creates keyring
  only_if { ceph_chef_mgr_secret }
  not_if "test -s #{keyring}"
  sensitive true if Chef::Resource::Execute.method_defined? :sensitive
end

execute 'generate ceph-mgr-secret as keyring' do
  command lazy { "ceph-authtool --create-keyring #{keyring} --name=mgr.#{node['hostname']} --gen-key --cap mon 'allow profile mgr'" }
  creates keyring
  not_if { ceph_chef_mgr_secret }
  not_if "test -s #{keyring}"
  notifies :create, 'ruby_block[save ceph_chef_mgr_secret]', :immediately
  sensitive true if Chef::Resource::Execute.method_defined? :sensitive
end

ruby_block 'save ceph_chef_mgr_secret' do
  block do
    fetch = Mixlib::ShellOut.new("ceph-authtool #{keyring} --print-key --name=mgr.#{node['hostname']}")
    fetch.run_command
    key = fetch.stdout
    node.normal['ceph']['mgr-secret'] = key.delete!("\n")
  end
  action :nothing
end

execute "chown #{keyring}" do
  command "chown #{node['ceph']['owner']}:#{node['ceph']['group']} #{keyring}"
end

execute "chmod #{keyring}" do
  command "chmod 0600 #{keyring}"
end

service 'ceph_mgr' do
  case node['ceph']['radosgw']['init_style']
  when 'upstart'
    service_name 'ceph-mgr-all-starter'
    provider Chef::Provider::Service::Upstart
  else
    service_name "ceph-mgr@#{node['hostname']}"
  end
  action [:enable, :start]
  supports :restart => true
end

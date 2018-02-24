#
# Author:: Hans Chris Jones <chris.jones@lambdastack.io>
# Cookbook Name:: ceph
# Recipe:: osd
#
# Copyright 2018, LambdaStack
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

# NOTE: Example of an OSD device to add. You can find other examples in the OSD attribute file and the
# environment file. The device and the journal should be the same IF you wish the data and journal to be
# on the same device (ceph default). However, if you wish to have the data on device by itself (i.e., HDD)
# and the journal on a different device (i.e., SSD) then give the cooresponding device name for the given
# entry (device or journal). The command 'ceph-disk prepare' will keep track of partitions for journals
# so DO NOT create a device with partitions already configured and then attempt to use that as the journal:
# device value. Journals are raw devices (no file system like xfs).
#
# "osd": {
#    "devices": [
#        {
#            "type": "hdd",
#            "data": "/dev/sdb",
#            "data_type": "hdd",
#            "journal": "/dev/sdf",
#            "journal_type": "ssd",
#            "encrypted": false,
#            "status": ""
#        }
#    ]
# }

include_recipe 'ceph-chef'
include_recipe 'ceph-chef::osd_install'

# Disk utilities used
package 'gdisk' do
  action :upgrade
end

package 'cryptsetup' do
  action :upgrade
  only_if { node['ceph']['osd']['dmcrypt'] }
end

# Create the scripts directory within the /etc/ceph directory. This is not standard Ceph. It's included here as
# a place to hold helper scripts mainly for OSD and Journal maintenance
directory '/etc/ceph/scripts' do
  mode node['ceph']['mode']
  recursive true
  action :create
  not_if 'test -d /etc/ceph/scripts'
end

include_recipe 'ceph-chef::bootstrap_osd_key'

# Calling ceph-volume. Ceph-disk was deprecated.
# IMPORTANT:
#  - Always use the default path for OSD (i.e. /var/lib/ceph/osd/$cluster-$id)
if node['ceph']['osd']['devices']
  devices = node['ceph']['osd']['devices']
  devices = Hash[(0...devices.size).zip devices] unless devices.is_a? Hash

  devices.each do |index, osd_device|
    # NOTE: May now be able to query the device instead of setting 'deployed' flag now that ceph-volume is being used...
    if !node['ceph']['osd']['devices'][index]['status'].nil? && node['ceph']['osd']['devices'][index]['status'] == 'deployed'
      Log.info("osd: osd device '#{osd_device}' has already been setup.")
      next
    end

    # if the 'encrypted' attribute is true then apply flag. This will encrypt the data at rest.
    # IMPORTANT: More work needs to be done on solid key management for very high security environments.
    dmcrypt = osd_device['encrypted'] == true ? '--dmcrypt' : ''

    # set the storage type for the OSD data
    # if none is specified use the default specified by upstream (currently bluestore)
    osd_type = if node['ceph']['osd']['type'].eql?('bluestore')
      osd_journal = ''
      ''
    elsif node['ceph']['osd']['type'].eql?('filestore')
      osd_journal = "#{osd_device['journal']}"
      '--filestore'
    end

    # Create OSD using ceph-volume. Ceph-disk is deprecated. 'osd_type' and 'osd_journal' will be '' by default.
    execute "ceph-volume on #{osd_device['data']}" do
      command <<-EOH
        ceph-volume lvm create #{osd_type} --data #{osd_device['data']} #{osd_journal}
        sleep 3
      EOH
      user node['ceph']['owner']
      action :run
      notifies :create, "ruby_block[save osd_device status #{index}]", :immediately
    end

    # Add this status to the node env so that we can implement recreate and/or delete functionalities in the future.
    ruby_block "save osd_device status #{index}" do
      block do
        node.normal['ceph']['osd']['devices'][index]['status'] = 'deployed'
      end
      action :nothing
    end
  end
else
  Log.info("node['ceph']['osd']['devices'] empty")
end

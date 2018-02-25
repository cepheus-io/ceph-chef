#
# Author:: Hans Chris Jones <chris.jones@lambdastack.io>
# Cookbook Name:: ceph
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

# This recipe will add OSDs once the physical device has been added.

# IMPORTANT: Use this recipe *ONLY* if you just want to add OSD devices and *NOT* have them included as part of the
# actual ['ceph']['osd']['devices'] array. *IF* you want to add the devices on a more permanent basis then *ADD* the
# given device to the ['ceph']['osd']['devices'] array and call *OSD.rb* recipe instead!

# TODO: Add an osd provider that creates an osd, removes an osd and starts/stops an osd.
# It can also reweight an osd so as to bring down a number of them gracefully so that they
# can be safely removed instead of just stopping the osd and removing from the crush map.

if node['ceph']['osd']['add']
  devices = node['ceph']['osd']['add']

  devices = Hash[(0...devices.size).zip devices] unless devices.is_a? Hash

  devices.each do |index, osd_device|
    partitions = 1

    unless osd_device['status'].nil? || osd_device['status'] != 'deployed'
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
  Log.info("node['ceph']['osd']['add'] empty")
end

# PeerCastStation, a P2P streaming servent.
# Copyright (C) 2011 Ryuichi Sakamoto (kumaryu@kumaryu.net)
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
$: << File.join(File.dirname(__FILE__), '..', 'PeerCastStation.Core', 'bin', 'Debug')
require 'PeerCastStation.Core.dll'
require 'test/unit'
using_clr_extensions PeerCastStation::Core

class MockYellowPageFactory
  include PeerCastStation::Core::IYellowPageFactory
  
  def name
    'MockYellowPage'
  end
  
  def create(name, uri)
    MockYellowPage.new(name, uri)
  end
end

class MockYellowPage
  include PeerCastStation::Core::IYellowPage
  def initialize(name, uri)
    @name = name
    @uri = uri
    @log = []
  end
  attr_reader :name, :uri, :log
  
  def find_tracker(channel_id)
    @log << [:find_tracker, channel_id]
    addr = System::Net::IPEndPoint.new(System::Net::IPAddress.parse('127.0.0.1'), 7147)
    System::Uri.new("mock://#{addr}")
  end
  
  def list_channels
    raise NotImplementError, 'Not implemented yet'
  end
  
  def announce(channel)
    raise NotImplementError, 'Not implemented yet'
  end
end

class MockSourceStreamFactory
  include PeerCastStation::Core::ISourceStreamFactory
  def initialize
    @log = []
  end
  attr_reader :log
  
  def name
    'MockSourceStream'
  end
  
  def create(channel, uri)
    @log << [:create, channel, uri]
    MockSourceStream.new(channel, uri)
  end
end

class MockSourceStream
  include PeerCastStation::Core::ISourceStream
  
  def initialize(channel, tracker)
    @channel = channel
    @tracker = tracker
    @status_changed = []
    @status = PeerCastStation::Core::SourceStreamStatus.idle
    @log = []
  end
  attr_reader :log, :tracker, :channel, :status

  def add_StatusChanged(handler)
    @status_changed << handler
  end
  
  def remove_StatusChanged(handler)
    @status_changed.delete(handler)
  end

  def post(from, packet)
    @log << [:post, from, packet]
  end
  
  def start
    @log << [:start]
  end
  
  def reconnect
    @log << [:reconnect]
  end
  
  def close
    @log << [:close]
  end
end

class MockOutputStream
  include PeerCastStation::Core::IOutputStream
  
  def initialize(type=0)
    @type = type
    @remote_endpoint = nil
    @upstream_rate = 0
    @is_local = false
    @log = []
  end
  attr_reader :log
  attr_accessor :remote_endpoint, :upstream_rate, :is_local

  def output_stream_type
    @type
  end

  def post(from, packet)
    @log << [:post, from, packet]
  end
  
  def start
    @log << [:start]
  end
  
  def close
    @log << [:close]
  end
end

class MockOutputStreamFactory
  include PeerCastStation::Core::IOutputStreamFactory
  
  def initialize
    @log = []
  end
  attr_reader :log
  
  def name
    'MockOutputStream'
  end
  
  def ParseChannelID(header)
    @log << [:parse_channel_id, header]
    header = header.to_a.pack('C*')
    if /^mock ([a-fA-F0-9]{32})/=~header then
      System::Guid.new($1.to_clr_string)
    else
      nil
    end
  end
  
  def create(stream, remote_endpoint, channel_id, header)
    @log << [:create, stream, remote_endpoint, channel_id, header]
    MockOutputStream.new
  end
end
  
class TC_CoreContent < Test::Unit::TestCase
  def test_construct
    obj = PeerCastStation::Core::Content.new(10, 'content')
    assert_equal(10, obj.position)
    assert_equal('content'.unpack('C*'), obj.data)
  end
end

class TC_CoreChannelInfo < Test::Unit::TestCase
  def test_construct
    obj = PeerCastStation::Core::ChannelInfo.new(System::Guid.empty)
    assert_equal(System::Guid.empty, obj.ChannelID)
    assert_nil(obj.tracker)
    assert_equal('', obj.name)
    assert_not_nil(obj.extra)
    assert_equal(0, obj.extra.count)
  end
  
  def test_changed
    log = []
    obj = PeerCastStation::Core::ChannelInfo.new(System::Guid.empty)
    obj.property_changed {|sender, e| log << e.property_name }
    obj.name = 'test'
    obj.tracker = System::Uri.new('mock://127.0.0.1:7147')
    obj.extra.add(PeerCastStation::Core::Atom.new(PeerCastStation::Core::ID4.new('test'.to_clr_string), 'foo'.to_clr_string))
    assert_equal(3, log.size)
    assert_equal('Name',    log[0])
    assert_equal('Tracker', log[1])
    assert_equal('Extra',   log[2])
  end
end

class TC_OutputStreamCollection < Test::Unit::TestCase
  def test_count_relaying
    collection = PeerCastStation::Core::OutputStreamCollection.new
    assert_equal(0, collection.count)
    assert_equal(0, collection.count_relaying)
    collection.add(MockOutputStream.new(PeerCastStation::Core::OutputStreamType.play))
    collection.add(MockOutputStream.new(PeerCastStation::Core::OutputStreamType.relay))
    collection.add(MockOutputStream.new(PeerCastStation::Core::OutputStreamType.metadata))
    collection.add(MockOutputStream.new(
      PeerCastStation::Core::OutputStreamType.play |
      PeerCastStation::Core::OutputStreamType.relay))
    collection.add(MockOutputStream.new(
      PeerCastStation::Core::OutputStreamType.relay |
      PeerCastStation::Core::OutputStreamType.metadata))
    collection.add(MockOutputStream.new(
      PeerCastStation::Core::OutputStreamType.play |
      PeerCastStation::Core::OutputStreamType.metadata))
    collection.add(MockOutputStream.new(
      PeerCastStation::Core::OutputStreamType.play |
      PeerCastStation::Core::OutputStreamType.relay |
      PeerCastStation::Core::OutputStreamType.metadata))
    assert_equal(7, collection.count)
    assert_equal(4, collection.count_relaying)
  end

  def test_count_playing
    collection = PeerCastStation::Core::OutputStreamCollection.new
    assert_equal(0, collection.count)
    assert_equal(0, collection.count_playing)
    collection.add(MockOutputStream.new(PeerCastStation::Core::OutputStreamType.play))
    collection.add(MockOutputStream.new(PeerCastStation::Core::OutputStreamType.relay))
    collection.add(MockOutputStream.new(PeerCastStation::Core::OutputStreamType.metadata))
    collection.add(MockOutputStream.new(
      PeerCastStation::Core::OutputStreamType.play |
      PeerCastStation::Core::OutputStreamType.relay))
    collection.add(MockOutputStream.new(
      PeerCastStation::Core::OutputStreamType.relay |
      PeerCastStation::Core::OutputStreamType.metadata))
    collection.add(MockOutputStream.new(
      PeerCastStation::Core::OutputStreamType.play |
      PeerCastStation::Core::OutputStreamType.metadata))
    collection.add(MockOutputStream.new(
      PeerCastStation::Core::OutputStreamType.play |
      PeerCastStation::Core::OutputStreamType.relay |
      PeerCastStation::Core::OutputStreamType.metadata))
    assert_equal(7, collection.count)
    assert_equal(4, collection.count_playing)
  end
end


#   FELHelpers.rb
#   Copyright 2014 Bartosz Jankowski
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

class String
  def camelize
      self.gsub(/\/(.?)/) { "::" + $1.upcase }.gsub(/(^|_)(.)/) { $2.upcase }
  end
end

class Symbol
  def camelize
    self.to_s.camelize
  end
end

# Convert board id to string
# @param id [Integer] board id
# @return [String] board name or ? if unknown
def board_id_to_str(id)
  case (id >> 8 & 0xFFFF)
  when 0x1610 then "Allwinner A31s"
  when 0x1623 then "Allwinner A10"
  when 0x1625 then "Allwinner A13"
  when 0x1633 then "Allwinner A31"
  when 0x1639 then "Allwinner A80"
  when 0x1650 then "Allwinner A23"
  when 0x1651 then "Allwinner A20"
  else
    "?"
  end
end

# Convert tag mask to string
# @param tags [Integer] tag flag
# @return [String] human readable tags delimetered by |
def tags_to_s(tags)
  r = ""
  AWTags.each do |k,v|
    next if tags>0 && k == :none
    r << "|" if r.length>0 && tags & v == v
    r << "#{k.to_s}" if tags & v == v
  end
  r
end

# Decode packet
# @param packet [String] packet data without USB header
# @param dir [Symbol] last connection direction (`:read` or `:write`)
# @return [Symbol] direction of the packet
def debug_packet(packet, dir)
  if packet[0..3] == "AWUC" && packet.length == 32
    p = AWUSBRequest.read(packet)
    print "--> (% 5d) " % packet.length
    case p.cmd
    when USBCmd[:read]
      print "USBRead".yellow
      dir = :read
    when USBCmd[:write]
      print "USBWrite".yellow
      dir = :write
    else
      print "AWUnknown (0x%x)".red % p.type
    end
    puts "\t(Prepare for #{dir.to_s} of #{p.len} bytes)"
    #puts p.inspect
  elsif packet[0..7] == "AWUSBFEX"
    p = AWFELVerifyDeviceResponse.read(packet)
    puts "<-- (% 5d) " % packet.length << "AWFELVerifyDeviceResponse".
    yellow << "\t%s, FW: %d, mode: %s" % [ board_id_to_str(p.board), p.fw,
      AWDeviceMode.key(p.mode) ]
  elsif packet[0..3] == "AWUS" && packet.length == 13
    p = AWUSBResponse.read(packet)
    puts "<-- (% 5d) " % packet.length << "AWUSBResponse".yellow <<
    "\t0x%x, status %s" % [ p.tag, AWUSBStatus.key(p.csw_status) ]
  else
    return :unk if dir == :unk
    print (dir == :write ? "--> " : "<-- ") << "(% 5d) " % packet.length
    if packet.length == 16
      p = AWFELMessage.read(packet)
      case p.cmd
      when FELCmd[:verify_device] then puts "FELVerifyDevice"
        .yellow <<  " (0x#{FELCmd[:verify_device]})"
      when FESCmd[:transmite]
        p = AWFELFESTrasportRequest.read(packet)
        puts "FES#{FESCmd.key(p.cmd).camelize}: ".yellow <<
        FESTransmiteFlag.key(p.direction).to_s <<
        ", index #{p.media_index}, addr 0x%08x, len %d" % [p.address,
          p.len]
      when FESCmd[:download], FESCmd[:verify_status], FELCmd[:download],
        FELCmd[:upload], FESCmd[:run], FELCmd[:run]
        p = AWFELMessage.read(packet)
        print "FEL#{FELCmd.key(p.cmd).camelize}".
        yellow if FELCmd.has_value?(p.cmd)
        print "FES#{FESCmd.key(p.cmd).camelize}".
        yellow if FESCmd.has_value?(p.cmd)
        puts " (0x%.2X)\n"  % p.cmd <<
        "\ttag: #{p.tag}, %d bytes @ 0x%08x" % [p.len, p.address] <<
        ", flags #{tags_to_s(p.flags)} (0x%04x)" % p.flags
      else
        print "FEL#{FELCmd.key(p.cmd).camelize}".
        yellow if FELCmd.has_value?(p.cmd)
        print "FES#{FESCmd.key(p.cmd).camelize}".
        yellow if FESCmd.has_value?(p.cmd)
        if FESCmd.has_value?(p.cmd) || FELCmd.has_value?(p.cmd)
          puts " (0x%.2X): "  % p.cmd << "#{packet.to_hex_string[0..46]}"
        else
          print "\n"
          Hexdump.dump(packet[0..63])
        end
      end
    elsif packet.length == 8
      p = AWFELStatusResponse.read(packet)
      puts "FELStatusResponse\t".yellow <<
      "mark #{p.mark}, tag #{p.tag}, state #{p.state}"
    else
      print "\n"
      Hexdump.dump(packet[0..63])
    end
  end
  dir
end

# Decode USBPcap packets exported from Wireshark in C header format
# e.g. {
# 0x1c, 0x00, 0x10, 0x60, 0xa9, 0x95, 0x00, 0xe0, /* ...`.... */
# 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, /* ........ */
# 0x01, 0x01, 0x00, 0x0d, 0x00, 0x80, 0x02, 0x00, /* ........ */
# 0x00, 0x00, 0x00, 0x02                          /* .... */
# };
# @param file [String] file name
def debug_packets(file)
  return if file.nil?
  print "Processing...".green
  packets = Array.new
  contents = File.read(file)
  i = 0
  contents.scan(/^.*?{(.*?)};/m) do |packet|
    i+=1
    hstr = ""
    packet[0].scan(/0x([0-9A-Fa-f]{2})/m) { |hex| hstr << hex[0] }
    print "\rProcessing...#{i} found".green
    #Strip USB header
    begin
      packets << hstr.to_byte_string[27..-1] if hstr.to_byte_string[27..-1] != nil
    rescue RuntimeError => e
      puts "Error : (#{e.message}) at #{e.backtrace[0]}"
      puts "Failed to decode packet: (#{hstr.length / 2}), #{hstr}"
    end
  end
  puts

  dir = :unk
  packets.each do |packet|
    next if packet.length < 4
    dir = debug_packet(packet, dir)
  end
end

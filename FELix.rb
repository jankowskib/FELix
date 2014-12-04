#!/bin/env ruby
#   FELix.rb
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
require 'hex_string'
require 'hexdump'
require 'colorize'
require 'optparse'
require 'libusb'
require 'bindata'

require_relative 'FELStructs'

#Routines
# 1. Write
# --> AWUSBRequest(AW_USB_WRITE, len)
# --> WRITE(len)
# <-- READ(13) -> AWUSBResponse
# (then)
# 2. Read (--> send | <-- recv)
# --> AWUSBRequest(AW_USB_READ, len)
# <-- READ(len)
# <-- READ(13) -> AWUSBResponse

# Flash process (A31s)
# 1. FEL_R_VERIFY_DEVICE
# 2. FEL_RW_FES_TRANSMITE: Get FES (upload flag)
# 3. FEL_R_VERIFY_DEVICE
# 4. FEL_RW_FES_TRANSMITE: Flash new FES (download flag)
# 5. FEX_CMD_FES_DOWN (No write) (00 00 00 00 | 00 00 10 00 | 00 00 04 7f 01 00) [SUNXI_EFEX_TAG_ERASE|SUNXI_EFEX_TAG_FINISH]
# 6. FEL_R_VERIFY_DEVICE
# 7. FEX_CMD_FES_VERIFY_STATUS (tail 04 7f 00 00) [SUNXI_EFEX_TAG_ERASE]
# 8. FEX_CMD_FES_DOWN (write sunxi_mbr.fex, whole file at once => 16384 * 4 copies bytes size)
#                                  (00 00 00 00 00 00 00 00 01 00 01 7f 01 00) [SUNXI_EFEX_TAG_MBR|SUNXI_EFEX_TAG_FINISH]
# 9. FEX_CMD_FES_VERIFY_STATUS (tail 01 7f 00 00) [SUNXI_EFEX_TAG_MBR]
# (...)


# 0x206 data80
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |00 00 00 00| 10 00 00 00 |04 7f 01 00  SUNXI_EFEX_TAG_ERASE|SUNXI_EFEX_TAG_FINISH
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |00 00 00 00| 00 00 01 00 |01 7f 01 00  SUNXI_EFEX_TAG_MBR|SUNXI_EFEX_TAG_FINISH
# Then following sequence (write in chunks of 128 bytes => becase of FES_MEDIA_INDEX_LOG) writing partitons...
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |00 80 00 00| 00 00 01 00 |00 00 00 00
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |80 80 00 00| 00 00 01 00 |00 00 00 00
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |00 81 00 00| 00 00 01 00 |00 00 00 00
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |80 81 00 00| 00 00 01 00 |00 00 00 00
# -->                                                 ...
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |00 a3 00 00| 00 00 01 00 |00 00 00 00
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |80 a3 00 00| 00 00 01 00 |00 00 00 00
# -->                                                 ...
# --> (16) FEX_CMD_FES_DOWN (0x206): 06 02 00 00 |00 a4 00 00| 00 04 00 00 |00 00 01 00 SUNXI_EFEX_TAG_FINISH

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

# Decode packet
# @param packet [String] packet data without USB header
# @param dir [Symbol] last connection direction (`:read` or `:write`)
# @return [Symbol] direction of the packet
def debug_packet(packet, dir)
	if packet[0..3] == "AWUC" && packet.length == 32
		p = AWUSBRequest.read(packet)
		print "--> #{p.magic} (#{p.len}, #{p.len2}):\t"
		case p.cmd
		when AWUSBCommand::AW_USB_READ
			puts "AW_USB_READ"
			dir = :read
		when AWUSBCommand::AW_USB_WRITE
			puts "AW_USB_WRITE"
			dir = :write
		else
			puts "AW_UNKNOWN (0x%x)" % p.type
		end
		# puts packet.inspect
	elsif packet[0..4] == "AWUS\x0"
		p = AWUSBResponse.read(packet)
		puts "<-- #{p.magic} tag 0x%x, status 0x%x" % [p.tag, p.csw_status]
	elsif packet[0..7] == "AWUSBFEX"
		p = AWFELVerifyDeviceResponse.read(packet)
		puts "<-- AWFELVerifyDeviceResponse: %s, FW: %d, mode: %s" % [
			board_id_to_str(p.board), p.fw, FEL_DEVICE_MODE.key(p.mode)]
	else
		return :unk if dir == :unk
		print (dir == :write ? "--> " : "<-- ") << "(#{packet.length}) "
		if packet.length == 16
			p = AWFELMessage.read(packet)
			case p.cmd
			when AWCOMMAND[:FEL_R_VERIFY_DEVICE] then puts "FEL_R_VERIFY_DEVICE"
			when AWCOMMAND[:FEX_CMD_FES_RW_TRANSMITE]
				puts "#{AWCOMMAND.key(p.cmd)}: " << (p.data_tag and
					FESTransmiteFlag::FES_W_DOU_DOWNLOAD ? "FES_TRANSMITE_W_DOU_DOWNLOAD":
				 	(p.data_tag && FESTransmiteFlag::FES_R_DOU_UPLOAD ?
					"FES_TRANSMITE_R_DOU_UPLOAD" : "FES_TRANSMITE_UNKNOWN #{p.flag}"))
			else
				puts "#{AWCOMMAND.key(p.cmd)}: (0x%.2X):" <<
				"#{packet.to_hex_string[0..46]}" % p.cmd
			end
		else
			print "\n"
			Hexdump.dump(packet[0..63])
		end
	end
		dir
end

# Decode USBPcap packets exported from Wireshark in C header format
# eg. {
# 0x1c, 0x00, 0x10, 0x60, 0xa9, 0x95, 0x00, 0xe0, /* ...`.... */
# 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, /* ........ */
# 0x01, 0x01, 0x00, 0x0d, 0x00, 0x80, 0x02, 0x00, /* ........ */
# 0x00, 0x00, 0x00, 0x02                          /* .... */
# };
# @param file [String] file name
def debug_packets(file)
  return if file.nil?

	packets = Array.new
	contents = File.read(file)
	contents.scan(/^.*?{(.*?)};/m) do |packet|
    hstr = ""
    packet[0].scan(/0x(\w{2})/m) { |hex| hstr << hex[0] }
    #Strip USB header
    packets << hstr.to_byte_string[27..-1]
	end

	dir = :unk
	packets.each do |packet|
		next if packet.length < 4
		dir = debug_packet(packet, dir)
	end
end

# Print out the suitable devices
# @param devices [Array<LIBUSB::Device>] list of the devices
# @note the variable i is used for --device parameter
def list_devices(devices)
	i = 0
	devices.each do |d|
		puts "* %2d: (port %d) FEL device %d@%d %x:%x" % [++i, d.port_number,
			d.bus_number, d.device_address, d.idVendor, d.idProduct]
	end
end

def send_request(**args)
end

$options = {}

puts "FEL".red << "ix " << FELIX_VERSION << " by Lolet"
puts "I dont give any warranty on this software"
puts "You use it at own risk!"
puts "----------------------"

OptionParser.new do |opts|
	opts.banner = "Usage: #{ARGV[0]} [options]"

	opts.on("-l", "--list", "List the devices") do |v|
		devices = LIBUSB::Context.new.devices(:idVendor => 0x1f3a,
		 :idProduct => 0xefe8)
		puts "No device found in FEL mode!" if devices.empty?
		list_devices(devices)
		exit
	end
	opts.on("-d", "--device id", Integer,
  "Select device number (default 0)") { |id| $options[:device] = id }
	opts.on_tail("--version", "Show version") do
		puts FELIX_VERSION
		exit
	end
end.parse!

usb = LIBUSB::Context.new
devices = usb.devices(:idVendor => 0x1f3a, :idProduct => 0xefe8)
if devices.empty?
	puts "No device found in FEL mode!"
	exit
end

if devices.size > 1 && $options[:device] == nil # If there's more than one
																								 # device list and ask to select
	puts "Found more than 1 device (use --device <number> parameter):"
	exit
else
	$options[:device] ||= 0
	dev = devices[$options[:device]]
	puts "-> Connecting to device at " << "port %d, FEL device %d@%d %x:%x" % [
		dev.port_number, dev.bus_number, dev.device_address, dev.idVendor,
		dev.idProduct]
end
exit
$usb_out = dev.endpoints.select { |e| e.direction == :out }
$usb_in = dev.endpoints.select { |e| e.direction == :in }
handle = dev.open
#detach_kernel_driver(0).
handle.claim_interface(0)
request = AWUSBRequest.new
puts "--> #{request.magic} (#{request.len}, #{request.len2}) (%s)" % request.to_binary_s.to_hex_string
r = handle.bulk_transfer(:dataOut => request.to_binary_s, :endpoint => $usb_out)
puts "Result: " << r.inspect

data = AWFELStandardRequest.new
puts "Sending %s" % data.to_binary_s.to_hex_string
r = handle.bulk_transfer(:dataOut => data.to_binary_s, :endpoint => $usb_out)
puts "Result: " << r.inspect

r = handle.bulk_transfer(:dataIn => 13, :endpoint => $usb_in)
p = AWUSBResponse.read(r) if r.length == 13
debug_packet(p.to_binary_s, :read)

#Then response
request = AWUSBRequest.new
request.cmd = AWUSBCommand::AW_USB_READ
request.len = 32
puts "--> #{request.magic} (#{request.len}, #{request.len2}) (%s)" % request.to_binary_s.to_hex_string
r = handle.bulk_transfer(:dataOut => request.to_binary_s, :endpoint => $usb_out)
puts "Result: " << r.inspect

r = handle.bulk_transfer(:dataIn => 32, :endpoint => $usb_in)
puts "Real result: " << r.inspect
p = AWFELVerifyDeviceResponse.read(r) if r.length == 32
debug_packet(p.to_binary_s, :read)

r = handle.bulk_transfer(:dataIn => 13, :endpoint =>  $usb_in)
p = AWUSBResponse.read(r) if r.length == 13
debug_packet(p.to_binary_s, :read)

handle.close

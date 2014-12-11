#!/usr/bin/env ruby
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
require_relative 'FELHelpers'

#Routines
# 1. Write (--> send | <-- recv)
# --> AWUSBRequest(AW_USB_WRITE, len)
# --> WRITE(len)
# <-- READ(13) -> AWUSBResponse
# (then)
# 2. Read
# --> AWUSBRequest(AW_USB_READ, len)
# <-- READ(len)
# <-- READ(13) -> AWUSBResponse
# (then)
# 3. Read status
# --> AWUSBRequest(AW_USB_READ, 8)
# <-- READ(8)
# <-- READ(13) -> AWUSBResponse

# Flash process (A31s) (FES) (not completed)
# 1. FEL_VERIFY_DEVICE => mode: srv
# 2. FES_TRANSMITE: Get FES (upload flag)
# 3. FEL_VERIFY_DEVICE
# 4. FES_TRANSMITE: Flash new FES (download flag)
# 5. FES_DOWNLOAD (No write) (00 00 00 00 | 00 00 10 00 | 00 00 04 7f 01 00) [SUNXI_EFEX_TAG_ERASE|SUNXI_EFEX_TAG_FINISH]
# 6. FEL_VERIFY_DEVICE
# 7. FES_VERIFY_STATUS (tail 04 7f 00 00) [SUNXI_EFEX_TAG_ERASE]
# 8. FES_DOWNLOAD (write sunxi_mbr.fex, whole file at once => 16384 * 4 copies bytes size)
#                                  (00 00 00 00 00 00 00 00 01 00 01 7f 01 00) [SUNXI_EFEX_TAG_MBR|SUNXI_EFEX_TAG_FINISH]
# 9. FES_VERIFY_STATUS (tail 01 7f 00 00) [SUNXI_EFEX_TAG_MBR]
# (...)


# 0x206 data80
# --> (16) FES_DOWN (0x206): 06 02 00 00 |00 00 00 00| 10 00 00 00 |04 7f 01 00  SUNXI_EFEX_TAG_ERASE|SUNXI_EFEX_TAG_FINISH
# --> (16) FES_DOWN (0x206): 06 02 00 00 |00 00 00 00| 00 00 01 00 |01 7f 01 00  SUNXI_EFEX_TAG_MBR|SUNXI_EFEX_TAG_FINISH
# Then following sequence (write in chunks of 128 bytes => becase of FES_MEDIA_INDEX_LOG) writing partitons...
# --> (16) FES_DOWN (0x206): 06 02 00 00 |00 80 00 00| 00 00 01 00 |00 00 00 00
# --> (16) FES_DOWN (0x206): 06 02 00 00 |80 80 00 00| 00 00 01 00 |00 00 00 00
# --> (16) FES_DOWN (0x206): 06 02 00 00 |00 81 00 00| 00 00 01 00 |00 00 00 00
# --> (16) FES_DOWN (0x206): 06 02 00 00 |80 81 00 00| 00 00 01 00 |00 00 00 00
# -->                                                 ...
# --> (16) FES_DOWN (0x206): 06 02 00 00 |00 a3 00 00| 00 00 01 00 |00 00 00 00
# --> (16) FES_DOWN (0x206): 06 02 00 00 |80 a3 00 00| 00 00 01 00 |00 00 00 00
# -->                                                 ...
# --> (16) FES_DOWN (0x206): 06 02 00 00 |00 a4 00 00| 00 04 00 00 |00 00 01 00 SUNXI_EFEX_TAG_FINISH

# Flash process (A23, A31, boot v2) (FEL)
# Some important info about memory
# 0x2000 - 0x6000: INIT_CODE (16384 bytes)
# 0x7010 - 0x7D00: FEL_MEMORY (3312 bytes)
# => 0x7010 - 0x7210: SYS_PARA (512 bytes)
# => 0x7210 - 0x7220: SYS_PARA_LOG (16 bytes)
# => 0x7220 - 0x7D00: SYS_INIT_PROC (2784 bytes)
# => 0x7D00 - 0x7E00: ? (256 bytes)
# => 0x7E00 - ?     : DATA_START_ADDRESS
# 0x40000000: DRAM_BASE
# 0x4A000000: u-boot.fex
# 0x4D415244: SYS_PARA_LOG (second instance?)
#
# 1. FEL_VERIFY_DEVICE => mode: fel, data_start_address: 0x7E00
# 2. FEL_VERIFY_DEVICE (not sure why it's spamming with this)
# 3. FEL_UPLOAD: Get 256 bytes of data (filed 0xCC) from 0x7E00 (data_start_address)
# 4. FEL_VERIFY_DEVICE
# 5. FEL_DOWNLOAD: Send 256 bytes of data (0x00000000, rest 0xCC) at 0x7E00 (data_start_address)
# 4. FEL_VERIFY_DEVICE
# 5. FEL_DOWNLOAD: Send 16 bytes of data (filed 0x00) at 0x7210 (SYS_PARA_LOG)
# 6. FEL_DOWNLOAD: Send 6496 bytes of data (fes1.fex) at 0x2000 (INIT_CODE)
# 7. FEL_RUN: Run code at 0x2000 (fes1.fex) => inits dram
# 8. FEL_UPLOAD: Get 136 bytes of data (DRAM...) from 0x7210 (SYS_PARA_LOG)
# 9. FEL_DOWNLOAD(12 times because u-boot.fex is 0xBC000 bytes): Send (u-boot.fex) 0x4A000000 in 65536 bytes chunks
#    last chunk is 49152 bytes and ideally starts at config.fex data
# 10.FEL_RUN: Run code at 0x4A000000 (u-boot.fex) => mode: srv, you can send FES commands now
# *** Flash tool ask user if he would like to do format or upgrade

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

# Send a request
# @param handle [LIBUSB::DevHandle] a device handle
# @param data binary data
# @return [AWUSBResponse] or nil if fails
def send_request(handle, data)
# 1. Send AWUSBRequest to inform what we want to do (write/read/how many data)
  request = AWUSBRequest.new
  request.len = data.length
  debug_packet(request.to_binary_s, :write) if $options[:verbose]
  r = handle.bulk_transfer(:dataOut => request.to_binary_s, :endpoint =>
   $usb_out)
  puts "Sent ".green << "#{r}".yellow << " bytes".green if $options[:verbose]
# 2. Send a proper data
  debug_packet(data, :write) if $options[:verbose]
  r2 = handle.bulk_transfer(:dataOut => data, :endpoint => $usb_out)
  puts "Sent ".green << r2.to_s.yellow << " bytes".green if $options[:verbose]
# 3. Get AWUSBResponse
  r3 = handle.bulk_transfer(:dataIn => 13, :endpoint => $usb_in)
  debug_packet(r3, :read) if $options[:verbose]
  puts "Received ".green << "#{r3.length}".yellow << " bytes".green if $options[:verbose]
  r3
rescue => e
  raise "Failed to send ".red << "#{data.length}".yellow << " bytes".red <<
  " (" << e.message << ")"
end

# Read data
# @param handle [LIBUSB::DevHandle] a device handle
# @param len expected length of data
# @return [String] binary data or nil if fail
def recv_request(handle, len)
# 1. Send AWUSBRequest to inform what we want to do (write/read/how many data)
  request = AWUSBRequest.new
  request.len = len
  request.cmd = USBCmd[:read]
  debug_packet(request.to_binary_s, :write) if $options[:verbose]
  r = handle.bulk_transfer(:dataOut => request.to_binary_s, :endpoint => $usb_out)
  puts "Sent ".green << "#{r}".yellow << " bytes".green if $options[:verbose]
# 2. Read data of length we specified in request
  recv_data = handle.bulk_transfer(:dataIn => len, :endpoint => $usb_in)
  debug_packet(recv_data, :read) if $options[:verbose]
# 3. Get AWUSBResponse
  response = handle.bulk_transfer(:dataIn => 13, :endpoint => $usb_in)
  puts "Received ".green << "#{response.length}".yellow << " bytes".green if $options[:verbose]
  debug_packet(response, :read) if $options[:verbose]
  recv_data
rescue => e
  raise "Failed to receive ".red << "#{len}".yellow << " bytes".red <<
  " (" << e.message << ")"
end


# Clean up on and finish program
# @param handle [LIBUSB::DevHandle] a device handle
def bailout(handle)
  print "* Finishing"
  handle.close if handle
  puts "\t[OK]".green
  exit
rescue => e
  puts "\t[FAIL]".red
  puts "Error: #{e.message} at #{e.backtrace.join("\n")}"
end

# Get device status
# @param handle [LIBUSB::DevHandle] a device handle
# @return [AWFELVerifyDeviceResponse] device status
# @raise [String]
def felix_get_device_info(handle)
  data = send_request(handle, AWFELStandardRequest.new.to_binary_s)
  if data == nil
    raise "Failed to send request (data: #{data})"
  end
  data = recv_request(handle, 32)
  if data == nil || data.length != 32
    raise "Failed to receive device info (data: #{data})"
  end
  info = AWFELVerifyDeviceResponse.read(data)
  data = recv_request(handle, 8)
  if data == nil || data.length != 8
    raise "Failed to receive device status (data: #{data})"
  end
  status = AWFELStatusResponse.read(data)
  raise "Command failed (Status #{status.state})" if status.state > 0
  info
end

# Erase NAND flash
# @param handle [LIBUSB::DevHandle] a device handle
# @return [AWFESVerifyStatusResponse] operation status
# @raise [String] error name
# @note Use only in AWDeviceMode[:srv]
def felix_format_device(handle)
  request = AWFELMessage.new
  request.address = 0
  request.len = 16
  request.flags = AWTags[:erase] | AWTags[:finish]
  data = send_request(handle, request.to_binary_s)
  if data == nil
    raise "Failed to send request (data: #{data})"
  end
  data = recv_request(handle, 8)
  if data == nil || data.length != 8
    raise "Failed to receive device status (data: #{data})"
  end
  status = AWFELStatusResponse.read(data)
  if status.state > 0
    raise "Command failed (Status #{status.state})"
  end
  felix_verify_status(handle, :erase)
end

# Verify last operation status
# @param handle [LIBUSB::DevHandle] a device handle
# @param tags [Symbol] operation tag (zero or more of AWTags)
# @return [AWFESVerifyStatusResponse] device status
# @raise [String] error name
# @note Use only in AWDeviceMode[:fes]
def felix_verify_status(handle, tags=[:none])
  request = AWFELMessage.new
  request.cmd = FESCmd[:verify_status]
  request.address = 0
  request.len = 0
  tags.each {|t| request.flags |= AWTags[t]}
  data = send_request(handle, request.to_binary_s)
  if data == nil
    raise "Failed to send verify request"
  end
  data = recv_request(handle, 12)
  if data == nil
    raise "Failed to receive verify request (no data)"
  elsif data.length != 12
    raise "Failed to receive verify request (data len #{data.length} != 12)"
  end
  AWFESVerifyStatusResponse.read(data)
end

# Read memory from device
# @param handle [LIBUSB::DevHandle] a device handle
# @param address [Integer] memory address to read from
# @param length [Integer] size of data
# @param tags [Array<AWTags>] operation tag (zero or more of AWTags)
# @param mode [AWDeviceMode] operation mode `:fel` or `:fes`
# @return [String] requested data
# @raise [String] error name
def felix_read(handle, address, length, tags=[:none], mode=:fel)
  result = ""
  remain_len = length
  while remain_len>0
    request = AWFELMessage.new
    request.cmd = FELCmd[:upload] if mode == :fel
    request.cmd = FESCmd[:upload] if mode == :fes
    request.address = address
    if remain_len / FELIX_MAX_CHUNK == 0
      request.len = remain_len
    else
      request.len = FELIX_MAX_CHUNK
    end
    tags.each {|t| request.flags |= AWTags[t]}
    data = send_request(handle, request.to_binary_s)
    raise "Failed to send request (response len: #{data.length} !=" <<
      " 13)" if data.length != 13

    output = recv_request(handle, request.len)

    # Rescue if we received AWUSBResponse
    output = recv_request(handle, request.len) if output.length !=
     request.len && output.length == 13
    # Rescue if we received AWFELStatusResponse
    output = recv_request(handle, request.len) if output.length !=
     request.len && output.length == 8
    if output.length != request.len
      raise "Data size mismatch (data len #{output.length} != #{request.len})"
    end
    status = recv_request(handle, 8)
    raise "Failed to get device status (data: #{status})" if status.length != 8
    fel_status = AWFELStatusResponse.read(status)
    raise "Command failed (Status #{fel_status.state})" if fel_status.state > 0
    result << output
    remain_len-=request.len
    address+=request.len
  end
  result
end

# Write data to device memory
# @param handle [LIBUSB::DevHandle] a device handle
# @param address [Integer] place in memory to write
# @param memory [String] data to write
# @param tags [Array<AWTags>] operation tag (zero or more of AWTags)
# @param mode [AWDeviceMode] operation mode `:fel` or `:fes`
# @raise [String] error name
def felix_write(handle, address, memory, tags=[:none], mode=:fel)
  total_len = memory.length
  start = 0
  while total_len>0
    request = AWFELMessage.new
    request.cmd = FELCmd[:download] if mode == :fel
    request.cmd = FESCmd[:download] if mode == :fes
    request.address = address
    if total_len / FELIX_MAX_CHUNK == 0
      request.len = total_len
    else
      request.len = FELIX_MAX_CHUNK
    end
    tags.each {|t| request.flags |= AWTags[t]}
    data = send_request(handle, request.to_binary_s)
    if data == nil
      raise "Failed to send request (#{request.cmd})"
    end
    data = send_request(handle, memory[start, request.len])
    if data == nil
      raise "Failed to send data (#{start}/#{memory.length})"
    end
    data = recv_request(handle, 8)
    if data == nil || data.length != 8
      raise "Failed to receive device status (data: #{data})"
    end
    status = AWFELStatusResponse.read(data)
    if status.state > 0
      raise "Command failed (Status #{status.state})"
    end
    start+=request.len
    total_len-=request.len
    address+=request.len
  end
end

# Execute code at specified memory
# @param handle [LIBUSB::DevHandle] a device handle
# @param address [Integer] memory address to read from
# @raise [String] error name
#
# @note Use only in AWDeviceMode[:fel]
def felix_run(handle, address)
  request = AWFELMessage.new
  request.cmd = FELCmd[:run]
  request.address = address
  data = send_request(handle, request.to_binary_s)
  if data == nil
    raise "Failed to send request (#{request.cmd})"
  end
  data = recv_request(handle, 8)
  if data == nil || data.length != 8
    raise "Failed to receive device status (data: #{data})"
  end
  status = AWFELStatusResponse.read(data)
  if status.state > 0
    raise "Command failed (Status #{status.state})"
  end
end

$options = {}
puts "FEL".red << "ix " << FELIX_VERSION << " by Lolet"
puts "Warning:".red << "I don't give any warranty on this software"
puts "You use it at own risk!"
puts "----------------------"

begin
  # ComputerInteger: hex strings (0x....) or decimal
  ComputerInteger = /(?:0x[\da-fA-F]+(?:_[\da-fA-F]+)*|\d+(?:_\d+)*)/
  Modes = [:fel, :fes]
  AddressCmds = [:write, :read, :run]
  LengthCmds = [:read]
  OptionParser.new do |opts|
      opts.banner = "Usage: FELix.rb action [options]"
      opts.separator "Actions:"
      opts.on("--devices", "List the devices") do |v|
          devices = LIBUSB::Context.new.devices(:idVendor => 0x1f3a,
           :idProduct => 0xefe8)
          puts "No device found in FEL mode!" if devices.empty?
          list_devices(devices)
          exit
      end
      opts.on("--info", "Get device info") { $options[:action] =
        :device_info }
      opts.on("--format", "Erase NAND Flash") { $options[:action] = :format }
      opts.on("--debug path", String, "Decodes packets from Wireshark dump") do |f|
        debug_packets(f)
        exit
      end
      opts.on("--run", "Execute code. Use with --address") do
        $options[:action] = :run
      end
      opts.on("--read file", String, "Read memory to file. Use with" <<
        " --address and --length") do |f|
         $options[:action] = :read
         $options[:file] = f
       end
      opts.on("--write file", String, "Write file to memory. Use with" <<
        " --address") do |f|
         $options[:action] = :write
         $options[:file] = f
      end
      opts.on("--request id", ComputerInteger, "Send a standard request") do |f|
        $options[:action] = :request
        $options[:request] = f[0..1] == "0x" ? Integer(f, 16) : f.to_i
      end
      opts.on("--version", "Show version") do
        puts FELIX_VERSION
        exit
      end
      opts.separator "Options:"
      opts.on("-d", "--device number", Integer,
      "Select device number (default 0)") { |id| $options[:device] = id }

      opts.on("-a", "--address address", ComputerInteger, "Address (used for" <<
      " --" << AddressCmds.join(", --") << ")") do |a|
        $options[:address] = a[0..1] == "0x" ? Integer(a, 16) : a.to_i
      end
      opts.on("-l", "--length len", ComputerInteger, "Length of data (used " <<
      "for --" << LengthCmds.join(", --") << ")") do |l|
        $options[:length] = l[0..1] == "0x" ? Integer(l, 16) : l.to_i
      end
      opts.on("-m", "--mode mode", Modes, "Set command context to one of" <<
      "modes (" << Modes.join(", ") << ")") do |m|
        $options[:mode] = m.to_sym
      end
      opts.on("-t", "--tags t,a,g", Array, "One or more tag (" <<
      AWTags.keys.join(", ") << ")") do |t|
        $options[:tags] = t.map(&:to_sym) # Convert every value to symbol
      end
      opts.on_tail("-v", "--verbose", "Verbose traffic") do
        $options[:verbose] = true
      end
  end.parse!
  $options[:tags] = [:none] unless $options[:tags]
  $options[:mode] = :fel unless $options[:mode]
  unless ($options[:tags] - AWTags.keys).empty?
    puts "Invalid tag. Please specify one or more of " << AWTags.keys.join(", ")
    exit
  end
  raise OptionParser::MissingArgument if($options[:action] == :read &&
    ($options[:length] == nil || $options[:address] == nil))
  raise OptionParser::MissingArgument if(($options[:action] == :write ||
  $options[:action] == :run) && $options[:address] == nil)
rescue OptionParser::MissingArgument
  puts "Missing argument. Type FELix.rb --help to see usage"
  exit
rescue OptionParser::InvalidArgument
  puts "Invalid argument. Type FELix.rb --help to see usage"
  exit
end

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
    print "* Connecting to device at port %d, FEL device %d@%d %x:%x" % [
        dev.port_number, dev.bus_number, dev.device_address, dev.idVendor,
        dev.idProduct]
end
# Setup endpoints
$usb_out = dev.endpoints.select { |e| e.direction == :out }[0]
$usb_in = dev.endpoints.select { |e| e.direction == :in }[0]

begin
  $handle = dev.open
  #detach_kernel_driver(0)
  $handle.claim_interface(0)
  puts "\t[OK]".green
rescue LIBUSB::ERROR_NOT_SUPPORTED
  puts "\t[FAIL]".red
  puts "Error: You must install libusb filter on your usb device driver"
  bailout($handle)
rescue => e
  puts "\t[FAIL]".red
  puts "Error: #{e.message} at #{e.backtrace.join("\n")}"
  bailout($handle)
end

case $options[:action]
when :device_info # case for FEL_R_VERIFY_DEVICE
  begin
    info = felix_get_device_info($handle)
    info.each_pair do |k, v|
      print "%-40s" % k.to_s.yellow
      case k
      when :board then puts board_id_to_str(v)
      when :mode then puts AWDeviceMode.key(v)
      when :data_flag, :data_length, :data_start_address then puts "0x%08x" % v
      else
        puts "#{v}"
      end
    end
  rescue => e
    puts "Failed to receive device info (#{e.message})"
  end
when :format
  begin
    data = felix_format_device($handle)
    puts "Device response:" << "#{data.last_error}".yellow
  rescue => e
    puts "Failed to format device (#{e.message})"
  end
when :read
  begin
    print "* #{$options[:mode]}: Reading data (#{$options[:length]}" <<
      " bytes)" unless $options[:verbose]
    data = felix_read($handle, $options[:address], $options[:length],
      $options[:tags], $options[:mode])
    File.open($options[:file], "w") { |f| f.write(data) }
    puts "\t[OK]".green unless $options[:verbose]
  rescue => e
    puts "\t[FAIL]".red unless $options[:verbose]
    puts "Failed to read data: #{e.message} at #{e.backtrace.join("\n")}"
  end
when :write
  begin
    print "* #{$options[:mode]}: Writing data" unless $options[:verbose]
    data = File.read($options[:file])
    print " (#{data.length} bytes)" unless $options[:verbose]
    felix_write($handle, $options[:address], data, $options[:tags],
      $options[:mode])
    puts "\t[OK]".green unless $options[:verbose]
  rescue => e
    puts "\t[FAIL]".red unless $options[:verbose]
    puts "Failed to write data: #{e.message} at #{e.backtrace.join("\n")}"
  end
when :run
  begin
    felix_run($handle, $options[:address])
  rescue => e
    puts "Failed to execute: #{e.message} at #{e.backtrace.join("\n")}"
  end
when :request
  begin
    request = AWFELMessage.new
    request.cmd = $options[:request]
    request.len = 0
    data = send_request($handle, request.to_binary_s)
    raise "Failed to send request (response len: #{data.length} !=" <<
    " 13)" if data.length != 13

    output = recv_request($handle, FELIX_MAX_CHUNK)
    Hexdump.dump output

    status = recv_request($handle, 8)
    raise "Failed to get device status (data: #{status})" if status.length != 8
    fel_status = AWFELStatusResponse.read(status)
    raise "Command failed (Status #{fel_status.state})" if fel_status.state > 0  
  rescue => e
    puts "Failed to send a request(#{$options[:request]}): #{e.message}" <<
      " at #{e.backtrace.join("\n")}"
  end
else
  puts "No action specified"
end

bailout($handle)

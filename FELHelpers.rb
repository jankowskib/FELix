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

# Change the way library allocs memory to avoid nasty memory segmentation
class LIBUSB::Transfer
  # Allocate #FELIX_MAX_CHUNK bytes of data buffer for input transfer.
  #
  # @param [Fixnum]  len  Number of bytes to allocate
  # @param [String, nil] data  some data to initialize the buffer with
  def alloc_buffer(len, data=nil)
    if !@buffer
      free_buffer if @buffer
      # HACK: Avoid crash when memory is reallocated
      @buffer = FFI::MemoryPointer.new(FELIX_MAX_CHUNK, 1, false)
    end
    @buffer.put_bytes(0, data) if data
    @transfer[:buffer] = @buffer
    @transfer[:length] = len
  end

  # Set output data that should be sent.
  def buffer=(data)
    alloc_buffer(data.bytesize, data)
  end
end


class String # @visibility private
  def camelize # @visibility private
      self.gsub(/\/(.?)/) { "::" + $1.upcase }.gsub(/(^|_)(.)/) { $2.upcase }
  end
end

class Symbol # @visibility private
  def camelize # @visibility private
    self.to_s.camelize
  end
end

#Fix endianess bug (N* -> V*) (so much time wasted before I figured it out...)
class Crypt::RC6
  def encrypt_block(data) # @visibility private
    a, b, c, d = *data.unpack('V*')
    b += @sbox[0]
    d += @sbox[1]
    1.upto @rounds do |i|
      t = lrotate((b * (2 * b + 1)), 5)
      u = lrotate((d * (2 * d + 1)), 5)
      a = lrotate((a ^ t), u) + @sbox[2 * i]
      c = lrotate((c ^ u), t) + @sbox[2 * i + 1]
      a, b, c, d  =  b, c, d, a
    end
    a += @sbox[2 * @rounds + 2]
    c += @sbox[2 * @rounds + 3]
    [a, b, c, d].map{|i| i & 0xffffffff}.pack('V*')
  end

  def decrypt_block(data) # @visibility private
    a, b, c, d = *data.unpack('V*')
    c -= @sbox[2 * @rounds + 3]
    a -= @sbox[2 * @rounds + 2]
    @rounds.downto 1 do |i|
      a, b, c, d = d, a, b, c
      u = lrotate((d * (2 * d + 1)), 5)
      t = lrotate((b * (2 * b + 1)), 5)
      c = rrotate((c - @sbox[2 * i + 1]), t) ^ u
      a = rrotate((a - @sbox[2 * i]), u) ^ t
    end
    d -= @sbox[1]
    b -= @sbox[0]
    [a, b, c, d].map{|i| i & 0xffffffff}.pack('V*')
  end
end

# Contains support methods
class FELHelpers
  class << self
    # Convert board id to string
    # @param id [Integer] board id
    # @return [String] board name
    def board_id_to_str(id)
      board = case (id >> 8 & 0xFFFF)
      when 0x1610 then "Allwinner A31s (sun6i)"
      when 0x1623 then "Allwinner A10 (sun4i)"
      when 0x1625 then "Allwinner A13/A10s (sun5i)"
      when 0x1633 then "Allwinner A31 (sun6i)"
      when 0x1639 then "Allwinner A80/A33 (sun9i)"
      when 0x1650 then "Allwinner A23 (sun7i)"
      when 0x1651 then "Allwinner A20 (sun7i)"
      else
        "Unknown: (0x#{id >> 8 & 0xFFFF})"
      end
      board << ", revision #{id & 0xFF}"
    end

    # Convert tag mask to string
    # @param tags [Integer] tag flag
    # @return [String] human readable tags delimetered by |
    def tags_to_s(tags)
      r = ""
      AWTags.each do |k, v|
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
        puts "\t(Prepare for #{dir} of #{p.len} bytes)"
        #puts p.inspect
      elsif packet[0..7] == "AWUSBFEX"
        p = AWFELVerifyDeviceResponse.read(packet)
        puts "<-- (% 5d) " % packet.bytesize << "FELVerifyDeviceResponse".
        light_blue << "\t%s, FW: %d, mode: %s" % [ board_id_to_str(p.board), p.fw,
          AWDeviceMode.key(p.mode) ]
      elsif packet[0..3] == "AWUS" && packet.length == 13
        p = AWUSBResponse.read(packet)
        puts "<-- (% 5d) " % packet.bytesize << "AWUSBResponse".yellow <<
        "\t0x%x, status %s" % [ p.tag, AWUSBStatus.key(p.csw_status) ]
      elsif packet[0..3] == "DRAM" && packet.length == 136
        p = AWDRAMData.read(packet)
        puts "<-- (% 5d) " % packet.bytesize << "AWDRAMData".light_blue
        p p
      elsif packet.length == 512
        p = AWSystemParameters.read(packet)
        puts "<-- (% 5d) " % packet.bytesize << "AWSystemParameters".light_blue
        p p
      elsif packet.length == 12 && dir == :read
        p = AWFESVerifyStatusResponse.read(packet)
        puts "<-- (% 5d) " % packet.bytesize << "AWFESVerifyStatusResponse ".
         light_blue << "flags: 0x%x, crc: 0x%x, last_err/crc %d" % [p.flags,
         p.fes_crc, p.crc]
      else
        return :unk if dir == :unk
        print (dir == :write ? "--> " : "<-- ") << "(% 5d) " % packet.bytesize
        if packet.length == 16
          p = AWFELMessage.read(packet)
          case p.cmd
          when FELCmd[:verify_device] then puts "FELVerifyDevice"
            .light_blue <<  " (0x#{FELCmd[:verify_device]})"
          when FESCmd[:transmite]
            p = AWFESTrasportRequest.read(packet)
            print "FES#{FESCmd.key(p.cmd).camelize}: ".light_blue
            print FESTransmiteFlag.key(p.direction).to_s
            print "(0x%04x)" % p.direction unless FESTransmiteFlag.key(p.direction)
            puts ", tag #{p.tag}, index #{p.media_index}, addr 0x%08x, len %d," % [
              p.address, p.len] << " reserved %s" % p.reserved.inspect
          when FESCmd[:download], FESCmd[:verify_status], FELCmd[:download],
            FELCmd[:upload], FESCmd[:run], FELCmd[:run]
            p = AWFELMessage.read(packet)
            print "FEL#{FELCmd.key(p.cmd).camelize}:".
            light_blue if FELCmd.has_value?(p.cmd)
            print "FES#{FESCmd.key(p.cmd).camelize}:".
            light_blue if FESCmd.has_value?(p.cmd)
            puts " tag: #{p.tag}, %d bytes @ 0x%02x" % [p.len, p.address] <<
            ", flags #{tags_to_s(p.flags)} (0x%04x)" % p.flags
          else
            print "FEL#{FELCmd.key(p.cmd).camelize}".
            light_blue if FELCmd.has_value?(p.cmd)
            print "FES#{FESCmd.key(p.cmd).camelize}".
            light_blue if FESCmd.has_value?(p.cmd)
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

    # Decrypt Livesuit image header using RC6 algorithm
    # @param data [String] encrypted binary data
    # @param key [Symbol] encryption key (:header, :item, :data)
    # @return decryped binary data
    def decrypt(data, key)
      out = ""
      data.scan(/.{16}/m) do |m|
        out << RC6[key].decrypt_block(m)
      end
      out
    end

    # Load Livesuit image header, and display info
    # @param file [String] filename
    def show_image_info(file)
      encrypted = false
      img = File.read(file, 1024) # Read header
      if img.byteslice(0, 8) != "IMAGEWTY"
        puts "Warning:".red << " Image is encrypted!".yellow
        encrypted = true
      end
      print "Decrypting..." if encrypted
      img = decrypt(img, :header) if encrypted
      raise FELError, "Unrecognized image format" if img.byteslice(0, 8) !=
        "IMAGEWTY"
      # @todo read header version
      item_count = img[encrypted ? 0x38 : 0x3C, 4].unpack("V").first
      raise "Firmware contains no items!" if item_count == 0

      for i in 1..item_count
        print "\rDecrypting...: #{i}/#{item_count}".green if encrypted
        item = File.read(file, 1024, (i * 1024)) # Read item
        item = decrypt(item, :item) if encrypted
        img << item
      end
      puts if encrypted
      puts AWImage.read(img).inspect
    end

  end
end

# Twofish key: 00000005 00000004 00000009 0000000d 00000016
#              00000023 00000039 0000005c 00000095 000000f1
#              00000186 00000277 000003fd 00000674 00000a71
#              000010e5 00001b56 00002c3b 00004791 000073cc
#              0000bb5d 00012f29 0001ea86 000319af 00050435
#              00081de4 000d2219 00153ffd 00226216 0037a213
#              005a0429 0091a63c

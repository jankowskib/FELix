#   FELHelpers.rb
#   Copyright 2014-2015 Bartosz Jankowski
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

raise "Use ./felix to execute program!" if File.basename($0) == File.basename(__FILE__)

# Fix for bytesize function
class StringIO
  def bytesize
    size
  end
end

# Change the way library allocs memory to avoid nasty memory segmentation
class LIBUSB::Transfer
  # Allocate #FELIX_MAX_CHUNK bytes of data buffer for input transfer.
  #
  # @param [Fixnum]  len  Number of bytes to allocate
  # @param [String, nil] data  some data to initialize the buffer with
  def alloc_buffer(len, data=nil)
    if !@buffer
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

# Contains support methods
class FELHelpers
  class << self
    # Convert board id to string
    # @param id [Integer] board id
    # @return [String] board name
    def board_id_to_str(id)
      board = case (id >> 8 & 0xFFFF)
      when 0x1610 then "Allwinner AXX (sunxi)"
      when 0x1623 then "Allwinner A10 (sun4i)"
      when 0x1625 then "Allwinner A13/A10s (sun5i)"
      when 0x1633 then "Allwinner A31 (sun6i)"
      when 0x1639 then "Allwinner A80/A33 (sun9i)"
      when 0x1650 then "Allwinner A23 (sun7i)"
      when 0x1651 then "Allwinner A20 (sun7i)"
      when 0x1667 then "Allwinner A33 (sun8i)"
      when 0x1673 then "Allwinner A83 (sun8i)"
      else
        "Unknown: (0x%x)" % (id >> 8 & 0xFFFF)
      end
      board << ", revision #{id & 0xFF}"
    end

    # Convert sys_config.fex port to integer form
    # @param port [String] port e.g. "port:PB22<2><1><default><default>"
    # @return [Integer] integer form e.g. 0x7C4AC1
    # @raise [FELError] if cannot parse port
    # @example how to encode port (on example: port:PH20<2><1><default><default>):
    #   ?    : 0x40000                  = 0x40000
    #   group: 0x80000 + 'H' - 'A'      = 0x80007   (H)
    #   pin:   0x100000 + (20 << 5)     = 0x100280  (20)
    #   func:  0x200000 + (2  << 10)    = 0x200800  (<2>)
    #   mul:   0x400000 + (1  << 14)    = 0x404000  (<1>)
    #   pull:  0x800000 + (?  << 16)    = 0         (<default>)
    #   data:  0x1000000 +(?  << 18)    = 0         (<default>)
    #   sum                             = 0x7C4A87
    # @todo find out how to encode port:powerX<>
    def port_to_id(port)
      raise FELError, "Failed to parse port string (#{port})" unless port=~
        /port:p\w\d\d?<[\w<>]+>$/i
      id = 0x40000
      port.match(%r{port:p(?<group>\w)(?<pin>\d\d?)(?:<(?<func>\d+)>)?
        (?:<(?<mul>\d+)>)?(?:<(?<pull>\d+)>)?(?:<(?<data>\d+)>)?}ix) do |m|
        id+= 0x80000 + m[:group].ord - 'A'.ord
        id+= 0x100000 + (m[:pin].to_i << 5)
        id+= 0x200000 + (m[:func].to_i << 10) if m[:func]
        id+= 0x400000 + (m[:mul].to_i << 14) if m[:mul]
        id+= 0x800000 + (m[:pull].to_i << 16) if m[:pull]
        id+= 0x1000000 + (m[:data].to_i << 18) if m[:data]
      end
      id
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
          print "AWUnknown (0x%x)".red % p.cmd
        end
        puts "\t(Prepare for #{dir} of #{p.len} bytes)"
        #puts p.inspect
      elsif packet.length == 20 && packet[16..19] == "AWUC"
        p = AWUSBRequestV2.read(packet)
        print "--> (% 5d) " % packet.length
        dir = (p.cmd == FESCmd[:download] ? :write : :read)
        print "FES#{FESCmd.key(p.cmd).camelize}".
        light_blue if FESCmd.has_value?(p.cmd)
        puts "\tTag: #{tags_to_s(p.flags)} (0x%04x), addr (0x%x)" % [p.flags, p.address]
        puts "\t(Prepare for #{dir} of #{p.len} bytes)" if p.len > 0
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
        p.pp
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
          when FESCmd[:transmit]
            p = AWFESTrasportRequest.read(packet)
            print "FES#{FESCmd.key(p.cmd).camelize}: ".light_blue
            print FESTransmiteFlag.key(p.flags).to_s
            print "(0x%04x)" % p.flags unless FESTransmiteFlag.key(p.flags)
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
              $options[:verbose] ? Hexdump.dump(packet) : Hexdump.dump(packet[0..63])
            end
          end
        elsif packet.length == 8
          p = AWFELStatusResponse.read(packet)
          puts "FELStatusResponse\t".yellow <<
          "mark #{p.mark}, tag #{p.tag}, state #{p.state}"
        else
          print "\n"
          $options[:verbose] ? Hexdump.dump(packet) : Hexdump.dump(packet[0..63])
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
      print "* Processing..."
      packets = Array.new
      contents = File.read(file)
      header_size = nil
      i = 0
      contents.scan(/^.*?{(.*?)};/m) do |packet|
        i+=1
        hstr = ""
        packet[0].scan(/0x([0-9A-Fa-f]{2})/m) { |hex| hstr << hex[0] }
        print "\r* Processing..." << "#{i}".yellow << " found"
        #Strip USB header
        begin
          #try to guess header size
          header_size = hstr.to_byte_string.index('AWUC') unless header_size
          header_size = hstr.to_byte_string.index('AWUS') unless header_size
          next unless header_size
          packets << hstr.to_byte_string[header_size..-1] if hstr.to_byte_string[header_size..-1] != nil
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
      # Fill block if last chunk is < 16 bytes
      align = 16 - data.bytesize % 16
      if align
        data << "\0" * align
      end
      out = RC6Keys[key].decrypt(data)
      out.byteslice(0...-align)
    end

    # Load Livesuit image header, and display info
    # @param file [String] filename
    def show_image_info(file)
      encrypted = false
      img = File.read(file, 1024) # Read header
      if img.byteslice(0, 8) != FELIX_IMG_HEADER
        puts "Warning:".red << " Image is encrypted!".yellow
        encrypted = true
      end
      print "Decrypting..." if encrypted
      img = decrypt(img, :header) if encrypted
      raise FELError, "Unrecognized image format" if img.byteslice(0, 8) !=
        FELIX_IMG_HEADER
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

    # Generate AW-style checksum for given data block
    # @param data [String] memory block to compute
    # @note Original C function is add_sum from u-boot-2011.09/sprite/sprite_verify.c
    def checksum(data)
      sum = 0
      ints = data.unpack("V*")
      ints.each do |i|
        sum += i
      end

      case(data.length & 3)
      when 0
        sum
      when 1
        sum += ints[-1] & 0x000000ff
      when 2
        sum += ints[-1] & 0x0000ffff
      when 3
        sum += ints[-1] & 0x00ffffff
      end

      # Trim 64 -> 32 bit value
      sum & 0xffffffff
    end

    # Create DRAM config based on sys_config.fex, sys_config1.fex
    # @param file [String] sys_config.fex file
    # @param legacy [TrueClass,FalseClass] what strcture to create
    # @return [AWSystemLegacyParameters,AWSystemParameters] dram config
    def create_dram_config(file = nil, legacy = false)
      dram_cfg = nil
      cfg = file
      cfg.tr!("\0","")
      cfg_ini = IniFile.new( :content => cfg, :encoding => "UTF-8")
      if legacy
        dram_cfg = AWLegacySystemParameters.new
        # Assign values, but left defaults if entry doesn't exist
        dram_cfg.chip = cfg_ini[:platform]["chip"] if cfg_ini[:platform]["chip"]
        dram_cfg.pid = cfg_ini[:platform]["pid"] if cfg_ini[:platform]["pid"]
        dram_cfg.sid = cfg_ini[:platform]["sid"] if cfg_ini[:platform]["sid"]
        dram_cfg.bid = cfg_ini[:platform]["bid"] if cfg_ini[:platform]["bid"]
        dram_cfg.uart_debug_tx   = port_to_id(cfg_ini[:uart_para][
        "uart_debug_tx"]) if cfg_ini[:uart_para]["uart_debug_tx"]
        dram_cfg.uart_debug_port = cfg_ini[:uart_para]["uart_debug_port"] if
        cfg_ini[:uart_para]["uart_debug_port"]
        dram_cfg.dram_baseaddr = cfg_ini[:dram_para]["dram_baseaddr"] if
        cfg_ini[:dram_para]["dram_baseaddr"]
        dram_cfg.dram_clk = cfg_ini[:dram_para]["dram_clk"] if
        cfg_ini[:dram_para]["dram_clk"]
        dram_cfg.dram_type = cfg_ini[:dram_para]["dram_type"] if
        cfg_ini[:dram_para]["dram_type"]
        dram_cfg.dram_rank_num = cfg_ini[:dram_para]["dram_rank_num"] if
        cfg_ini[:dram_para]["dram_rank_num"]
        dram_cfg.dram_chip_density = cfg_ini[:dram_para]["dram_chip_density"] if
        cfg_ini[:dram_para]["dram_chip_density"]
        dram_cfg.dram_io_width = cfg_ini[:dram_para]["dram_io_width"] if
        cfg_ini[:dram_para]["dram_io_width"]
        dram_cfg.dram_bus_width = cfg_ini[:dram_para]["dram_bus_width"] if
        cfg_ini[:dram_para]["dram_bus_width"]
        dram_cfg.dram_cas = cfg_ini[:dram_para]["dram_cas"] if
        cfg_ini[:dram_para]["dram_cas"]
        dram_cfg.dram_zq = cfg_ini[:dram_para]["dram_zq"] if
        cfg_ini[:dram_para]["dram_zq"]
        dram_cfg.dram_odt_en = cfg_ini[:dram_para]["dram_odt_en"] if
        cfg_ini[:dram_para]["dram_odt_en"]
        dram_cfg.dram_size = cfg_ini[:dram_para]["dram_size"] if
        cfg_ini[:dram_para]["dram_size"]
        dram_cfg.dram_tpr0 = cfg_ini[:dram_para]["dram_tpr0"] if
        cfg_ini[:dram_para]["dram_tpr0"]
        dram_cfg.dram_tpr1 = cfg_ini[:dram_para]["dram_tpr1"] if
        cfg_ini[:dram_para]["dram_tpr1"]
        dram_cfg.dram_tpr2 = cfg_ini[:dram_para]["dram_tpr2"] if
        cfg_ini[:dram_para]["dram_tpr2"]
        dram_cfg.dram_tpr3 = cfg_ini[:dram_para]["dram_tpr3"] if
        cfg_ini[:dram_para]["dram_tpr3"]
        dram_cfg.dram_tpr4 = cfg_ini[:dram_para]["dram_tpr4"] if
        cfg_ini[:dram_para]["dram_tpr4"]
        dram_cfg.dram_tpr5 = cfg_ini[:dram_para]["dram_tpr5"] if
        cfg_ini[:dram_para]["dram_tpr5"]
        dram_cfg.dram_emr1 = cfg_ini[:dram_para]["dram_emr1"] if
        cfg_ini[:dram_para]["dram_emr1"]
        dram_cfg.dram_emr2 = cfg_ini[:dram_para]["dram_emr2"] if
        cfg_ini[:dram_para]["dram_emr2"]
        dram_cfg.dram_emr3 = cfg_ini[:dram_para]["dram_emr3"] if
        cfg_ini[:dram_para]["dram_emr3"]
      else
        dram_cfg = AWSystemParameters.new
        dram_cfg.uart_debug_tx   = port_to_id(cfg_ini[:uart_para][
          "uart_debug_tx"]) if cfg_ini[:uart_para]["uart_debug_tx"]
        dram_cfg.uart_debug_port = cfg_ini[:uart_para]["uart_debug_port"] if
        cfg_ini[:uart_para]["uart_debug_port"]
        dram_cfg.dram_clk        = cfg_ini[:dram_para]["dram_clk"] if
        cfg_ini[:dram_para]["dram_clk"]
        dram_cfg.dram_type       = cfg_ini[:dram_para]["dram_type"] if
        cfg_ini[:dram_para]["dram_type"]
        dram_cfg.dram_zq         = cfg_ini[:dram_para]["dram_zq"] if
        cfg_ini[:dram_para]["dram_zq"]
        dram_cfg.dram_odt_en     = cfg_ini[:dram_para]["dram_odt_en"] if
        cfg_ini[:dram_para]["dram_odt_en"]
        dram_cfg.dram_para1      = cfg_ini[:dram_para]["dram_para1"] if
        cfg_ini[:dram_para]["dram_para1"]
        dram_cfg.dram_para2      = cfg_ini[:dram_para]["dram_para2"] if
        cfg_ini[:dram_para]["dram_para2"]
        dram_cfg.dram_mr0        = cfg_ini[:dram_para]["dram_mr0"] if
        cfg_ini[:dram_para]["dram_mr0"]
        dram_cfg.dram_mr1        = cfg_ini[:dram_para]["dram_mr1"] if
        cfg_ini[:dram_para]["dram_mr1"]
        dram_cfg.dram_mr2        = cfg_ini[:dram_para]["dram_mr2"] if
        cfg_ini[:dram_para]["dram_mr2"]
        dram_cfg.dram_mr3        = cfg_ini[:dram_para]["dram_mr3"] if
        cfg_ini[:dram_para]["dram_mr3"]
        dram_cfg.dram_tpr0       = cfg_ini[:dram_para]["dram_tpr0"] if
        cfg_ini[:dram_para]["dram_tpr0"]
        dram_cfg.dram_tpr1       = cfg_ini[:dram_para]["dram_tpr1"] if
        cfg_ini[:dram_para]["dram_tpr1"]
        dram_cfg.dram_tpr2       = cfg_ini[:dram_para]["dram_tpr2"] if
        cfg_ini[:dram_para]["dram_tpr2"]
        dram_cfg.dram_tpr3       = cfg_ini[:dram_para]["dram_tpr3"] if
        cfg_ini[:dram_para]["dram_tpr3"]
        dram_cfg.dram_tpr4       = cfg_ini[:dram_para]["dram_tpr4"] if
        cfg_ini[:dram_para]["dram_tpr4"]
        dram_cfg.dram_tpr5       = cfg_ini[:dram_para]["dram_tpr5"] if
        cfg_ini[:dram_para]["dram_tpr5"]
        dram_cfg.dram_tpr6       = cfg_ini[:dram_para]["dram_tpr6"] if
        cfg_ini[:dram_para]["dram_tpr6"]
        dram_cfg.dram_tpr7       = cfg_ini[:dram_para]["dram_tpr7"] if
        cfg_ini[:dram_para]["dram_tpr7"]
        dram_cfg.dram_tpr8       = cfg_ini[:dram_para]["dram_tpr8"] if
        cfg_ini[:dram_para]["dram_tpr8"]
        dram_cfg.dram_tpr9       = cfg_ini[:dram_para]["dram_tpr9"] if
        cfg_ini[:dram_para]["dram_tpr9"]
        dram_cfg.dram_tpr10      = cfg_ini[:dram_para]["dram_tpr10"] if
        cfg_ini[:dram_para]["dram_tpr10"]
        dram_cfg.dram_tpr11      = cfg_ini[:dram_para]["dram_tpr11"] if
        cfg_ini[:dram_para]["dram_tpr11"]
        dram_cfg.dram_tpr12      = cfg_ini[:dram_para]["dram_tpr12"] if
        cfg_ini[:dram_para]["dram_tpr12"]
        dram_cfg.dram_tpr13      = cfg_ini[:dram_para]["dram_tpr13"] if
        cfg_ini[:dram_para]["dram_tpr13"]
        dram_cfg.dram_size       = cfg_ini[:dram_para]["dram_size"] if
        cfg_ini[:dram_para]["dram_size"]
      end
      dram_cfg
    end

  end
end

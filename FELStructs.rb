#   FELStructs.rb
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

# Program exception filter class
class FELError < StandardError
end

class AWUSBRequest < BinData::Record # size 32
  string   :magic,     :length => 4, :initial_value => "AWUC"
  uint32le :tag,       :initial_value => 0
  uint32le :len,       :initial_value => 16
  uint16le :reserved1, :initial_value => 0
  uint8    :reserved2, :initial_value => 0
  uint8    :cmd_len,   :value => 0xC
  uint8    :cmd,       :initial_value => USBCmd[:write]
  uint8    :reserved3, :initial_value => 0
  uint32le :len2, :value => :len
  array    :reserved, :type => :uint8, :initial_length  => 10, :value => 0
end

class AWUSBResponse < BinData::Record # size 13
  string   :magic, :length => 4, :initial_value => "AWUS"
  uint32le :tag
  uint32le :residue
  uint8    :csw_status                # != 0, then fail
end

class AWFELStandardRequest < BinData::Record # size 16
  uint16le :cmd, :initial_value => FELCmd[:verify_device]
  uint16le :tag, :initial_value => 0
  array    :reserved, :type => :uint8, :initial_length  => 12, :value => 0
end

# Extended struct for FEL/FES commands
#   Structure size: 16
class AWFELMessage < BinData::Record
  uint16le :cmd, :initial_value => FELCmd[:download]
  uint16le :tag, :initial_value => 0
  uint32le :address   #  addr + totalTransLen / 512 => FES_MEDIA_INDEX_PHYSICAL,
                      #  FES_MEDIA_INDEX_LOG (NAND)
                      #  addr + totalTransLen => FES_MEDIA_INDEX_DRAM
                      #  totalTransLen => 65536 (max chunk)
  uint32le :len # also next_mode for :tool_mode
  uint32le :flags, :initial_value => AWTags[:none] # one or more of FEX_TAGS
end

# Boot 1.0 way to download data
class AWFESTrasportRequest < BinData::Record # size 16
  uint16le :cmd, :value => FESCmd[:transmite]
  uint16le :tag, :initial_value => 0
  uint32le :address
  uint32le :len
  uint8    :media_index, :initial_value => FESIndex[:dram]
  uint8    :direction, :initial_value => FESTransmiteFlag[:write]
  array    :reserved, :type => :uint8, :initial_length  => 2, :value => 0
end

class AWFELStatusResponse < BinData::Record # size 8
  uint16le :mark
  uint16le :tag
  uint8    :state
  array    :reserved, :type => :uint8, :initial_length => 3
end

class AWFELVerifyDeviceResponse < BinData::Record # size 32
  string   :magic, :length => 8, :initial_value => "AWUSBFEX"
  uint32le :board
  uint32le :fw
  uint16le :mode
  uint8    :data_flag
  uint8    :data_length
  uint32le :data_start_address
  array    :reserved, :type => :uint8, :initial_length => 8
end

class AWFESVerifyStatusResponse < BinData::Record # size 12
  uint32le :flags   # always 0x6a617603
  uint32le :fes_crc
  int32le  :crc     # also last_error (0 if OK, -1 if fail)
end

class AWDRAMData < BinData::Record # size 136?
  string   :magic, :length => 4, :initial_value => "DRAM"
  uint32le :unk
  uint32le :dram_clk
  uint32le :dram_type
  uint32le :dram_zq
  uint32le :dram_odt_en
  uint32le :dram_para1
  uint32le :dram_para2
  uint32le :dram_mr0
  uint32le :dram_mr1
  uint32le :dram_mr2
  uint32le :dram_mr3
  uint32le :dram_tpr0
  uint32le :dram_tpr1
  uint32le :dram_tpr2
  uint32le :dram_tpr3
  uint32le :dram_tpr4
  uint32le :dram_tpr5
  uint32le :dram_tpr6
  uint32le :dram_tpr7
  uint32le :dram_tpr8
  uint32le :dram_tpr9
  uint32le :dram_tpr10
  uint32le :dram_tpr11
  uint32le :dram_tpr12
  uint32le :dram_tpr13
  array    :dram_unknown, :type => :uint32le, :read_until => :eof
end

# Init data for boot 1.0
# It's created using sys_config.fex, and its product of fes1-2.fex
# Names in brackets are [section] from sys_config.fex, and variable name is a key
# Size 512
# Dump of the struct (A31)
# unsigned char rawData[512] = {
#   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
#   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
#   0x87, 0x4A, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00, [0x38, 0x01, 0x00, 0x00], => dram_clk
#   0x03, 0x00, 0x00, 0x00, 0xFB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
#   0x00, 0x08, 0xF4, 0x10, 0x11, 0x12, 0x00, 0x00, 0x50, 0x1A, 0x00, 0x00,
#   0x04, 0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
#   0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x80, 0x40, 0x01, 0xA7, 0x39,
#   0x4C, 0xE7, 0x92, 0xA0, 0x09, 0xC2, 0x48, 0x29, 0x2C, 0x42, 0x44, 0x89,
#   0x80, 0x84, 0x02, 0x30, 0x97, 0x32, 0x2A, 0x00, 0xA8, 0x4F, 0x03, 0x05,
#   0xD8, 0x53, 0x63, 0x03, (0x00, 0x00, 0x00, 0x00)*
#   };
# @example how to encode port (on example: port:PH20<2><1><default><default>):
#   ?    : 0x40000                  = 0x40000
#   group: 0x80000 + 'H' - 'A'      = 0x80007   (H)
#   pin:   0x100000 + (20 << 5)     = 0x100280  (20)
#   func:  0x200000 + (2  << 10)    = 0x200800  (<2>)
#   mul:   0x400000 + (1  << 14)    = 0x404000  (<1>)
#   pull:  0x800000 + (?  << 16)    = 0         (<default>)
#   data:  0x1000000 +(?  << 18)    = 0         (<default>)
#   sum                             = 0x7C4A87
# @note default values are for A31s (sun8iw1p2)
class AWSystemParameters < BinData::Record
  array    :unknown, :type => :uint8, :initial_length => 24
  uint32le :uart_debug_tx, :initial_value => 0x7C4A87   # 0x18 [uart_para]
  uint32le :uart_debug_port, :inital_value => 0         # 0x1C [uart_para]
  uint32le :dram_clk, :initial_value => 240             # 0x20
  uint32le :dram_type, :initial_value => 3              # 0x24
  uint32le :dram_zq, :initial_value => 0xBB             # 0x28
  uint32le :dram_odt_en, :initial_value => 0            # 0x2C
  uint32le :dram_para1, :initial_value => 0x10F40400    # 0x30 &=0xffff => DRAM size (1048)
  uint32le :dram_para2, :initial_value => 0x1211
  uint32le :dram_mr0, :initial_value => 0x1A50
  uint32le :dram_mr1, :initial_value => 0
  uint32le :dram_mr2, :initial_value => 24
  uint32le :dram_mr3, :initial_value => 0
  uint32le :dram_tpr0, :initial_value => 0
  uint32le :dram_tpr1, :initial_value => 0x80000800
  uint32le :dram_tpr2, :initial_value => 0x46270140
  uint32le :dram_tpr3, :initial_value => 0xA0C4284C
  uint32le :dram_tpr4, :initial_value => 0x39C8C209
  uint32le :dram_tpr5, :initial_value => 0x694552AD
  uint32le :dram_tpr6, :initial_value => 0x3002C4A0
  uint32le :dram_tpr7, :initial_value => 0x2AAF9B
  uint32le :dram_tpr8, :initial_value => 0x604111D
  uint32le :dram_tpr9, :initial_value => 0x42DA072
  uint32le :dram_tpr10, :initial_value => 0
  uint32le :dram_tpr12, :initial_value => 0
  uint32le :dram_tpr13, :initial_value => 0           # 0x78
  uint32le :dram_size, :initial_value => (1024 << 20) # 1024 MB
  array    :unused, :type => :uint32le, :read_until => :eof
end

# Size 128
class AWSunxiPartition < BinData::Record
  endian :little
  uint32 :address_high, :initial_value => 0
  uint32 :address_low
  uint32 :lenhi, :initial_value => 0
  uint32 :lenlo
  string :classname, :length => 16, :trim_padding => true, :initial_value => "DISK"
  string :name, :length => 16, :trim_padding => true
  uint32 :user_type, :initial_value => 0x8000
  uint32 :keydata, :initial_value => 0
  uint32 :ro, :initial_value => 0
  array  :reserved, :type => :uint8, :initial_length => 68
end

# Size 64
class AWSunxiLegacyPartition < BinData::Record
  endian :little
  uint32 :address_high, :initial_value => 0
  uint32 :address_low
  uint32 :lenhi, :initial_value => 0
  uint32 :lenlo
  string :classname, :length => 12, :trim_padding => true, :initial_value => "DISK"
  string :name, :length => 12, :trim_padding => true
  uint32 :user_type, :initial_value => 0x8000
  uint32 :ro, :initial_value => 0
  array  :reserved, :type => :uint8, :initial_length => 16
end

#Newer mbr (softw411), record size: 16384
class AWSunxiMBR < BinData::Record
  uint32le :copy, :initial_value => 4
  uint32le :mbr_index
  uint32le :part_count, :value => lambda { part.select { |p| not p.name.empty? }.count  }
  uint32le :stamp, :initial_value => 0
  array    :part, :type => :aw_sunxi_partition, :initial_length => 120
  array    :reserved, :type => :uint8, :initial_length => 992
end

#Legacy mbr (softw311), record size: 1024
class AWSunxiLegacyMBR < BinData::Record
  uint8    :copy, :initial_value => 4
  uint8    :mbr_index
  uint16le :part_count, :value => lambda { part.select { |p| not p.name.empty? }.count  }
  array    :part, :type => :aw_sunxi_legacy_partition, :initial_length => 15
  array    :reserved, :type => :uint8, :initial_length => 44
end

# Unified SUNXI mbr
class AWMBR < BinData::Record
  uint32le  :crc, :value => lambda { Crc32.calculate(version.to_binary_s <<
                            magic << mbr.to_binary_s, 12+mbr.num_bytes,0) }
  uint32le  :version, :initial_value => 0x200
  string    :magic, :length => 8, :initial_value => "softw411",
                    :assert => lambda { ["softw311", "softw411"].include? magic }
  choice :mbr, :selection => :magic do
    aw_sunxi_mbr "softw411"
    aw_sunxi_legacy_mbr "softw311"
  end

  # Decode sunxi_mbr.fex
  #
  # Produces following output
  # --------------------------
  #   *   bootloader (nanda) @ 0x8000    [16MB]
  #   *   env        (nandb) @ 0x10000   [16MB]
  #   *   ...
  def inspect
    self.each_pair do |k, v|
      print "%-40s" % k.to_s.yellow unless k == :mbr
      case k
      when :crc, :version then puts "0x%08x" % v
      when :mbr
        v.each_pair do |i, j|
          next if i == :reserved
          print "%-40s" % i.to_s.yellow unless i == :part
          case i
          when :part
            puts "Partitions:".light_blue
            c = 'a'
            j.each do |p|
              break if p.name.empty?
              print "%-40s" % p.name.yellow
              puts "(nand%s) @ 0x%08x [% 5d MB]" % [c,
                p.address_low, p.lenlo/2048 ]
                c.next!
              end
          else
              puts "#{j}"
          end
        end
      else
          puts "#{v}"
      end
    end
  end

end

# Item structure nested in AWDownloadInfo (72 bytes)
class AWDownloadItem < BinData::Record
  endian :little
  string :name, :length => 16, :trim_padding => true
  uint32 :address_high, :initial_value => 0
  uint32 :address_low
  uint32 :lenhi, :initial_value => 0
  uint32 :lenlo
  string :filename, :length => 16, :trim_padding => true
  string :virtual_filename, :length => 16, :trim_padding => true
  uint32 :encrypt, :initial_value => 0
  uint32 :verify, :initial_value => 0
end

# Legacy item structure nested in AWDownloadInfo (88 bytes)
class AWLegacyDownloadItem < BinData::Record
  endian :little
  string :classname, :length => 12, :trim_padding => true, :initial_value => "DISK"
  string :name, :length => 12, :trim_padding => true
  uint32 :address_high, :initial_value => 0
  uint32 :address_low
  uint32 :lenhi, :initial_value => 0
  uint32 :lenlo
  string :part, :length => 12, :trim_padding => true
  string :filename, :length => 16, :trim_padding => true
  string :virtual_filename, :length => 16, :trim_padding => true
  uint32 :encrypt, :initial_value => 0
end

# Unified Structure for dlinfo.fex (16 384 bytes)
class AWDownloadInfo < BinData::Record
  uint32le  :crc, :value => lambda {
              feed = version.to_binary_s << magic << item_count.to_binary_s
              feed << stamp.to_binary_s if magic == "softw411"
              feed << item.to_binary_s
              feed << reserved.to_binary_s if magic == "softw411"
              Crc32.calculate(feed, self.num_bytes-4, 0)
            }
  uint32le  :version, :initial_value => 0x200
  string    :magic, :length => 8, :initial_value => "softw411",
            :assert => lambda { ["softw311", "softw411"].include? magic }
  uint32le  :item_count, :value => lambda { item.select { |p| not p.name.empty? }.count }
  array     :stamp, :type => :uint32le, :initial_length => 3, :onlyif =>
            lambda { magic == "softw411" }
  choice :item, :selection => :magic do
    array "softw411", :type => :aw_download_item, :initial_length => 120
    array "softw311", :type => :aw_legacy_download_item, :initial_length => 15
  end
  string    :reserved, :length => 7712, :onlyif => lambda { magic == "softw411"},
            :trim_padding => true

  # Decode dl_info.fex
  def inspect
    self.each_pair do |k ,v|
      print "%-40s" % k.to_s.yellow unless k == :item
      case k
      when :item
        v.each do |item|
          next if item.name.empty?
          item.each_pair do |i, j|
            print "%-40s" % i.to_s.yellow
            puts j
          end
        end
      when :stamp then p v
      when :crc, :version then puts "0x%08x" % v
      else
        puts v
      end
    end
  end

end

# Livesuit's image item (1024 bytes)
class AWImageItemV1 < BinData::Record
  endian  :little
  uint32  :version, :asserted_value => 0x100
  uint32  :item_size
  string  :main_type, :length => 8, :initial_value => "COMMON", :pad_byte => ' '
  string  :sub_type, :length => 16, :pad_byte => '0'
  uint32  :attributes
  uint32  :data_len_low
  uint32  :file_len_low
  uint32  :off_len_low
  uint32  :unk
  string  :path, :length => 256, :trim_padding => true
  string  :reserved, :length => 716, :trim_padding => true
  hide    :reserved

  # Useful to see item data
  def inspect
    "%-40s @ 0x%08x [%d kB] => %s" % [self.path.yellow, off_len_low, data_len_low>>10, main_type]
  end

end

# Livesuit's image item (1024 bytes)
class AWImageItemV3 < BinData::Record
  endian  :little
  uint32  :version, :asserted_value => 0x100
  uint32  :item_size
  string  :main_type, :length => 8, :initial_value => "COMMON", :pad_byte => ' '
  string  :sub_type, :length => 16, :pad_byte => '0'
  uint32  :attributes
  string  :path, :length => 256, :trim_padding => true
  uint32  :data_len_low
  uint32  :data_len_hi
  uint32  :file_len_low
  uint32  :file_len_hi
  uint32  :off_len_low
  uint32  :off_len_hi
  array   :encrypt_id, :type => :uint8, :initial_length => 64, :value => 0
  uint32  :crc
  string  :reserved, :length => 640, :trim_padding => true
  hide    :reserved

  # Useful to see item data
  def inspect
    "%-40s @ 0x%08x [%d kB] => %s" % [self.path.yellow, off_len_low, data_len_low>>10, main_type]
  end

end

# Livesuit image file header (version 0x100)
# @todo check that
class AWImageHeaderV1 < BinData::Record
  endian :little
  uint32  :header_size, :asserted_value => 0x50     # size of header-reserved
  uint32  :attributes
  uint32  :image_version
  uint32  :len_low
  uint32  :align
  uint32  :pid
  uint32  :vid
  uint32  :hw
  uint32  :fw
  uint32  :image_attr
  uint32  :item_size
  uint32  :item_count
  uint32  :item_offset
  uint32  :item_attr
  uint32  :append_size      # additional data length
  uint32  :append_offset_lo
  uint32  :append_offset_hi
  string  :reserved, :length => 944, :trim_padding => true # need to confirm that
  hide    :reserved
end

# Livesuit image file header (version 0x300), (1024 bytes)
class AWImageHeaderV3 < BinData::Record
  endian :little
  uint32  :header_size, :asserted_value => 0x60       # size of header-reserved
  uint32  :attributes, :initial_value => 0x4D00000   # disable compression
  uint32  :image_version, :initial_value => 0x100234
  uint32  :len_low                                   # file size
  uint32  :len_hi, :initial_value => 0
  uint32  :align, :initial_value => 1024
  uint32  :pid, :initial_value => 0x1234
  uint32  :vid, :initial_value => 0x8743
  uint32  :hw, :initial_value => 256
  uint32  :fw, :initial_value => 256
  uint32  :image_attr
  uint32  :item_size, :initial_value => 1024         # size of AWImageItem
  uint32  :item_count                                # number of AWImageItem embedded in image
  uint32  :item_offset, :initial_value => 1024       # item table offset (header is 1024)
  uint32  :item_attr
  uint32  :append_size                               # additional data length
  uint32  :append_offset_lo
  uint32  :append_offset_hi
  uint32  :unk1
  uint32  :unk2
  uint32  :unk3
  string  :reserved, :length => 928, :trim_padding => true
  hide    :reserved
end

# Unified Livesuit image structure
class AWImage < BinData::Record
  endian :little
  string  :magic, :length => 8, :asserted_value => "IMAGEWTY"
  uint32  :image_format, :initial_value => 0x300
  choice  :header, :selection => :image_format do
    aw_image_header_v1 0x100
    aw_image_header_v3 0x300
  end
  choice  :item, :selection => :image_format do
    array 0x100, :type => :aw_image_item_v1, :initial_length => lambda { header.item_count }
    array 0x300, :type => :aw_image_item_v3, :initial_length => lambda { header.item_count }
  end

  # Useful to see image data
  def inspect
    out = ""
    self.each_pair do |k ,v|
      out << "%-40s" % k.to_s.yellow unless [:header, :item, :magic].include? k
      case k
      when :image_format then out << "0x%03x\n" % v
      when :header
        v.each_pair do |i, j|
          out << "%-40s%s\n" % [i.to_s.yellow, j] if i == :item_count
          out <<  "%-40s%d MB\n" % [i.to_s.yellow, j>>  20] if i == :len_low
        #  out "res:" << reserved.inspect if i == :reserved
        end
      when :item
        out <<  "Items\n".light_blue
        v.each { |it| out <<  it.inspect << "\n" }
      end
    end
    out
  end

  # Get item from LiveSuit image by file name
  # @param filename [String] item name without path (i.e. system.fex, u-boot.fex, ...)
  # @return [AWImageItemV1, AWImageItemV3, nil] first item if found, else nil
  def item_by_file(filename)
    item = self.item.select do |it|
      it.path.match(/(?:.*\\)?(.+)$/)[1] == filename
    end
    item.first if item
  end

  # Get item from LiveSuit image by signature
  # @param sub_type [String] signature (i.e. BOOTLOADER_FEX00,  BOOT_FEX00000000, ...)
  # @return [AWImageItemV1, AWImageItemV3, nil] first item if found, else nil
  def item_by_sign(signature)
    item = self.item.select do |it|
      it.sub_type == filename
    end
    item.first if item
  end

end

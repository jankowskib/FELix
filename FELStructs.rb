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
require_relative 'FELConsts'

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
class Partition < BinData::Record
  endian :little
  uint32 :address_high
  uint32 :address_low
  uint32 :lenhi
  uint32 :lenlo
  string :classname, :length => 16
  string :name, :length => 16
  uint32 :user_type
  uint32 :keydata
  uint32 :ro
  array  :reserved, :type => :uint8, :initial_length => 68
end

# Structure for SUNXI boot, record size: 16384
class AWNandMBR < BinData::Record
  uint32le :crc
  uint32le :version
  string   :magic, :length => 8, :initial_value => "softw311" # or softw411
  uint32le :copy
  uint32le :part_index
  uint32le :mbr_count
  uint32le :stamp
  array    :part, :type => :partition, :initial_length => 120
  array    :reserved, :type => :uint8, :initial_length => 992
end

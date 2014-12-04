#   FELConsts.rb
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

FELIX_VERSION = "1.0 alfa"

#AWUSBRequest types
module AWUSBCommand
  AW_USB_READ                           = 0x11
  AW_USB_WRITE                          = 0x12
end

#\1: Messages (R -> Read, W -> Write => the operation you must do after send)
AWCOMMAND = {
  :FEL_R_VERIFY_DEVICE                   => 0x1,
  :FEL_R_SWITCH_ROLE                     => 0x2,
  :FEL_R_IS_READY                        => 0x3, # Read len 8
  :FEL_R_GET_CMD_SET_VER                 => 0x4,
  :FEL_R_DISCONNECT                      => 0x10,
  :FEL_W_DOWNLOAD                        => 0x101,
  :FEL_R_RUN                             => 0x102,
  :FEL_R_UPLOAD                          => 0x103,
  #FES Messages
  :FEX_CMD_FES_RW_TRANSMITE              => 0x201,
  :FEX_CMD_FES_W_RUN                     => 0x202,
  :FEX_CMD_FES_W_INFO                    => 0x203, # len ∈ {24...31}
  :FEX_CMD_FES_R_GET_MSG                 => 0x204,
  :FEX_CMD_FES_R_UNREG_FED               => 0x205,
  :FEX_CMD_FES_DOWNLOAD                  => 0x206,
  :FEX_CMD_FES_UPLOAD                    => 0x207,
  :FEX_CMD_FES_VERIFY                    => 0x208,
  :FEX_CMD_FES_QUERY_STORAGE             => 0x209,
  :FEX_CMD_FES_R_FLASH_SET_ON            => 0x20A,
  :FEX_CMD_FES_R_FLASH_SET_OFF           => 0x20B,
  :FEX_CMD_FES_VERIFY_VALUE              => 0x20C,
  :FEX_CMD_FES_VERIFY_STATUS             => 0x20D, # Read len 12
  :FEX_CMD_FES_FLASH_SIZE_PROBE          => 0x20E,
  :FEX_CMD_FES_TOOL_MODE                 => 0x20F,
  :FEX_CMD_FES_MEMSET                    => 0x210,
  :FEX_CMD_FES_PMU                       => 0x211,
  :FEX_CMD_FES_UNSEQMEM_READ             => 0x212,
  :FEX_CMD_FES_UNSEQMEM_WRITE            => 0x213
}

module FESTransmiteFlag
  FES_W_DOU_DOWNLOAD                    = 0x1000
  FES_R_DOU_UPLOAD                      = 0x2000
end

FEL_DEVICE_MODE = {
  :AL_VERIFY_DEV_MODE_NULL               => 0x0,
  :AL_VERIFY_DEV_MODE_FEL                => 0x1,
  :AL_VERIFY_DEV_MODE_SRV                => 0x2,
  :AL_VERIFY_DEV_MODE_UPDATE_COOL        => 0x3,
  :AL_VERIFY_DEV_MODE_UPDATE_HOT         => 0x4
}
#TAGS FOR FEX_CMD_FES_DOWN
module FEXTags
  TAG_DATA_MASK                         = 0x7FFF
  TAG_DRAM_MASK                         = 0x7F00
  TAG_DRAM                              = 0x7F00
  TAG_MBR                               = 0x7F01
  TAG_UBOOT                             = 0x7F02
  TAG_BOOT1                             = 0x7F02
  TAG_BOOT0                             = 0x7F03
  TAG_ERASE                             = 0x7F04
  TAG_PMU_SET                           = 0x7F05
  TAG_UNSEQ_MEM_FOR_READ                = 0x7F06
  TAG_UNSEQ_MEM_FOR_WRITE               = 0x7F07
  TAG_FLASH                             = 0x8000
  TAG_FINISH                            = 0x10000
  TAG_START                             = 0x20000
  TAG_MASK                              = 0x30000
end
#FES STORAGE TYPE
module FESMediaType
  FES_MEDIA_INDEX_DRAM                  = 0x0
  FES_MEDIA_INDEX_PHYSICAL              = 0x1
  FES_MEDIA_INDEX_LOG                   = 0x2
end

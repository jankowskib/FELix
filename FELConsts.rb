#   FELConsts.rb
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

# App version
FELIX_VERSION = "1.0 RC6"

# Maximum data transfer length
FELIX_MAX_CHUNK  = 65536
# NAND sector size
FELIX_SECTOR = 512
# Image header string
FELIX_IMG_HEADER = "IMAGEWTY"

# RC6 keys
RC6Keys = {
  :header => RC6.new("\0" * 31 << "i"),
  :item   => RC6.new("\1" * 31 << "m"),
  :data   => RC6.new("\2" * 31 << "g")
}

# Error exit code - everything OK
FELIX_SUCCESS = 0
# Error exit code - something wrong happened
FELIX_FAIL = 1
# Error exit code - unhandled erorrs (WTF)
FELIX_FATAL = 2

# Uboot checksum constant
UBOOT_STAMP_VALUE = 0x5F0A6C39

#AWUSBRequest type
USBCmd = {
  :read                            => 0x11,
  :write                           => 0x12
}

#FEL Messages
FELCmd = {
  :verify_device                   => 0x1, # [@get_device_status] can be used in FES
  :switch_role                     => 0x2,
  :is_ready                        => 0x3, # Read len 8, can be used in FES
  :get_cmd_set_ver                 => 0x4, # can be used in FES, may be used to check what commands are available (16 bytes)
  :disconnect                      => 0x10,
  :download                        => 0x101, # [@write] write
  :run                             => 0x102, # [@run] execute
  :upload                          => 0x103  # [@read] read
}

#FES Messages
FESCmd = {
  :transmit                        => 0x201, # [@transmit] read,write depends on flag, do not use
  :run                             => 0x202, # [@run]
  :info                            => 0x203, # [@info] get if FES_RUN has finished (32 bytes)
  :get_msg                         => 0x204, # [@get_msg] get result of last FES_RUN (param buffer size)
  :unreg_fed                       => 0x205, # [@unreg_fed] unmount NAND/MMC
  # Following are available on boot2.0
  :download                        => 0x206, # [@write]
  :upload                          => 0x207, # [@read]
  :verify                          => 0x208, # check CRC of given memory block, not implemented
  :query_storage                   => 0x209, # [@query_storage] used to check if we boot from nand or sdcard
  :flash_set_on                    => 0x20A, # [@set_storage_state] exec sunxi_sprite_init(0) => no data
  :flash_set_off                   => 0x20B, # [@set_storage_state] exec sunxi_sprite_exit(1) => no data
  :verify_value                    => 0x20C, # [@verify_value] compute and return CRC of given mem block => AWFESVerifyStatusResponse
  :verify_status                   => 0x20D, # [@verify_status] read len 12 => AWFESVerifyStatusResponse
  :flash_size_probe                => 0x20E, # read len 4 => sunxi_sprite_size()
  :tool_mode                       => 0x20F, # [@set_tool_mode] can be used to reboot device
                                             # :toolmode is one of AWUBootWorkMode
                                             # :nextmode is desired mode
  :memset                          => 0x210, # can be used to fill memory with desired value (byte)
  :pmu                             => 0x211, # change voltage setting
  :unseqmem_read                   => 0x212, # unsequenced memory read
  :unseqmem_write                  => 0x213,
  # From https://github.com/allwinner-zh/bootloader unavailable on most tablets <2015 year
  :fes_reset_cpu                   => 0x214,
  :low_power_manger                => 0x215,
  :force_erase                     => 0x220,
  :force_erase_key                 => 0x221,
  :query_secure                    => 0x230 # [@query_secure]
}

# Mode returned by FELCmd[:verify_device]
AWDeviceMode = {
  :null                            => 0x0,
  :fel                             => 0x1,
  :fes                             => 0x2, # also :srv
  :update_cool                     => 0x3,
  :update_hot                      => 0x4
}

AWSecureStatusMode  = {
  :sunxi_normal_mode                   => 0x0,
  :sunxi_secure_mode_with_secureos     => 0x1,
  :sunxi_secure_mode_no_secureos       => 0x2,
  :sunxi_secure_mode                   => 0x3,
  :sunxi_secure_mode_unknown           => -1  # added by me
}

# U-boot mode (uboot_spare_head.boot_data.work_mode,0xE0 offset)
AWUBootWorkMode = {
  :boot                            => 0x0,  # normal start
  :usb_tool_product                => 0x4,  # if :action => :none, then reboots device
  :usb_tool_update                 => 0x8,
  :usb_product                     => 0x10, # FES mode
  :card_product                    => 0x11, # SD-card flash
  :usb_debug                       => 0x12, # FES mode with debug
  :sprite_recovery                 => 0x13,
  :usb_update                      => 0x20, # USB upgrade (automatically inits nand!)
  :erase_key                       => 0x20, # replaced on A83
  :outer_update                    => 0x21  # external disk upgrade
}

# Used as argument for FES_SET_TOOL_MODE. Names are self-explaining
AWActions = {
  :none                             => 0x0,
  :normal                           => 0x1,
  :reboot                           => 0x2,
  :shutdown                         => 0x3,
  :reupdate                         => 0x4,
  :boot                             => 0x5,
  :sprite_test                      => 0x6
}

# Flag for FESCmd[:transmit]
FESTransmiteFlag = {
  :write                           => 0x10, # aka :download
  :read                            => 0x20, # aka :upload
# used on boot1.0 (index must be | :write)
  :start                           => 0x40,
  :finish                          => 0x80,
}

#TAGS FOR FES_DOWN
AWTags = {
  :none                            => 0x0,
  :dram                            => 0x7F00,
  :mbr                             => 0x7F01, # this flag actually perform erase
  :uboot                           => 0x7F02,
  :boot1                           => 0x7F02,
  :boot0                           => 0x7F03,
  :erase                           => 0x7F04, # forces platform->eraseflag
  :pmu_set                         => 0x7F05,
  :unseq_mem_for_read              => 0x7F06,
  :unseq_mem_for_write             => 0x7F07,
  :full_size                       => 0x7F10, # as seen on A80, download whole image at once
  :flash                           => 0x8000, # used only for writing
  :finish                          => 0x10000,
  :start                           => 0x20000,
}

#csw_status of AWUSBResponse
AWUSBStatus = {
  :ok => 0,
  :fail => 1
}

#FES STORAGE TYPE
FESIndex = {
  :dram                            => 0x0,
  :physical                        => 0x1,
  :nand                            => 0x2,
  :log                             => 0x2,
# these below are usable on boot 1.0
  :card                            => 0x3,
  :spinor                          => 0x3,
  :nand2                           => 0x20 # encrypted data write?
}

# Result of FES_QUERY_STORAGE
AWStorageType = {
    :nand                            => 0x0,
    :card                            => 0x1,
    :card2                           => 0x2,
    :spinor                          => 0x3,
    :unknown                         => -1 # added by me
}

#Livesuit image attributes
AWImageAttr = {
  :res                            => 0x800,
  :length                         => 0x80000,
  :encode                         => 0x4000000,
  :compress                       => 0x80000000
}

#FES run types (AWFELMessage->len)
AWRunContext = {
  :none                           => 0x0,
  :has_param                      => 0x1,
  :fet                            => 0x10,
  :gen_code                       => 0x20,
  :fed                            => 0x30
}

#Live suit item types
AWItemType = {
  :common                         => "COMMON",
  :info                           => "INFO",
  :bootrom                        => "BOOTROM",
  :fes                            => "FES",
  :fet                            => "FET",
  :fed                            => "FED",
  :fex                            => "FEX",
  :boot0                          => "BOOT0",
  :boot1                          => "BOOT1",
  :rootfsfat12                    => "RFSFAT12",
  :rootfsfat16                    => "RFSFAT16",
  :rootfsfat32                    => "FFSFAT32",
  :userfsfat12                    => "UFSFAT12",
  :userfsfat16                    => "UFSFAT16",
  :userfsfat32                    => "UFSFAT32",
  :phoenix_script                 => "PXSCRIPT",
  :phoenix_tools                  => "PXTOOLS",
  :audio_dsp                      => "AUDIODSP",
  :video_dsp                      => "VIDEODSP",
  :font                           => "FONT",
  :flash_drv                      => "FLASHDRV",
  :os_core                        => "OS_CORE",
  :driver                         => "DRIVER",
  :pic                            => "PICTURE",
  :audio                          => "AUDIO",
  :video                          => "VIDEO",
  :application                    => "APP"
}

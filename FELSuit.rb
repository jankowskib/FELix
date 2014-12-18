#   FELSuit.rb
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

class FELix
end

# Contains methods to emulate LiveSuit
class FELSuit < FELix

  # Initialize device and check image file
  # @param device [LIBUSB::Device] a device
  # @param file [String] LiveSuit image
  def initialize(device, file)
    super(device)
    @image = file
    raise FELError, "Image not found!" unless File.exist?(@image)
    @encrypted = encrypted?
    @structure = fetch_image_structure
    puts @structure.inspect
  end

  # Flash image to the device
  # @raise error string if something wrong happen
  def flash
    # 1. Let's check device mode
    info = get_device_info
    raise FELError, "Failed to get device info. Try to reboot!" unless info
    # 2. If we're in FEL mode we must firstly boot2fes
    boot_to_fes && info = get_device_info if info.mode == :fel
    raise FELError, "Failed to boot to fes" unless info.mode == :fes
  end

  # Download egon, uboot and run code in hope we boot to fes
  # @param egon [String] FES binary data (init dram code, eGON, fes1.fex)
  # @param uboot [String] U-boot binary data (u-boot.fex)
  # @todo Verify header (eGON.BT0, uboot)
  # @raise [String] error name
  def boot_to_fes(egon, uboot)
    raise FELError, "eGON is too big (#{egon.bytesize}>16384)" if egon.bytesize>16384
    write(0x2000, egon)
    run(0x2000)
    write(0x4a000000, uboot)
    write(0x4a0000E0, AWUBootWorkMode[:usb_product].to_s.to_byte_string) # write 0x10 flag
    run(0x4a000000)
  end

  # Write MBR to NAND (and do format)
  # @param mbr [String] new mbr. Must have 65536 bytes of length
  # @param format [TrueClass, FalseClass] erase data
  # @return [AWFESVerifyStatusResponse] result of sunxi_sprite_download_mbr (crc:-1 if fail)
  # @raise [String] error name
  # @note Use only in :fes mode
  # @note **Warining**: Device may do format anyway if NAND version doesn't match!
  def write_mbr(mbr, format=false)
    raise FELError, "MBR is empty!" if mbr.empty?
    raise FELError, "MBR is too small" unless mbr.bytesize == 65536
    # 1. Force platform->erase_flag => 1 or 0 if we dont wanna erase
    write(0, format ? "\1\0\0\0" : "\0\0\0\0", [:erase, :finish], :fes)
    # 2. Verify status (actually this is unecessary step [last_err is not set at all])
    # verify_status(:erase)
    # 3. Write MBR
    write(0, mbr, [:mbr, :finish], :fes)
    # 4. Get result value of sunxi_sprite_verify_mbr
    verify_status(:mbr)
  end

  # Check if image is encrypted
  # @raise [FELError] if image decryption failed
  def encrypted?
    img = File.read(@image, 16) # Read block
    return false if img.byteslice(0, 8) == "IMAGEWTY"
    img = FELHelpers.decrypt(img, FELIX_HEADER_KEY) if img.byteslice(0, 8) !=
    "IMAGEWTY"
    return true if img.byteslice(0, 8) == "IMAGEWTY"
    raise FELError, "Failed to decrypt image"
  end

  # Read item from LiveSuit image
  # @param item [String] item name without path (i.e. system.fex, u-boot.fex,...)
  def get_image_item(item)

  end

  # Read header & image items information
  # @return [AWImage] LiveSuit image structure
  def fetch_image_structure
    if @encrypted
        File.open(@image) do |f|
        # @todo improve that
        header = f.read(1024)
        header = FELHelpers.decrypt(header, FELIX_HEADER_KEY)
        img_version = header[8, 4].unpack("V").first
        item_count = header[img_version == 0x100 ? 0x38 : 0x3C, 4].
          unpack("V").first
        items = f.read(item_count * 1024)
        header << FELHelpers.decrypt(items, FELIX_ITEM_KEY)
        AWImage.read(header)
    end
    else
      # much faster if image is not encrypted
      File.open(@image) { |f| AWImage.binread(f) }
    end
  end

end

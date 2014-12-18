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
    raise FELError, "Flashing old images is not supported " <<
      "yet!" unless @structure.item_by_file("u-boot.fex") && @structure.
      item_by_file("fes1.fex")
  end

  # Flash image to the device
  # @raise error string if something wrong happen
  # @yieldparam [String] status
  # @yieldparam [Integer] Percentage status if there's active transfer
  def flash
    # 1. Let's check device mode
    info = get_device_info
    raise FELError, "Failed to get device info. Try to reboot!" unless info
    # 2. If we're in FEL mode we must firstly boot2fes
    uboot = get_image_data(@structure.item_by_file("u-boot.fex"))
    fes = get_image_data(@structure.item_by_file("fes1.fex"))
    if info.mode == AWDeviceMode[:fel]
      yield "Booting to FES" if block_given?
      boot_to_fes(fes, uboot)
      yield "Waiting for reconnection" if block_given?
      # 3. Wait for device reconnection
      # @todo use hotplug in the future
      sleep(5)
      raise FELError, "Failed to reconnect!" unless reconnect?
      info = get_device_info
    end
    # 4. Write MBR
    # @todo add format parameter
    yield "Writing new paratition table"
    raise FELError, "Failed to boot to fes" unless info.mode == AWDeviceMode[:fes]
    mbr = get_image_data(@structure.item_by_file("sunxi_mbr.fex"))
    dlinfo = AWDownloadInfo.read(get_image_data(@structure.item_by_file(
      "dlinfo.fex")))
    status = write_mbr(mbr, true)
    raise FELError, "Cannot flash new partition table" if status.crc != 0
    # 5. Enable NAND
    yield "Attaching NAND driver"
    set_storage_state(:on)
    # 6. Write partitions
    dlinfo.item.each do |item|
      break if item.name.empty?
      part = @structure.item_by_sign(item.filename)
      raise FELError, "Cannot find item: #{item.filename} in the " <<
        "image" unless part
      yield "Reading #{item.name}"
      data = get_image_data(part)
      yield "Writing #{item.name}"
      write(item.address_low, data, :none, :fes) do |n|
        yield "Writing #{item.name}", (n * data.bytesize) / 100
      end
    end
    # 7. Disable NAND
    yield "Detaching NAND driver"
    set_storage_state(:off)
    # 8. Write u-boot
    yield "Writing u-boot"
    write(0, uboot, :uboot, :fes) do |n|
      yield "Writing u-boot", (n * uboot.bytesize) / 100
    end
    # 9. Write boot0
    boot0 = get_image_data(@structure.item_by_file("boot0_nand.fex"))
    yield "Writing boot0"
    write(0, boot0, :boot0, :fes) do |n|
      yield "Writing boot0", (n * boot0.bytesize) / 100
    end
    # 10. Reboot
    yield "Rebooting"
    set_tool_mode(:usb_tool_update, :none)
    yield "Finished"
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
    write(0x4a0000E0, AWUBootWorkMode[:usb_product].chr) # write 0x10 flag
    run(0x4a000000)
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

  # Read item data from LiveSuit image
  # @param item [AWImageItemV1, AWImageItemV3] item data
  # @return [String] binary data
  # @raise [FELError] if read failed
  def get_image_data(item)
    raise FELError, "Item not exist" unless item
    data = File.read(@image, item.data_len_low,item.off_len_low)
    raise FELError, "Cannot read data" unless data
    data = FELHelpers.decrypt(data, FELIX_DATA_KEY) if @encrypted
    data
    # @todo decrypt twofish
  end

  # Read header & image items information
  # @return [AWImage] LiveSuit image structure
  def fetch_image_structure
    if @encrypted
      File.open(@image) do |f|
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
      File.open(@image) { |f| AWImage.read(f) }
    end
  end

end

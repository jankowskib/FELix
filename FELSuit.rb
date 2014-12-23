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

  attr_reader :structure

  # Initialize device and check image file
  # @param device [LIBUSB::Device] a device
  # @param file [String] LiveSuit image
  def initialize(device, file)
    super(device)
    @image = file
    raise FELError, "Image not found!" unless File.exist?(@image)
    @encrypted = encrypted?
    @structure = fetch_image_structure
  end

  # Flash image to the device
  # @raise error string if something wrong happen
  # @yieldparam [String] status
  # @yieldparam [Integer] Percentage status if there's active transfer
  def flash
    raise FELError, "Flashing old images is not supported " <<
      "yet!" unless @structure.item_by_file("u-boot.fex") && @structure.
      item_by_file("fes1.fex")
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
    yield "Writing new paratition table" if block_given?
    raise FELError, "Failed to boot to fes" unless info.mode == AWDeviceMode[:fes]
    mbr = get_image_data(@structure.item_by_file("sunxi_mbr.fex"))
    dlinfo = AWDownloadInfo.read(get_image_data(@structure.item_by_file(
      "dlinfo.fex")))
    status = write_mbr(mbr, false)
    raise FELError, "Cannot flash new partition table" if status.crc != 0
    # 5. Enable NAND
    yield "Attaching NAND driver" if block_given?
    set_storage_state(:on)
    # 6. Write partitions
    dlinfo.item.each do |item|
      break if item.name.empty?
      part = @structure.item_by_sign(item.filename)
      raise FELError, "Cannot find item: #{item.filename} in the " <<
        "image" unless part
      yield "Flashing #{item.name}" if block_given?
      curr_add = item.address_low
      if item.name == "system"
        sys_handle = get_image_handle(part)
        sparse = SparseImage.new(sys_handle, part.off_len_low)
        # @todo
        # 4096 % 512 == 0 so it shouldn't be a problem
        # but 4096 / 65536 it is
        queue = Queue.new
        threads = []
        threads << Thread.new do
          i = 0
          sparse.each_chunk do |data|
            i+=1
            yield ("Decompressing #{item.name}"), (i * 100) / sparse.
              count_chunks if block_given?
            queue << data
          end
          sys_handle.close
        end
        threads << Thread.new do
          written = 0
          while written < part.data_len_low
            data = queue.pop
            written+=data.bytesize
            write(curr_add, data, :none, :fes, written < part.data_len_low)
            curr_add+=data.bytesize / 512
            yield ("Writing #{item.name} @ 0x%08x" % curr_add), (written * 100) /
              sparse.get_final_size if block_given?
          end
          yield "Writing #{item.name}", 100 if block_given?
        end
        threads.each {|t| t.join}
      else
        queue = Queue.new
        threads = []
        # reader
        threads << Thread.new do
          read = 0
          get_image_data(part) do |data|
            read+=data.bytesize
            yield "Reading #{item.name}", (read * 100) / part.
              data_len_low if block_given?
            queue << data
          end
        end
        # writter
        threads << Thread.new do
          written = 0
          while written < part.data_len_low
            data = queue.pop
            written+=data.bytesize
            write(curr_add, data, :none, :fes, written < part.data_len_low) do
              yield "Writing #{item.name}", (written * 100) / part.
                data_len_low if block_given?
            end
            curr_add+=data.bytesize / 512
          end
          yield "Writing #{item.name}", 100 if block_given?
        end
        threads.each {|t| t.join}
      end
    end
    # 7. Disable NAND
    yield "Detaching NAND driver" if block_given?
    set_storage_state(:off)
    # 8. Write u-boot
    yield "Writing u-boot" if block_given?
    write(0, uboot, :uboot, :fes) do |n|
      yield "Writing u-boot", (n * 100) / uboot.bytesize if block_given?
    end
    # 9. Write boot0
    boot0 = get_image_data(@structure.item_by_file("boot0_nand.fex"))
    yield "Writing boot0" if block_given?
    write(0, boot0, :boot0, :fes) do |n|
      yield "Writing boot0", (n * 100) / boot0.bytesize if block_given?
    end
    # 10. Reboot
    yield "Rebooting" if block_given?
    set_tool_mode(:usb_tool_update, :none)
    yield "Finished" if block_given?
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
    img = FELHelpers.decrypt(img, :header) if img.byteslice(0, 8) !=
    "IMAGEWTY"
    return true if img.byteslice(0, 8) == "IMAGEWTY"
    raise FELError, "Failed to decrypt image"
  end

  # Check image format
  def legacy?
    not (@structure.item_by_file("u-boot.fex") && @structure.item_by_file(
      "fes1.fex"))
  end

  # Read item data from LiveSuit image
  # @param item [AWImageItemV1, AWImageItemV3] item data
  # @param chunk [Integer] size of yielded chunk
  # @param length [Integer] how much data to read
  # @param offset [Integer] where to start reading of data
  # @return [String] binary data if no block given
  # @yieldparam [String] data
  # @raise [FELError] if read failed
  def get_image_data(item, chunk = FELIX_MAX_CHUNK, length = item.data_len_low,
    offset = 0)
    raise FELError, "Item not exist" unless item
    if block_given?
      File.open(@image) do |f|
        f.seek(item.off_len_low + offset, IO::SEEK_CUR)
        read = 0
        while data = f.read(chunk)
          data = FELHelpers.decrypt(data, :data) if @encrypted
          read+=data.bytesize
          left = read - length
          if left > 0
            yield data.byteslice(0, data.bytesize - left)
            break
          else
            yield data
            break if read == length
          end
        end
      end
    else
      data = File.read(@image, length, item.off_len_low + offset)
      raise FELError, "Cannot read data" unless data
      data = FELHelpers.decrypt(data, :data) if @encrypted
      data
      # @todo decrypt twofish
    end
  end

  # Seeks to image position and get file handle
  # @param item [AWImageItemV1, AWImageItemV3] item data
  # @return [File] handle
  # @raise [FELError] if failed
  # @note Don't forget to close handle after
  def get_image_handle(item)
    raise FELError, "Item not exist" unless item
    f = File.open(@image)
    f.seek(item.off_len_low, IO::SEEK_CUR)
    f
  end

  # Read header & image items information
  # @return [AWImage] LiveSuit image structure
  def fetch_image_structure
    if @encrypted
      File.open(@image) do |f|
        header = f.read(1024)
        header = FELHelpers.decrypt(header, :header)
        img_version = header[8, 4].unpack("V").first
        item_count = header[img_version == 0x100 ? 0x38 : 0x3C, 4].
          unpack("V").first
        items = f.read(item_count * 1024)
        header << FELHelpers.decrypt(items, :item)
        AWImage.read(header)
      end
    else
      # much faster if image is not encrypted
      File.open(@image) { |f| AWImage.read(f) }
    end
  end

end

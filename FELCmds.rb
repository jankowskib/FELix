#   FELCmds.rb
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

class FELix

  # Send a request
  # @param data the binary data
  # @raise [FELError, FELFatal]
  def send_request(data)
  # 1. Send AWUSBRequest to inform what we want to do (write/read/how many data)
    request = AWUSBRequest.new
    request.len = data.bytesize
    FELHelpers.debug_packet(request.to_binary_s, :write) if $options[:verbose]
    @handle.bulk_transfer(:dataOut => request.to_binary_s, :endpoint =>
     @usb_out, :timeout=>(5 * 1000))
  # 2. Send a proper data
    FELHelpers.debug_packet(data, :write) if $options[:verbose]
    @handle.bulk_transfer(:dataOut => data, :endpoint => @usb_out, :timeout=>(5 * 1000))
  # 3. Get AWUSBResponse
  # Some request takes a lot of time (i.e. NAND format). Try to wait 60 seconds for response.
    r3 = @handle.bulk_transfer(:dataIn => 13, :endpoint => @usb_in, :timeout=>(60 * 1000))
    FELHelpers.debug_packet(r3, :read) if $options[:verbose]
  rescue LIBUSB::ERROR_INTERRUPTED, LIBUSB::ERROR_TIMEOUT
    raise FELError, "Transfer cancelled"
  rescue => e
    raise FELFatal, "Failed to send ".red << "#{data.bytesize}".yellow << " bytes".red <<
    " (" << e.message << ")"
  end

  # Read data
  # @param len an expected length of the data
  # @return [String] the binary data
  # @raise [FELError, FELFatal]
  def recv_request(len)
  # 1. Send AWUSBRequest to inform what we want to do (write/read/how many data)
    request = AWUSBRequest.new
    request.len = len
    request.cmd = USBCmd[:read]
    FELHelpers.debug_packet(request.to_binary_s, :write) if $options[:verbose]
    @handle.bulk_transfer(:dataOut => request.to_binary_s, :endpoint => @usb_out)
  # 2. Read data of length we specified in request
    recv_data = @handle.bulk_transfer(:dataIn => len, :endpoint => @usb_in)
    FELHelpers.debug_packet(recv_data, :read) if $options[:verbose]
  # 3. Get AWUSBResponse
    response = @handle.bulk_transfer(:dataIn => 13, :endpoint => @usb_in)
    FELHelpers.debug_packet(response, :read) if $options[:verbose]
    recv_data
  rescue LIBUSB::ERROR_INTERRUPTED, LIBUSB::ERROR_TIMEOUT
    raise FELError, "Transfer cancelled"
  rescue => e
    raise FELFatal, "Failed to receive ".red << "#{len}".yellow << " bytes".red <<
    " (" << e.message << ")"
  end

  # An unified higher level function for PC<->device communication
  #
  # @param direction [:push, :pull] a method of transfer
  # @param request [AWFELMessage, AWFELStandardRequest] a request
  # @param size [Integer] an expected size of an answer (for `:pull`)
  # @param data [String] the binary data (for `:push`)
  # @return [String, nil] the received answer (for `:pull`)
  # @raise [FELError, FELFatal]
  def transfer(direction, request, size:nil, data:nil)
    raise FELFatal, "\nAn invalid argument for :pull" if data && direction == :pull
    raise FELFatal, "\nAn invalid argument for :push" if size && direction == :push
    raise FELFatal, "\nAn invalid direction: #{direction}" unless [:pull, :push].
      include? direction

    begin
      send_request(request.to_binary_s)
    rescue FELError
      retry
    rescue FELFatal => e
      raise FELFatal, "\nFailed to send a request: #{e}"
    end

    answer = nil

    case direction
    when :pull
      begin
        answer = recv_request(size)
        raise FELFatal, "An unexpected answer length ( #{answer.length} <>" <<
          " #{size})" if answer.length!= size
      rescue FELFatal => e
        raise FELFatal, "\nFailed to get the data (#{e})"
      end if size > 0
    when :push
        begin
          send_request(data)
        rescue FELError
          retry
        rescue FELFatal => e
          raise FELFatal, "\nFailed to send the data: #{e}"
        end if data
    end

    begin
      data = recv_request(8)
      status = AWFELStatusResponse.read(data)
      raise FELError, "\nCommand execution failed (Status #{status.state})" if
        status.state > 0
    rescue BinData::ValidityError => e
      raise FELFatal, "\nAn unexpected device response: #{e}"
    rescue FELFatal => e
      raise FELFatal, "\nFailed to receive the device status: #{e}"
    end

    answer if direction == :pull
  end

  # Get the device status
  # @return [AWFELVerifyDeviceResponse] a status of the device
  # @raise [FELError, FELFatal]
  def get_device_status
    answer = transfer(:pull, AWFELStandardRequest.new, size: 32)
    AWFELVerifyDeviceResponse.read(answer)
  end

  # Read memory from device
  # @param address [Integer] a memory address to read from
  # @param length [Integer] a size of the read memory
  # @param tags [Symbol, Array<AWTags>] an operation tag (zero or more of AWTags)
  # @param mode [AWDeviceMode] an operation mode `:fel` or `:fes`
  # @return [String] the requested memory block if block has only one parameter
  # @raise [FELError, FELFatal]
  # @yieldparam [Integer] bytes read as far
  # @yieldparam [String] read data chunk of `FELIX_MAX_CHUNK`
  # @note Not usable on the legacy fes (boot1.0)
  def read(address, length, tags=[:none], mode=:fel, &block)
    raise FELError, "The length is not specifed" unless length
    raise FELError, "The address is not specifed" unless address
    result = ""
    remain_len = length
    request = AWFELMessage.new
    request.cmd = mode == :fel ? FELCmd[:upload] : FESCmd[:upload]
    request.address = address.to_i
    if tags.kind_of?(Array)
      tags.each {|t| request.flags |= AWTags[t]}
    else
      request.flags |= AWTags[tags]
    end

    while remain_len>0
      if remain_len / FELIX_MAX_CHUNK == 0
        request.len = remain_len
      else
        request.len = FELIX_MAX_CHUNK
      end

      data = transfer(:pull, request, size: request.len)
      result << data if block.arity < 2
      remain_len-=request.len

      # if EFEX_TAG_DRAM isnt set we read nand/sdcard
      if request.flags & AWTags[:dram] == 0 && mode == :fes
        next_sector=request.len / 512
        request.address+=( next_sector ? next_sector : 1) # Read next sector if its less than 512
      else
        request.address+=request.len
      end
      yield length-remain_len, data if block_given?
    end
    result
  end

  # Write data to device memory
  # @param address [Integer] a place in memory to write
  # @param memory [String] data to write
  # @param tags [Symbol, Array<AWTags>] an operation tag (zero or more of AWTags)
  # @param mode [AWDeviceMode] an operation mode `:fel` or `:fes`
  # @param dontfinish do not set finish tag in `:fes` context
  # @raise [FELError, FELFatal]
  # @yieldparam [Integer] bytes written as far
  # @note Not usable on the legacy fes (boot1.0)
  def write(address, memory, tags=[:none], mode=:fel, dontfinish=false)
    raise FELError, "The memory is not specifed" unless memory
    raise FELError, "The address is not specifed" unless address
    total_len = memory.bytesize
    start = 0
    request = AWFELMessage.new
    request.cmd = mode == :fel ? FELCmd[:download] : FESCmd[:download]
    request.address = address.to_i
    if tags.kind_of?(Array)
      tags.each {|t| request.flags |= AWTags[t]}
    else
      request.flags |= AWTags[tags]
    end

    while total_len>0
      if total_len / FELIX_MAX_CHUNK == 0
        request.len = total_len
      else
        request.len = FELIX_MAX_CHUNK
      end
      # At last chunk finish tag must be set
      request.flags |= AWTags[:finish] if mode == :fes &&
        total_len <= FELIX_MAX_CHUNK && dontfinish == false

      transfer(:push, request, data: memory.byteslice(start, request.len))

      start+=request.len
      total_len-=request.len
      # if EFEX_TAG_DRAM isnt set we write nand/sdcard
      if request.flags & AWTags[:dram] == 0 && mode == :fes
        next_sector=request.len / 512
        request.address+=( next_sector ? next_sector : 1) # Write next sector if its less than 512
      else
        request.address+=request.len
      end
      yield start if block_given? # yield sent bytes
    end
  end

  # Execute code at specified memory
  # @param address [Integer] a memory address to read from
  # @param mode [AWDeviceMode] an operation mode `:fel` or `:fes`
  # @param flags [Array<AWRunContext>] zero or more flags (in `:fes` only)
  # @param args [Array<Integer>] an array of arguments if `:has_param` flag is set
  # @note `flags` is `max_para` in boot2.0
  # @raise [FELError, FELFatal]
  def run(address, mode=:fel, flags = :none, args = nil)
    request = AWFELMessage.new
    request.cmd = mode == :fel ? FELCmd[:run] : FESCmd[:run]
    request.address = address

    raise FELFatal, "\nCannot use flags in FEL" if flags != :none && mode == :fel
    if flags.kind_of?(Array)
      flags.each do |f|
        raise FELFatal, "\nAn unknown flag #{f}" unless AWRunContext.has_key? f
        request.len |= AWRunContext[f]
      end
    else
      raise FELFatal, "\nAn unknown flag #{f}" unless AWRunContext.has_key? flags
      request.len |= AWRunContext[flags]
    end
    if request.len & AWRunContext[:has_param] == AWRunContext[:has_param]
      params = AWFESRunArgs.new(:args => args)
      transfer(:push, request, data:params.to_binary_s)
    else
      transfer(:push, request)
    end
  end

  # Send a FES_INFO request (get the code execution status)
  # @raise [FELError, FELFatal]
  # @return [String] the device response (32 bytes)
  def info
    request = AWFELMessage.new
    request.cmd = FESCmd[:info]
    transfer(:pull, request, size: 32)
  end

  # Send a FES_GET_MSG request (get the code execution status string)
  # @param len [Integer] a length of requested data
  # @raise [FELError, FELFatal]
  # @return [String] the device response (default 1024 bytes)
  def get_msg(len = 1024)
    request = AWFELMessage.new
    request.cmd = FESCmd[:get_msg]
    request.address = len
    transfer(:pull, request, size: len)
  end

  # Send a FES_UNREG_FED request (detach the storage)
  # @param type [FESIndex] a storage type
  # @raise [FELError, FELFatal]
  def unreg_fed(type = :nand)
    request = AWFELMessage.new
    request.cmd = FESCmd[:unreg_fed]
    request.address = FESIndex[type]
    transfer(:push, request)
  end

  # Verify the last operation status
  # @param tags [Symbol, Array<AWTags>] an operation tag (zero or more of AWTags)
  # @return [AWFESVerifyStatusResponse] the device status
  # @raise [FELError, FELFatal]
  # @note Use only in a :fes mode
  def verify_status(tags=[:none])
    request = AWFELMessage.new
    request.cmd = FESCmd[:verify_status]
    if tags.kind_of?(Array)
      tags.each {|t| request.flags |= AWTags[t]}
    else
      request.flags |= AWTags[tags]
    end
    # Verification finish flag may be not set immediately
    5.times do
      answer = transfer(:pull, request, size: 12)
      resp = AWFESVerifyStatusResponse.read(answer)
      return resp if resp.flags == 0x6a617603
      sleep(300)
    end
    raise FELError, "The verify process has timed out"
  end

  # Verify the checksum of the given memory block
  # @param address [Integer] a memory address
  # @param len [Integer] a length of verfied block
  # @return [AWFESVerifyStatusResponse] the verification response
  # @raise [FELError, FELFatal]
  # @note Use only in a :fes mode
  def verify_value(address, len)
    request = AWFELMessage.new
    request.cmd = FESCmd[:verify_value]
    request.address = address
    request.len = len

    answer = transfer(:pull, request, size: 12)
    AWFESVerifyStatusResponse.read(answer)
  end

  # Attach / detach the storage (handles `:flash_set_on` and `:flash_set_off`)
  # @param how [Symbol] a desired state of the storage (`:on` or `:off`)
  # @param type [Integer] type of storage. Unused.
  # @raise [FELError, FELFatal]
  # @note Use only in a :fes mode. An MBR must be written before
  def set_storage_state(how, type=0)
    raise FELError, "An invalid parameter state (#{how})" unless [:on, :off].
      include? how
    request = AWFELMessage.new
    request.cmd = how == :on ? FESCmd[:flash_set_on] : FESCmd[:flash_set_off]
    request.address = type # the address field is used for storage type
    transfer(:push, request)
  end

  # Get security system status. (handles `:query_secure`)
  # Secure flag is controlled by `secure_bit` in sys_config.fex
  # See more: https://github.com/allwinner-zh/bootloader/blob/master/u-boot-2011.09/arch/arm/cpu/armv7/sun8iw7/board.c#L300
  #
  # @raise [FELError, FELFatal]
  # @return [Symbol<AWSecureStatusMode>] a status flag
  # @note Use only in a :fes mode
  def query_secure
    request = AWFELStandardRequest.new
    request.cmd = FESCmd[:query_secure]

    status = transfer(:pull, request, size: 4).unpack("V")[0]

    if AWSecureStatusMode.has_value? status
      AWSecureStatusMode.keys[status]
    else
      AWSecureStatusMode.keys[-1]
    end
  end

  # Get currently default storage. (handles `:query_storage`)
  #
  # @raise [FELError, FELFatal]
  # @return [Symbol<FESIndex>] a status flag or `:unknown`
  # @note Use only in a :fes mode
  def query_storage
    request = AWFELStandardRequest.new
    request.cmd = FESCmd[:query_storage]

    status = transfer(:pull, request, size: 4).unpack("V")[0]

    if FESIndex.has_value? status
      FESIndex.keys[status]
    else
      :unknown
    end
  end


  # Send a FES_TRANSMIT request
  # Can be used to read/write memory in FES mode
  #
  # @param direction [Symbol<FESTransmiteFlag>] one of FESTransmiteFlag (`:write` or `:read`)
  # @param opts [Hash] Arguments
  # @option opts :address [Integer] place in memory to transmit
  # @option opts :memory [String] data to write (use only with `:write`)
  # @option opts :media_index [Symbol<FESIndex>] one of index (default `:dram`)
  # @option opts :length [Integer] size of data (use only with `:read`)
  # @option opts :dontfinish [TrueClass, FalseClass] do not set finish tag
  # @raise [FELError, FELFatal]
  # @return [String] the data if `direction` is `:read`
  # @yieldparam [Integer] read/written bytes
  # @note Use only in a :fes mode. Always prefer FES_DOWNLOAD/FES_UPLOAD instead of this in boot 2.0
  # @TODO: Replace opts -> named arguments
  def transmit(direction, *opts)
    opts = opts.first
    opts[:media_index] ||= :dram
    start = 0
    if direction == :write
      raise FELError, "The memory is not specifed" unless opts[:memory]
      raise FELError, "The address is not specifed" unless opts[:address]

      total_len = opts[:memory].bytesize
      address = opts[:address]

      request = AWFESTrasportRequest.new # Little optimization
      request.flags = FESTransmiteFlag[direction]
      request.media_index = FESIndex[opts[:media_index]]
      # Set :start tag when writing to physical memory
      request.flags |= FESTransmiteFlag[:start] if request.media_index>0

      while total_len>0
        request.address = address.to_i
        if total_len / FELIX_MAX_CHUNK == 0
          request.len = total_len
        else
          request.len = FELIX_MAX_CHUNK
        end

        # At last chunk finish tag must be set
        request.flags |= FESTransmiteFlag[:finish] if total_len <= FELIX_MAX_CHUNK && opts[:dontfinish] == false

        transfer(:push, request, data: opts[:memory].byteslice(start, request.len))

        start+=request.len
        total_len-=request.len
        if opts[:media_index] == :dram
          address+=request.len
        else
          next_sector=request.len / 512
          address+=( next_sector ? next_sector : 1) # Write next sector if its less than 512
        end
        yield start if block_given? # yield sent bytes
      end
    elsif direction == :read
      raise FELError, "The length is not specifed" unless opts[:length]
      raise FELError, "The address is not specifed" unless opts[:address]
      result = ""
      request = AWFESTrasportRequest.new
      address = opts[:address]
      request.len = remain_len = length = opts[:length]
      request.flags = FESTransmiteFlag[direction]
      request.media_index = FESIndex[opts[:media_index]]

      while remain_len>0
        request.address = address.to_i
        if remain_len / FELIX_MAX_CHUNK == 0
          request.len = remain_len
        else
          request.len = FELIX_MAX_CHUNK
        end

        result << transfer(:pull, request, size: request.len)

        remain_len-=request.len
        # if EFEX_TAG_DRAM isnt set we read nand/sdcard
        if opts[:media_index] == :dram
          address+=request.len
        else
          next_sector=request.len / 512
          address+=( next_sector ? next_sector : 1) # Read next sector if its less than 512
        end
        yield length-remain_len if block_given?
      end
      result
    else
      raise FELError, "An unknown direction '(#{direction})'"
    end
  end

  # Send a FES_SET_TOOL_MODE request
  # Can be used to change the device state (i.e. reboot)
  # or to change the u-boot work mode
  #
  # @param mode [Symbol<AWUBootWorkMode>] a mode
  # @param action [Symbol<AWActions>] an action.
  #   if the `action` is `:none` and the `mode` is not `:usb_tool_update` then
  #   the action is fetched from a sys_config's platform->next_work key.
  #   If the key does not exist then defaults to `:normal`
  # @raise [FELError, FELFatal]
  # @note Use only in a :fes mode
  # @note Action parameter is respected only if the `mode` is `:usb_tool_update`
  # @note This command is only usable for reboot
  def set_tool_mode(mode, action=:none)
    request = AWFELMessage.new
    request.cmd = FESCmd[:tool_mode]
    request.address = AWUBootWorkMode[mode]
    request.len = AWActions[action]

    transfer(:push, request)
  end

  # Write an MBR to the storage (and do format)
  #
  # @param mbr [String] a new mbr. Must have 65536 bytes of length
  # @param format [Boolean] force data wipe
  # @return [AWFESVerifyStatusResponse] the result of sunxi_sprite_download_mbr (crc:-1 if fail)
  # @raise [FELError, FELFatal]
  # @note Use only in a :fes mode
  # @note **Warning**: The device may do format anyway if the storage version doesn't match!
  def write_mbr(mbr, format=false)
    raise FELError, "\nThe MBR is empty!" if mbr.empty?
    raise FELError, "\nThe MBR is too small" unless mbr.bytesize == 65536
    # 1. Force platform->erase_flag => 1 or 0 if we dont wanna erase
    write(0, format ? "\1\0\0\0" : "\0\0\0\0", [:erase, :finish], :fes)
    # 2. Verify status (actually this is unecessary step [last_err is not set at all])
    # verify_status(:erase)
    # 3. Write MBR
    write(0, mbr, [:mbr, :finish], :fes)
    # 4. Get result value of sunxi_sprite_verify_mbr
    verify_status(:mbr)
  end

end

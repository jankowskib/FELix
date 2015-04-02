
$FELIX_TEST_CASE = true
load "#{File.dirname(__FILE__)}/../felix"

describe FELix do
  context "when device is connected" do
    context "FEL" do

      before(:each) do
        devices = LIBUSB::Context.new.devices(:idVendor => 0x1f3a,
          :idProduct => 0xefe8)
        raise "Please connect device in FEL mode" if devices.empty?
        @fel = FELix.new(devices[0])
      end

      after(:each) do
        @fel.bailout if @fel
      end

      describe "#get_device_status" do
        it "has a device in FEL mode" do
          expect(@fel.get_device_status.mode).to eq(AWDeviceMode[:fel])
        end
      end

      describe "#read" do
        it "reads small chunk of data" do
          @fel.read(0x7E00, 256)
        end
        it "reads big chunk of data (last block is incomplete)" do
          @fel.read(0x7E00, (1 + rand(3)) + rand(FELIX_MAX_CHUNK))
        end
      end

      describe "#write" do
        it "writes small chunk of data" do
          chunk = (0...256).map{65.+(rand(25)).chr}.join
          @fel.write(0x7E00, chunk)
        end
      end

      describe "#read/#write" do
        it "writes and reads small chunk of data" do
          chunk = (0...256).map{65.+(rand(25)).chr}.join
          @fel.write(0x7E00, chunk)
          data = @fel.read(0x7E00, chunk.length)
          expect(data.length).to eq(chunk.length)
          a_crc = Crc32.calculate(chunk, chunk.length, 0)
          b_crc = Crc32.calculate(data, data.length, 0)
          expect(a_crc).to eq(b_crc)
        end
      end

      describe "#run" do
        # @TODO: It'd be hard to figure out universal test for that
      end

    end # FEL commands
  end # device is connected
end


describe FELHelpers do
  describe '::checksum' do
    it 'passes checksum generation test for env' do
      File.open("./spec/assets/env.sample", "rb") do |f|
        expect(FELHelpers.checksum(f.read)).to eq (0x2ae1d857)
      end
    end

    it 'passes checksum generation test for bootloader' do
      File.open("./spec/assets/bootloader.sample", "rb") do |f|
        expect(FELHelpers.checksum(f.read)).to eq (0x93b56219)
      end
    end

    it 'recomputes crc for u-boot binary' do
      uboot = UbootBinary.read(File.read("./spec/assets/u-boot.sample"))
      old_sum = uboot.header.check_sum
      uboot.header.check_sum = UBOOT_STAMP_VALUE
      uboot.header.check_sum = FELHelpers.checksum(uboot.to_binary_s)
      expect(uboot.header.check_sum).to eq(old_sum)
    end

  end

  describe '::port_to_id' do
    it 'decodes port:PB22<2><1><default><default>' do
      expect(FELHelpers.port_to_id("port:PB22<2><1><default><default>")).
      to eq (0x7C4AC1)
    end
    it 'decodes port:PH20<2><1><default><default>' do
      expect(FELHelpers.port_to_id("port:PH20<2><1><default><default>")).
      to eq (0x7C4A87)
    end
  end

end

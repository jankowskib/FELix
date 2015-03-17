require 'colorize'
require 'optparse'
require 'libusb'
require 'bindata'
require 'crc32'
require 'rc6'
require 'inifile'

require 'spec_helper'

require_relative '../FELConsts'
require_relative '../FELStructs'
require_relative '../FELHelpers'

describe AWSysParaItem do
  it "generates valid structure" do
    para = AWSysParaItem.new
    expect(para.name).to eq("")
    expect(para.filename).to eq("")
    expect(para.verify_filename).to eq("")
    expect(para.encrypt).to eq(1)

    expect(para.to_binary_s.bytesize).to eq(97)
  end

  it "generates structure using AWDownloadItem" do
    dl = AWDownloadItem.new
    dl.name = "system"
    dl.address_low = 131072
    dl.lenlo = 2097152
    dl.filename = "SYSTEM_FEX000000"
    dl.verify_filename = "VSYSTEM_FEX00000"

    para = AWSysParaItem.new(dl)
    expect(para.name).to eq("system")
    expect(para.filename).to eq("SYSTEM_FEX000000")
    expect(para.verify_filename).to eq("VSYSTEM_FEX00000")

  end

  it "generates structure using AWLegacyDownloadItem" do
    dl = AWLegacyDownloadItem.new
    dl.name = "system"
    dl.address_low = 131072
    dl.lenlo = 2097152
    dl.filename = "SYSTEM_FEX000000"
    dl.verify_filename = "VSYSTEM_FEX00000"

    para = AWSysParaItem.new(dl)
    expect(para.name).to eq("system")
    expect(para.filename).to eq("SYSTEM_FEX000000")
    expect(para.verify_filename).to eq("VSYSTEM_FEX00000")
  end

  it "generates valid structure from sys_config.fex" do
    sys_config = File.read("./spec/assets/sys_config.sample")
    valid_parts = File.read("./spec/assets/sys_para.sample", 6*97, 0xA8C) # 6 items
    parts = BinData::Array.new(:type => :aw_sys_para_item, :initial_length => 6)

    cfg_ini = IniFile.new( :content => sys_config, :encoding => "UTF-8")
    6.times do |n|
      parts[n] = AWSysParaItem.new(
      {
        :name => cfg_ini["download#{n}"]["part_name"],
        :filename => cfg_ini["download#{n}"]["pkt_name"],
        :encrypt => cfg_ini["download#{n}"]["encrypt"],
        :verify_filename => cfg_ini["download#{n}"]["verify_file"],
      })
    end

    expect(parts.to_binary_s).to eq(valid_parts)
  end

end

describe AWSysParaPart do
  it "generates valid structure" do
    para = AWSysParaPart.new
    expect(para.address_low).to eq(0)
    expect(para.address_high).to eq(0)
    expect(para.classname).to eq("DISK")
    expect(para.name).to eq("")
    expect(para.user_type).to eq(0)
    expect(para.ro).to eq(0)
    expect(para.reserved).to eq(Array.new(24,0))
    expect(para.to_binary_s.bytesize).to eq(104)
  end

  it "generates structure using AWSunxiPartition" do
    part = AWSunxiPartition.new
    part.address_low = 0x400
    part.name = "bootloader"
    part.user_type = 0
    part.ro = 0

    para = AWSysParaPart.new(part)
    expect(para.address_low).to eq(0x400)
    expect(para.address_high).to eq(0)
    expect(para.name).to eq("bootloader")
    expect(para.user_type).to eq(0)
    expect(para.ro).to eq(0)
  end

  it "generates structure using AWSunxiLegacyPartition" do
    part = AWSunxiLegacyPartition.new
    part.address_low = 0x400
    part.name = "bootloader"
    part.user_type = 0
    part.ro = 0

    para = AWSysParaPart.new(part)
    expect(para.address_low).to eq(0x400)
    expect(para.address_high).to eq(0)
    expect(para.name).to eq("bootloader")
    expect(para.user_type).to eq(0)
    expect(para.ro).to eq(0)
  end

  it "generates valid structure from sys_config.fex" do
    sys_config = File.read("./spec/assets/sys_config.sample")
    valid_parts = File.read("./spec/assets/sys_para.sample", 9*104, 0x4D8) # 9 partitions
    parts = BinData::Array.new(:type => :aw_sys_para_part, :initial_length => 9)

    cfg_ini = IniFile.new( :content => sys_config, :encoding => "UTF-8")
    9.times do |n|
      parts[n] = AWSysParaPart.new(
      {
        :address_high => cfg_ini["partition#{n}"]["size_hi"],
        :address_low => cfg_ini["partition#{n}"]["size_lo"],
        :classname => cfg_ini["partition#{n}"]["class_name"],
        :name => cfg_ini["partition#{n}"]["name"],
        :user_type => cfg_ini["partition#{n}"]["user_type"],
        :ro => cfg_ini["partition#{n}"]["ro"]
      })
    end

    expect(parts.to_binary_s).to eq(valid_parts)
  end

end

describe AWSysPara do
  it "generates valid structure" do
    sys = AWSysPara.new
    sys.part_num = 9
    sys.dl_num = 6
    expect(sys.to_binary_s.bytesize).to eq(5496)
  end

  it "creates structure using sys_config.fex, sys_config1.fex" do
    # load assets
    valid_para = File.read("./spec/assets/sys_para.sample")
    sys_config = File.read("./spec/assets/sys_config.sample")
    sys_config << File.read("./spec/assets/sys_config1.sample")

    expect(valid_para.bytesize).to eq(5496)
    sys = AWSysPara.new
    sys.dram = FELHelpers.create_dram_config(sys_config, true)
    cfg_ini = IniFile.new( :content => sys_config, :encoding => "UTF-8")
    sys.part_num = cfg_ini[:part_num]["num"]
    sys.part_num.times do |n|
      sys.part_items[n] = AWSysParaPart.new(
      {
        :address_high => cfg_ini["partition#{n}"]["size_hi"],
        :address_low => cfg_ini["partition#{n}"]["size_lo"],
        :classname => cfg_ini["partition#{n}"]["class_name"],
        :name => cfg_ini["partition#{n}"]["name"],
        :user_type => cfg_ini["partition#{n}"]["user_type"],
        :ro => cfg_ini["partition#{n}"]["ro"]
      })
    end
    sys.dl_num = cfg_ini[:down_num]["down_num"]
    sys.dl_num.times do |n|
      sys.dl_items[n] = AWSysParaItem.new(
      {
        :name => cfg_ini["download#{n}"]["part_name"],
        :filename => cfg_ini["download#{n}"]["pkt_name"],
        :encrypt => cfg_ini["download#{n}"]["encrypt"],
        :verify_filename => cfg_ini["download#{n}"]["verify_file"],
      })
    end

    # expect we created the same struct as binary one
    expect(sys.to_binary_s.bytesize).to eq(5496)
    expect(sys.to_binary_s).to eq(valid_para.b)
  end
end

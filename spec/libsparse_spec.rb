require 'spec_helper'
require 'crc32'

require_relative '../libsparse'

describe SparseImage do
  describe '#new' do
    it 'parses a sparse file #1' do
      File.open("./spec/assets/sparse1.sample") do |f|
        image = SparseImage.new(f)
        expect(image.get_final_size).to eq(512*1024*1024)
        expect(image.count_chunks).to eq(22)
      end
    end


  end

  describe '::is_valid?' do
    it 'validates file #1 as correct' do
      File.open("./spec/assets/sparse1.sample") do |f|
        expect(SparseImage.is_valid?(f.read(64))).to be(true)
      end
    end

    it 'validates random data as incorrect' do
      sample = (0...64).map{65.+(rand(25)).chr}.join
      expect(SparseImage.is_valid?(sample)).to be(false)
    end

    it 'validates random data with short size as incorrect' do
      sample = (0...2).map{65.+(rand(25)).chr}.join
      expect(SparseImage.is_valid?(sample)).to be(false)
    end

  end

  describe '#each_chunk' do
    it 'decompresses correctly a sparse file #1' do
      File.open("./spec/assets/sparse1.sample", "rb") do |f|
        image = SparseImage.new(f)
        data = String.new
        image.each_chunk do |chunk|
          data << chunk
        end
        expect(Crc32.calculate(data, data.length, 0)).to eq(0xC7B4BA44)
      end
    end

  end

end

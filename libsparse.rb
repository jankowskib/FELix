#   libsparse.rb
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

require 'bindata'

# Sparse file exception filter class
class SparseError < StandardError
end

#Sparse image chunk types
ChunkType = {
  :raw                            => 0xcac1,
  :fill                           => 0xcac2,
  :dont_care                      => 0xcac3,
  :crc32                          => 0xcac4
}

# Android sparse ext4 image header
# As stated in (https://github.com/android/platform_system_core/blob/master/libsparse/sparse_format.h)
class SparseImageHeader < BinData::Record
  endian    :little
  uint32    :magic, :asserted_value => 0xed26ff3a
  # major_version (0x1) - reject images with higher major versions
  uint16    :major_version, :assert => lambda { value <= 1 }
  uint16    :minor_version    # (0x0) - allow images with higer minor versions
  # 28 bytes for first revision of the file format
  uint16    :file_hdr_sz, :asserted_value => 28
  # 12 bytes for first revision of the file format
  uint16    :chunk_hdr_sz, :asserted_value => 12
  # block size in bytes, must be a multiple of 4 (4096)
  uint32    :blk_sz, :assert => lambda { value % 4 == 0}
  uint32    :total_blks       # total blocks in the non-sparse output image
  uint32    :total_chunks     # total chunks in the sparse input image
  uint32    :image_checksum   # CRC32 checksum of the original data, counting "don't care"
  #   as 0. Standard 802.3 polynomial, use a Public Domain
  #   table implementation
end

# Android sparse ext4 image chunk
class SparseImageChunk < BinData::Record
  endian    :little
  # 0xCAC1 -> :raw 0xCAC2 -> :fill 0xCAC3 -> :dont_care
  uint16    :chunk_type, :assert => lambda { ChunkType.has_value? value }
  uint16    :reserved
  uint32    :chunk_sz        # in blocks in output image
  uint32    :total_sz        # in bytes of chunk input file including chunk header and data
end

# Main class
class SparseImage

  attr_reader :chunks

  # Check sparse image validity
  # @param data [IO] image handle
  # @param offset [Integer] file offset
  # @raise [SparseError] if fail
  def initialize(data, offset = 0)
    @file = data
    if !(@file.class <= IO) && !@file.instance_of?(StringIO)
      raise SparseError, "Argument must be (sub)class of IO"
    end
    @chunks = []
    @offset = offset
    @file.seek(@offset, IO::SEEK_SET)
    @header = SparseImageHeader.read(@file)
    @header.total_chunks.times do
      chunk = SparseImageChunk.read(@file)
      @chunks << chunk
      @file.seek(chunk.total_sz - @header.chunk_hdr_sz, IO::SEEK_CUR)
    end
  rescue BinData::ValidityError => e
    raise SparseError, "Not a sparse file (#{e})"
  rescue => e
    raise SparseError, "Initialize error (#{e})"
  end

  # Check if given data is a sparse file (it checks only validity of header
  # contrary to #initialize)
  # @param data [String] binary data
  # @return [TrueClass, FalseClass] true if header is valid
  def self.is_valid?(data)
    return false if data.length < 32 # stop if data is less than header size
    @header = SparseImageHeader.read(data)
    true
  rescue BinData::ValidityError
    false
  end

  # Dump decompressed image
  # @param filename [String] output image path
  def dump(filename)
    out = File.open(filename, "wb")
    each_chunk do |chunk|
        out << chunk
    end
  ensure
    out.close
  end

  # Read chunks and yield data
  # @yieldparam [String] binary data of chunk
  # @yieldparam [Symbol<ChunkType>] type of chunk
  def each_chunk
    @file.seek(@offset, IO::SEEK_SET)
    @file.seek(@header.file_hdr_sz, IO::SEEK_CUR)
    @chunks.each do |c|
      @file.seek(@header.chunk_hdr_sz, IO::SEEK_CUR)
      data = ""
      case c.chunk_type
      when ChunkType[:raw]
        data << @file.read(c.total_sz - @header.chunk_hdr_sz)
      when ChunkType[:fill]
        num = @file.read(4)
        data << num * ((@header.blk_sz / 4) * c.chunk_sz)
      when ChunkType[:crc32]
        num = @file.read(4)
      when ChunkType[:dont_care]
        data << "\0" * (c.chunk_sz * @header.blk_sz)
      end
      yield data, ChunkType.invert[c.chunk_type]
    end
  end

  def [](i)
    raise SparseError, "Chunk not found" unless @chunks[i]
    @file.seek(@offset, IO::SEEK_SET)
    @file.seek(@header.file_hdr_sz, IO::SEEK_CUR)
    toseek = 0
    data = ""
    @chunks.each_with_index do |c, idx|
      skip = false
      if i > idx
          toseek += c.total_sz
          next
      end
      @file.seek(toseek + @header.chunk_hdr_sz, IO::SEEK_CUR)
      case c.chunk_type
      when ChunkType[:raw]
        data << @file.read(c.total_sz - @header.chunk_hdr_sz)
      when ChunkType[:fill]
        num = @file.read(4)
        data << num * ((@header.blk_sz / 4) * c.chunk_sz)
      when ChunkType[:crc32]
        num = @file.read(4)
      when ChunkType[:dont_care]
        data << "\0" * (c.chunk_sz * @header.blk_sz)
      end
      return data
    end
  end

  # Get size of unsparsed image (bytes)
  def get_final_size
    @header.total_blks * @header.blk_sz
  end

  # Get number of chunks
  def count_chunks
    @header.total_chunks
  end

end

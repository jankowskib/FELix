FELix
==================

FELix is a multiplatform tool for Allwinner processors handling FEL and FES
protocol written in Ruby

* Uses libusb1.0 / ruby 2.0+
* More powerful than fel tool from sunxi-tools
* Easy to improve

Features
------------------

* Write / read memory
* Execute the code at address
* Flash LiveSuit image (at this moment only newer image are supported)
* Extract data from LiveSuit image
* Format the device NAND / Write new MBR
* Enable NAND
* Dump/flash single partition
* Display the device info
* Reboot the device


Installation
------------------

1. Install ruby 2.0+ (you can use ruby-installer on Windows)
2. Install bundler
       $ gem install bundler
3. Run bundler in application directory
       $ bundle
4. Install libusb (Linux only)
       $ sudo apt-get install libusb1.0.0-dev
5. Install usb filter (Windows only) on your USB driver. Use [Zadig](http://zadig.akeo.ie/).


Usage
------------------

See `(ruby) felix --help` for available commands


Howtos
------------------

* Dump/flash single partition
  1. Get firmware image containing u-boot.fex and fes1.fex files
  2. Boot to FES
         $ felix --tofes <firmware.img>
  3. Enable NAND
         $ felix --nand on
  4. Flash or dump partition
         $ felix --write boot.img --item boot
         $ felix --read boot.img --item boot


Issues
------------------

As I have limited access to Allwinner devices, I encourage you to report issues
you encounter in Issues section. As far I tested the tool on A23, A31 and A31s.


Todo
------------------

There's a lot of things to do. The most important are:

* Support for legacy image format (partially done)
* ~~Separate command for reading/writing NAND partitions~~. **Done**
* Improving speed of libsparse / rc6 algorithm
* Partitioning support without sunxi_mbr

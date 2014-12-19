FELix
==================

FELix is a multiplatform tool for Allwinner processors handling FEL and FES protocol written in Ruby

* Uses libusb1.0
* More powerful than fel tool from sunxi-tools


Features
------------------

* Write / read data to memory
* Execute code at address
* Flash LiveSuit images (at this moment only newer image are supported)
* Format device NAND / Write new MBR
* Enable NAND, so you can read NAND from device
* Display device info
* Reboot device


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

See (ruby) felix --help for available commands

Issues
------------------

As I have limited access to Allwinner devices, I encourage you to report issues you encounter in Issues section

Todo
------------------

There's a lot thing to do. The most important things are:

* Support for legacy image format (parially done)
* Separate command for reading/writing NAND partitions
* Improving speed of libsparse
* Partitioning support without sunxi_mbr

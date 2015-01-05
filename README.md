FELix
==================

FELix is a multiplatform tool for Allwinner processors handling FEL and FES
protocol written in Ruby

* Uses libusb1.0 / ruby 2.0
* More powerful than fel tool from sunxi-tools

Features
------------------

* Write / read memory
* Execute the code at address
* Flash LiveSuit image (at this moment only newer image are supported)
* Extract single item from LiveSuit image
* Format the device NAND / Write new MBR
* Enable NAND
* Dump/flash single partition
* Display the device info
* Reboot the device


Installation
------------------

1. Install ruby 2.0 (you can use ruby-installer on Windows)

        $ sudo apt-get install ruby2.0 ruby2.0-dev
        $ sudo ln -sf /usr/bin/ruby2.0 /usr/bin/ruby
        $ sudo ln -sf /usr/bin/gem2.0 /usr/bin/gem

2. Install bundler

        $ gem install bundler

3. Install libraries (Linux only)

        $ sudo apt-get install libusb-1.0.0-dev libffi-dev libssl-dev

4. Run bundler in application directory

        $ bundle

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

- [ ] Support for legacy image format (partially done)
- [x] Separate command for reading/writing NAND partitions
- [ ] Improve speed of libsparse / rc6 algorithm
- [ ] Partitioning support without sunxi_mbr
- [ ] Handle every available FEL/FES command

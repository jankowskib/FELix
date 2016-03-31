FELix
==================

FELix is a multiplatform tool for Allwinner processors handling FEL and FES
protocol written in Ruby

* Uses libusb1.0 / ruby 2.0+
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
* Boot device using given u-boot

Installation
------------------

1. Install ruby 2.0+ (you can use ruby-installer on Windows)

        $ sudo apt-get install ruby2.0 ruby2.0-dev
        $ sudo ln -sf /usr/bin/ruby2.0 /usr/bin/ruby
        $ sudo ln -sf /usr/bin/gem2.0 /usr/bin/gem

2. Install bundler

        $ gem install bundler

3. Install libraries (Linux only)

        $ sudo apt-get install libusb-1.0.0-dev libffi-dev

4. Run bundler in application directory (You may need to edit Gemfile to match your ruby version)

        $ bundle

5. Switch to FEL mode (`adb reboot efex`) and install a usb filter (Windows only)
over the default USB driver. Use [Zadig](http://zadig.akeo.ie/).


Usage
------------------

See `(ruby) felix --help` for available commands


Howtos
------------------

* Dump/flash single partition

  1. Boot to FES

          $ felix --tofes <firmware.img>

  2. Enable NAND

          $ felix --nand on

  3. Flash or dump partition

          $ felix --write boot.img --item boot
          $ felix --read boot.img --item boot

  4. Disable NAND

          $ felix --nand off


* Write new `boot0`/`boot1` (**Warning**: this may brick your device if you write incorrect file)

  1. Boot to FES

          $ felix --tofes <firmware.img>

  2. Write new boot0 using fes context and boot0 tag

          $ felix --write boot0_nand.fex -c fes -t boot0 -a 0 (for boot1 use boot1 or uboot tag)

  3. Optionally reboot device

          $ felix --reboot


Issues
------------------

As I have limited access to Allwinner devices, I encourage you to report issues
you encounter in Issues section. As far I tested the tool on A13, A23, A31, A31s and A83.


Todo
------------------

There's a lot of things to do. The most important are:

- [ ] Support for legacy image format (partially done)
  - [x] Boot to FES
  - [ ] Flash legacy image
  - [x] Extract legacy image
- [x] Validation of files before flash
- [ ] Improve error handling (may be troublesome)
- [x] Separate command for reading/writing NAND partitions
- [x] Improve speed of libsparse / rc6 algorithm
- [ ] Partitioning support without sunxi_mbr
- [ ] Handle every available FEL/FES command
- [ ] Some kind of GUI

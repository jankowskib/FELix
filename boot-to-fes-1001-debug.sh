#!/usr/bin/env bash
./FELix.rb --write ./1001/fes1.fex -a 0x2000
./FELix.rb --run -a 0x2000
./FELix.rb --write ./1001/u-boot-to-fes-debug.fex -a 0x4a000000
./FELix.rb --run -a 0x4a000000
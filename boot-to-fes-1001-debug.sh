#!/usr/bin/env bash
./felix --write ./1001/fes1.fex -a 0x2000 || exit
./felix --run -a 0x2000 || exit
./felix --write ./1001/u-boot-to-fes-debug.fex -a 0x4a000000 || exit
./felix --run -a 0x4a000000

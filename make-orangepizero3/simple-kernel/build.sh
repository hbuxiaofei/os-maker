#!/usr/bin/env bash

PATH=$PATH:/usr/local/bin/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin

export PATH

make clean

make uImage

#!/bin/sh

# in dataset base dir
# warm up the backlinks.txt cache and count these files and their sizes

 C=0; A=0; du -ks .hlinx/*/*/backlinks.txt | ( while read S N; do C=$(($C+1)); A=$(($A+$S)); cat "$N" > /dev/null 2>&1 & done; echo "$C files, $A kb total" )


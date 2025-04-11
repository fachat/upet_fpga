#!/bin/bash


. /opt/Xilinx/14.7/ISE_DS/settings64.sh

for i in ultracpu21a ultipet12a micropet30b micropet31a; do

	if test $i/*.bit -nt $i.bin ; then 
		echo "make it"
		promgen -spi -p bin -w -u 0 $i/*.bit -o $i.bin
	fi;
done;


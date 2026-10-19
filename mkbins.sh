#!/bin/bash


. /opt/Xilinx/14.7/ISE_DS/settings64.sh

for i in ultracpu14a ultracpu20a ultracpu21a \
	ultipet12a ultipet13a ultipet13ahdmi \
	micropet30b micropet31a; do

	echo "DIR: $i"
	ls $i/*.bit 

	if test $i/*.bit -nt $i.bin ; then 
		echo "make it"
		promgen -spi -p bin -w -u 0 $i/*.bit -o $i.bin
	fi;
done;


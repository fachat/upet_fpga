#!/bin/sh

. /opt/Xilinx/14.7/ISE_DS/settings64.sh

for i in *.tcl; do 

	# rebuild the .bit file
	xtclsh $i run_process

	# rebuild the .bin file
	dir=`basename $i .tcl`

	echo "DIR: $dir"
	ls $dir/*.bit 

	if test $dir/*.bit -nt $dir.bin ; then 
		echo "make it"
		promgen -spi -p bin -w -u 0 $dir/*.bit -o $dir.bin
	fi;
done;


all: sprite16_demo


sprite16_demo: sprite16_demo.bas
	cat $< | tr "[A-Z]" "[a-z]" | petcat -w40 > $@

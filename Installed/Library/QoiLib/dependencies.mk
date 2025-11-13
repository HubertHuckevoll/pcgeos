qoiexp.obj \
qoiexp.eobj: geos.h heap.h vm.h lmem.h file.h hugearr.h Ansi/string.h \
                graphics.h fontID.h font.h color.h extgraph.h gstring.h \
                qoilib.h
qoiimp.obj \
qoiimp.eobj: geos.h heap.h vm.h lmem.h file.h hugearr.h Ansi/string.h \
                graphics.h fontID.h font.h color.h extgraph.h gstring.h \
                qoilib.h

qoilibEC.geo qoilib.geo : geos.ldf ansic.ldf extgraph.ldf 
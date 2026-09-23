webpapi.obj \
webpapi.eobj: webpint.h geos.h file.h graphics.h fontID.h font.h color.h \
                heap.h lmem.h hugearr.h vm.h Ansi/string.h webplib.h
webpriff.obj \
webpriff.eobj: webpint.h geos.h file.h graphics.h fontID.h font.h color.h \
                heap.h lmem.h hugearr.h vm.h Ansi/string.h webplib.h
webpbit.obj \
webpbit.eobj: webpint.h geos.h file.h graphics.h fontID.h font.h color.h \
                heap.h lmem.h hugearr.h vm.h Ansi/string.h webplib.h
webpdsp.obj \
webpdsp.eobj: webpint.h geos.h file.h graphics.h fontID.h font.h color.h \
                heap.h lmem.h hugearr.h vm.h Ansi/string.h webplib.h
webpvp8.obj \
webpvp8.eobj: webpint.h geos.h file.h graphics.h fontID.h font.h color.h \
                heap.h lmem.h hugearr.h vm.h Ansi/string.h webplib.h \
                webpcore.inc

webplibEC.geo webplib.geo : geos.ldf ansic.ldf 
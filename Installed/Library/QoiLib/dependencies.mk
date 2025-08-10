qoiexp.obj \
qoiexp.eobj: extgraph.goh Objects/winC.goh Objects/metaC.goh object.goh \
                Objects/inputC.goh Objects/uiInputC.goh Objects/visC.goh
qoiexp.obj \
qoiexp.eobj: geos.h heap.h vm.h lmem.h file.h hugearr.h Ansi/string.h \
                graphics.h fontID.h font.h color.h gstring.h chunkarr.h \
                object.h geode.h Objects/helpCC.h input.h char.h hwr.h \
                win.h
qoiimp.obj \
qoiimp.eobj: extgraph.goh Objects/winC.goh Objects/metaC.goh object.goh \
                Objects/inputC.goh Objects/uiInputC.goh Objects/visC.goh
qoiimp.obj \
qoiimp.eobj: geos.h heap.h vm.h lmem.h file.h hugearr.h Ansi/string.h \
                graphics.h fontID.h font.h color.h gstring.h chunkarr.h \
                object.h geode.h Objects/helpCC.h input.h char.h hwr.h \
                win.h

qoilibEC.geo qoilib.geo : geos.ldf ansic.ldf extgraph.ldf 
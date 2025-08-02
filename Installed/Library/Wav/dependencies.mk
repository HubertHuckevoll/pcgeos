wavManager.obj \
wavManager.eobj: geos.def ec.def library.def lmem.def vm.def system.def \
                localize.def sllang.def resource.def geode.def heap.def \
                initfile.def Internal/strDrInt.def Internal/semInt.def \
                Internal/streamDr.def driver.def file.def timer.def \
                thread.def bsnwav.def sound.def Internal/soundFmt.def \
                wav.def wavConstants.def wavMacros.def wav.asm adpcm.asm

wavEC.geo wav.geo : geos.ldf sound.ldf bsnwav.ldf 
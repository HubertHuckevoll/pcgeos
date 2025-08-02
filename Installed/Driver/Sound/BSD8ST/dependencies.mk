manager.obj \
manager.eobj: geos.def file.def geode.def dirk.def dirksnd.def \
                resource.def ec.def driver.def lmem.def heap.def \
                system.def localize.def sllang.def timer.def initfile.def \
                char.def Internal/interrup.def bsconst.def bserror.def \
                bstimer.asm sound.def Internal/soundFmt.def \
                Internal/semInt.def Internal/DMADrv.def \
                Internal/strDrInt.def Internal/streamDr.def \
                Internal/soundDrv.def bserror.asm bsregs.asm bsinit.asm \
                bsdelay.asm bsstrate.asm bsint.asm bsvoice.asm bsdac.asm \
                bsstream.asm bswav.asm bsmixer.asm mixlib.def \
                bsrecord.asm bsnwav.asm

bsd8stEC.geo bsd8st.geo : geos.ldf stream.ldf 
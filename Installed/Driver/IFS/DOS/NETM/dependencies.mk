netmManager.obj \
netmManager.eobj: geos.def heap.def geode.def resource.def ec.def lmem.def \
                system.def localize.def sllang.def drive.def disk.def \
                file.def driver.def timedate.def sem.def timer.def \
                initfile.def Internal/semInt.def Internal/interrup.def \
                Internal/dos.def fileEnum.def Internal/fileInt.def \
                Internal/driveInt.def Internal/diskInt.def \
                Internal/fsd.def Internal/log.def Internal/heapInt.def \
                sysstats.def Internal/geodeStr.def Internal/fileStr.def \
                Internal/fsDriver.def Internal/dosFSDr.def \
                netmConstant.def netmStrings.asm netmVariable.def \
                netmEntry.asm netmDisk.asm netmInitExit.asm \
                netmSecondary.asm netmUtils.asm netmHooks.asm

netmEC.geo netm.geo : geos.ldf 
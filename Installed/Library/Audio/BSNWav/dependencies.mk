MP3Dec.obj \
MP3Dec.eobj: MP3Dec/mp3decManager.asm \
                stdapp.def geos.def geode.def resource.def ec.def lmem.def \
                object.def graphics.def fontID.def font.def color.def \
                gstring.def text.def char.def heap.def ui.def file.def \
                vm.def win.def input.def hwr.def localize.def sllang.def \
                Objects/processC.def Objects/metaC.def chunkarr.def \
                geoworks.def gcnlist.def timedate.def \
                Objects/Text/tCommon.def stylesh.def iacp.def \
                Objects/uiInputC.def Objects/visC.def Objects/vCompC.def \
                Objects/vCntC.def Internal/vUtils.def Objects/genC.def \
                disk.def drive.def uDialog.def Objects/gInterC.def \
                token.def Objects/clipbrd.def Objects/gSysC.def \
                Objects/gProcC.def alb.def Objects/gFieldC.def \
                Objects/gScreenC.def Objects/gFSelC.def \
                Objects/gViewC.def Objects/gContC.def Objects/gCtrlC.def \
                Objects/gDocC.def Objects/gDocCtrl.def \
                Objects/gDocGrpC.def Objects/gEditCC.def \
                Objects/gViewCC.def Objects/gToolCC.def \
                Objects/gPageCC.def Objects/gPenICC.def \
                Objects/gGlyphC.def Objects/gTrigC.def \
                Objects/gBoolGC.def Objects/gItemGC.def \
                Objects/gDListC.def Objects/gItemC.def Objects/gBoolC.def \
                Objects/gDispC.def Objects/gDCtrlC.def Objects/gPrimC.def \
                Objects/gAppC.def Objects/gTextC.def Objects/gGadgetC.def \
                Objects/gValueC.def Objects/gToolGC.def \
                Internal/gUtils.def Objects/helpCC.def Objects/eMenuC.def \
                Objects/emomC.def Objects/emTrigC.def Internal/uProcC.def \
                product.def
Driver.obj \
Driver.eobj: Driver/driverManager.asm \
                geos.def driver.def lmem.def geode.def resource.def \
                library.def ec.def dirk.def dirksnd.def \
                Internal/soundDrv.def bsnwav.def
Runtime.obj \
Runtime.eobj: Runtime/runtimeManager.asm \
                wcc_rtl.asm ansicGeode.def geos.def file.def heap.def \
                ec.def lmem.def library.def geode.def resource.def \
                chunkarr.def localize.def sllang.def ansic.def \
                ansicErrors.def
Memory.obj \
Memory.eobj: Memory/memoryManager.asm \
                memory_asm.asm ansicGeode.def geos.def file.def heap.def \
                ec.def lmem.def library.def geode.def resource.def \
                chunkarr.def localize.def sllang.def ansic.def \
                ansicErrors.def product.def
subcode.obj \
subcode.eobj: stdapp.goh object.goh ui.goh Objects/metaC.goh \
                Objects/inputC.goh Objects/clipbrd.goh \
                Objects/uiInputC.goh iacp.goh Objects/winC.goh \
                Objects/gProcC.goh alb.goh Objects/processC.goh \
                Objects/visC.goh Objects/vCompC.goh Objects/vCntC.goh \
                Objects/gAppC.goh Objects/genC.goh Objects/gInterC.goh \
                Objects/gPrimC.goh Objects/gDispC.goh Objects/gTrigC.goh \
                Objects/gViewC.goh Objects/gTextC.goh Objects/vTextC.goh \
                Objects/gCtrlC.goh gcnlist.goh spool.goh \
                Objects/gFSelC.goh Objects/gGlyphC.goh \
                Objects/gDocCtrl.goh Objects/gDocGrpC.goh \
                Objects/gDocC.goh Objects/gContC.goh Objects/gDCtrlC.goh \
                Objects/gEditCC.goh Objects/gBoolGC.goh \
                Objects/gItemGC.goh Objects/gDListC.goh \
                Objects/gItemC.goh Objects/gBoolC.goh \
                Objects/gGadgetC.goh Objects/gToolCC.goh \
                Objects/gValueC.goh Objects/gToolGC.goh \
                Objects/helpCC.goh bsnwav.goh Main/subcode.goh
subcode.obj \
subcode.eobj: geos.h heap.h geode.h resource.h ec.h object.h lmem.h \
                graphics.h fontID.h font.h color.h gstring.h timer.h vm.h \
                dbase.h localize.h Ansi/ctype.h timedate.h file.h \
                sllang.h system.h geoworks.h chunkarr.h Objects/helpCC.h \
                disk.h drive.h input.h char.h hwr.h win.h uDialog.h \
                Objects/gInterC.h Objects/Text/tCommon.h stylesh.h \
                driver.h thread.h print.h Internal/spoolInt.h serialDr.h \
                parallDr.h hugearr.h fileEnum.h sound.h library.h \
                initfile.h dirksnd.h bsnwav.h
library.obj \
library.eobj: stdapp.goh object.goh ui.goh Objects/metaC.goh \
                Objects/inputC.goh Objects/clipbrd.goh \
                Objects/uiInputC.goh iacp.goh Objects/winC.goh \
                Objects/gProcC.goh alb.goh Objects/processC.goh \
                Objects/visC.goh Objects/vCompC.goh Objects/vCntC.goh \
                Objects/gAppC.goh Objects/genC.goh Objects/gInterC.goh \
                Objects/gPrimC.goh Objects/gDispC.goh Objects/gTrigC.goh \
                Objects/gViewC.goh Objects/gTextC.goh Objects/vTextC.goh \
                Objects/gCtrlC.goh gcnlist.goh spool.goh \
                Objects/gFSelC.goh Objects/gGlyphC.goh \
                Objects/gDocCtrl.goh Objects/gDocGrpC.goh \
                Objects/gDocC.goh Objects/gContC.goh Objects/gDCtrlC.goh \
                Objects/gEditCC.goh Objects/gBoolGC.goh \
                Objects/gItemGC.goh Objects/gDListC.goh \
                Objects/gItemC.goh Objects/gBoolC.goh \
                Objects/gGadgetC.goh Objects/gToolCC.goh \
                Objects/gValueC.goh Objects/gToolGC.goh \
                Objects/helpCC.goh bsnwav.goh Main/subcode.goh
library.obj \
library.eobj: geos.h heap.h geode.h resource.h ec.h object.h lmem.h \
                graphics.h fontID.h font.h color.h gstring.h timer.h vm.h \
                dbase.h localize.h Ansi/ctype.h timedate.h file.h \
                sllang.h system.h geoworks.h chunkarr.h Objects/helpCC.h \
                disk.h drive.h input.h char.h hwr.h win.h uDialog.h \
                Objects/gInterC.h Objects/Text/tCommon.h stylesh.h \
                driver.h thread.h print.h Internal/spoolInt.h serialDr.h \
                parallDr.h hugearr.h fileEnum.h Ansi/string.h library.h \
                initfile.h dirksnd.h bsnwav.h sound.h
pcm.obj \
pcm.eobj: stdapp.goh object.goh ui.goh Objects/metaC.goh \
                Objects/inputC.goh Objects/clipbrd.goh \
                Objects/uiInputC.goh iacp.goh Objects/winC.goh \
                Objects/gProcC.goh alb.goh Objects/processC.goh \
                Objects/visC.goh Objects/vCompC.goh Objects/vCntC.goh \
                Objects/gAppC.goh Objects/genC.goh Objects/gInterC.goh \
                Objects/gPrimC.goh Objects/gDispC.goh Objects/gTrigC.goh \
                Objects/gViewC.goh Objects/gTextC.goh Objects/vTextC.goh \
                Objects/gCtrlC.goh gcnlist.goh spool.goh \
                Objects/gFSelC.goh Objects/gGlyphC.goh \
                Objects/gDocCtrl.goh Objects/gDocGrpC.goh \
                Objects/gDocC.goh Objects/gContC.goh Objects/gDCtrlC.goh \
                Objects/gEditCC.goh Objects/gBoolGC.goh \
                Objects/gItemGC.goh Objects/gDListC.goh \
                Objects/gItemC.goh Objects/gBoolC.goh \
                Objects/gGadgetC.goh Objects/gToolCC.goh \
                Objects/gValueC.goh Objects/gToolGC.goh \
                Objects/helpCC.goh bsnwav.goh Main/subcode.goh
pcm.obj \
pcm.eobj: geos.h heap.h geode.h resource.h ec.h object.h lmem.h \
                graphics.h fontID.h font.h color.h gstring.h timer.h vm.h \
                dbase.h localize.h Ansi/ctype.h timedate.h file.h \
                sllang.h system.h geoworks.h chunkarr.h Objects/helpCC.h \
                disk.h drive.h input.h char.h hwr.h win.h uDialog.h \
                Objects/gInterC.h Objects/Text/tCommon.h stylesh.h \
                driver.h thread.h print.h Internal/spoolInt.h serialDr.h \
                parallDr.h hugearr.h fileEnum.h bsnwav.h sound.h \
                library.h dirksnd.h
wav.obj \
wav.eobj: 
wav.obj \
wav.eobj: bsnwav.h geos.h file.h
mp3reader.obj \
mp3reader.eobj: 
mp3reader.obj \
mp3reader.eobj: MP3Dec/mp3int.h geos.h heap.h ec.h Ansi/string.h \
                MP3Dec/mp3dec.h MP3Dec/core/pvmp3_framedecoder.h \
                MP3Dec/core/pvmp3_dec_defs.h \
                MP3Dec/core/pvmp3_audio_type_defs.h \
                MP3Dec/core/pvmp3decoder_api.h MP3Dec/core/s_mp3bits.h \
                MP3Dec/core/s_tmp3dec_file.h MP3Dec/core/s_tmp3dec_chan.h \
                MP3Dec/core/s_huffcodetab.h bsnwav.h file.h
mp3api.obj \
mp3api.eobj: MP3Dec/mp3int.h geos.h heap.h ec.h Ansi/string.h \
                MP3Dec/mp3dec.h MP3Dec/core/pvmp3_framedecoder.h \
                MP3Dec/core/pvmp3_dec_defs.h \
                MP3Dec/core/pvmp3_audio_type_defs.h \
                MP3Dec/core/pvmp3decoder_api.h MP3Dec/core/s_mp3bits.h \
                MP3Dec/core/s_tmp3dec_file.h MP3Dec/core/s_tmp3dec_chan.h \
                MP3Dec/core/s_huffcodetab.h
mp3frame.obj \
mp3frame.eobj: MP3Dec/core/pvmp3_framedecoder.inc \
                MP3Dec/core/pvmp3_framedecoder.h \
                MP3Dec/core/pvmp3_dec_defs.h \
                MP3Dec/core/pvmp3_audio_type_defs.h geos.h \
                MP3Dec/core/pvmp3decoder_api.h MP3Dec/core/s_mp3bits.h \
                MP3Dec/core/pvmp3_poly_phase_synthesis.h \
                MP3Dec/core/s_tmp3dec_chan.h MP3Dec/core/pvmp3_tables.h \
                MP3Dec/core/pv_mp3_huffman.h MP3Dec/core/s_tmp3dec_file.h \
                MP3Dec/core/s_huffcodetab.h MP3Dec/core/pvmp3_getbits.h \
                MP3Dec/core/pvmp3_imdct_synth.h \
                MP3Dec/core/pvmp3_alias_reduction.h \
                MP3Dec/core/pvmp3_reorder.h \
                MP3Dec/core/pvmp3_dequantize_sample.h \
                MP3Dec/core/pvmp3_stereo_proc.h \
                MP3Dec/core/pvmp3_mpeg2_stereo_proc.h \
                MP3Dec/core/pvmp3_get_side_info.h \
                MP3Dec/core/pvmp3_get_scale_factors.h \
                MP3Dec/core/pvmp3_mpeg2_get_scale_factors.h \
                MP3Dec/core/pvmp3_decode_header.h \
                MP3Dec/core/pvmp3_get_main_data_size.h \
                MP3Dec/core/mp3_mem_funcs.h Ansi/string.h \
                MP3Dec/core/pvmp3_decode_huff_cw.h \
                MP3Dec/core/pvmp3_decode_header.inc \
                MP3Dec/core/pvmp3_crc.h MP3Dec/core/pvmp3_seek_synch.h \
                MP3Dec/core/pvmp3_get_main_data_size.inc \
                MP3Dec/core/pv_mp3dec_fxd_op.h MP3Dec/core/../mp3fxp.h \
                MP3Dec/core/pvmp3_get_side_info.inc \
                MP3Dec/core/pvmp3_get_scale_factors.inc \
                MP3Dec/core/pvmp3_mpeg2_get_scale_data.inc \
                MP3Dec/core/pvmp3_mpeg2_get_scale_data.h \
                MP3Dec/core/pvmp3_mpeg2_get_scale_factors.inc \
                MP3Dec/core/pvmp3_seek_synch.inc \
                MP3Dec/core/pvmp3_crc.inc MP3Dec/core/pvmp3_reorder.inc
mp3fxp.obj \
mp3fxp.eobj: MP3Dec/core/pvmp3_audio_type_defs.h geos.h MP3Dec/mp3fxp.h
mp3huff.obj \
mp3huff.eobj: MP3Dec/core/pvmp3_decode_huff_cw.inc \
                MP3Dec/core/pv_mp3dec_fxd_op.h \
                MP3Dec/core/pvmp3_audio_type_defs.h geos.h \
                MP3Dec/core/../mp3fxp.h MP3Dec/core/pvmp3_tables.h \
                MP3Dec/core/pvmp3_dec_defs.h \
                MP3Dec/core/pvmp3decoder_api.h \
                MP3Dec/core/pv_mp3_huffman.h MP3Dec/core/s_mp3bits.h \
                MP3Dec/core/s_tmp3dec_file.h MP3Dec/core/s_tmp3dec_chan.h \
                MP3Dec/core/s_huffcodetab.h MP3Dec/core/pvmp3_getbits.h \
                MP3Dec/core/pvmp3_decode_huff_cw.h \
                MP3Dec/core/pvmp3_huffman_parsing.inc \
                MP3Dec/core/mp3_mem_funcs.h Ansi/string.h \
                MP3Dec/core/pvmp3_tables.inc
mp3imdct.obj \
mp3imdct.eobj: MP3Dec/core/pvmp3_audio_type_defs.h geos.h \
                MP3Dec/core/pvmp3_normalize.inc \
                MP3Dec/core/pvmp3_normalize.h \
                MP3Dec/core/pvmp3_alias_reduction.inc \
                MP3Dec/core/pvmp3_alias_reduction.h \
                MP3Dec/core/pvmp3_dec_defs.h \
                MP3Dec/core/pvmp3decoder_api.h \
                MP3Dec/core/pv_mp3dec_fxd_op.h MP3Dec/core/../mp3fxp.h
mp3quant.obj \
mp3quant.eobj: MP3Dec/core/pvmp3_dequantize_sample.inc \
                MP3Dec/core/pv_mp3dec_fxd_op.h \
                MP3Dec/core/pvmp3_audio_type_defs.h geos.h \
                MP3Dec/core/../mp3fxp.h MP3Dec/core/pvmp3_dec_defs.h \
                MP3Dec/core/pvmp3decoder_api.h \
                MP3Dec/core/pvmp3_dequantize_sample.h \
                MP3Dec/core/pvmp3_normalize.h MP3Dec/core/mp3_mem_funcs.h \
                Ansi/string.h MP3Dec/core/pvmp3_tables.h \
                MP3Dec/core/pv_mp3_huffman.h MP3Dec/core/s_mp3bits.h \
                MP3Dec/core/s_tmp3dec_file.h MP3Dec/core/s_tmp3dec_chan.h \
                MP3Dec/core/s_huffcodetab.h MP3Dec/core/pvmp3_getbits.h
mp3ster.obj \
mp3ster.eobj: MP3Dec/core/pvmp3_stereo_proc.inc \
                MP3Dec/core/pvmp3_stereo_proc.h \
                MP3Dec/core/pvmp3_dec_defs.h \
                MP3Dec/core/pvmp3_audio_type_defs.h geos.h \
                MP3Dec/core/pvmp3decoder_api.h \
                MP3Dec/core/pv_mp3dec_fxd_op.h MP3Dec/core/../mp3fxp.h \
                MP3Dec/core/pvmp3_tables.h MP3Dec/core/pv_mp3_huffman.h \
                MP3Dec/core/s_mp3bits.h MP3Dec/core/s_tmp3dec_file.h \
                MP3Dec/core/s_tmp3dec_chan.h MP3Dec/core/s_huffcodetab.h \
                MP3Dec/core/pvmp3_getbits.h \
                MP3Dec/core/pvmp3_mpeg2_stereo_proc.inc \
                MP3Dec/core/pvmp3_mpeg2_stereo_proc.h \
                MP3Dec/core/mp3_mem_funcs.h Ansi/string.h
mp3synth.obj \
mp3synth.eobj: MP3Dec/core/pvmp3_poly_phase_synthesis.inc \
                MP3Dec/core/pvmp3_poly_phase_synthesis.h \
                MP3Dec/core/pvmp3_audio_type_defs.h geos.h \
                MP3Dec/core/s_tmp3dec_chan.h MP3Dec/core/pvmp3_dec_defs.h \
                MP3Dec/core/pvmp3decoder_api.h \
                MP3Dec/core/pvmp3_polyphase_filter_window.h \
                MP3Dec/core/pv_mp3dec_fxd_op.h MP3Dec/core/../mp3fxp.h \
                MP3Dec/core/pvmp3_dct_16.h MP3Dec/core/pvmp3_equalizer.h \
                MP3Dec/core/mp3_mem_funcs.h Ansi/string.h \
                MP3Dec/core/pvmp3_equalizer.inc

bsnwavEC.geo bsnwav.geo : geos.ldf 
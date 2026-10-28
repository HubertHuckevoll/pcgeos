mp3frame.obj \
mp3frame.eobj: core/pvmp3_framedecoder.inc core/pvmp3_framedecoder.h \
                core/pvmp3_dec_defs.h core/pvmp3_audio_type_defs.h geos.h \
                core/pvmp3decoder_api.h core/s_mp3bits.h \
                core/pvmp3_poly_phase_synthesis.h core/s_tmp3dec_chan.h \
                core/pvmp3_tables.h core/pv_mp3_huffman.h \
                core/s_tmp3dec_file.h core/s_huffcodetab.h \
                core/pvmp3_getbits.h resource.h core/pvmp3_imdct_synth.h \
                core/pvmp3_alias_reduction.h core/pvmp3_reorder.h \
                core/pvmp3_dequantize_sample.h core/pvmp3_stereo_proc.h \
                core/pvmp3_mpeg2_stereo_proc.h core/pvmp3_get_side_info.h \
                core/pvmp3_get_scale_factors.h \
                core/pvmp3_mpeg2_get_scale_factors.h \
                core/pvmp3_decode_header.h \
                core/pvmp3_get_main_data_size.h core/mp3_mem_funcs.h \
                Ansi/string.h core/pvmp3_decode_huff_cw.h \
                core/pvmp3_decode_header.inc core/pvmp3_crc.h \
                core/pvmp3_seek_synch.h core/pvmp3_get_main_data_size.inc \
                core/pv_mp3dec_fxd_op.h core/../mp3fxp.h \
                core/pvmp3_get_side_info.inc \
                core/pvmp3_get_scale_factors.inc \
                core/pvmp3_mpeg2_get_scale_data.inc \
                core/pvmp3_mpeg2_get_scale_data.h \
                core/pvmp3_mpeg2_get_scale_factors.inc \
                core/pvmp3_seek_synch.inc core/pvmp3_crc.inc \
                core/pvmp3_reorder.inc
mp3huff.obj \
mp3huff.eobj: core/pvmp3_decode_huff_cw.inc core/pv_mp3dec_fxd_op.h \
                core/pvmp3_audio_type_defs.h geos.h core/../mp3fxp.h \
                core/pvmp3_tables.h core/pvmp3_dec_defs.h \
                core/pvmp3decoder_api.h core/pv_mp3_huffman.h \
                core/s_mp3bits.h core/s_tmp3dec_file.h \
                core/s_tmp3dec_chan.h core/s_huffcodetab.h \
                core/pvmp3_getbits.h resource.h \
                core/pvmp3_decode_huff_cw.h \
                core/pvmp3_huffman_parsing.inc core/mp3_mem_funcs.h \
                Ansi/string.h core/pvmp3_tables.inc
mp3imdct.obj \
mp3imdct.eobj: core/pvmp3_audio_type_defs.h geos.h \
                core/pvmp3_normalize.inc core/pvmp3_normalize.h \
                core/pvmp3_alias_reduction.inc \
                core/pvmp3_alias_reduction.h core/pvmp3_dec_defs.h \
                core/pvmp3decoder_api.h core/pv_mp3dec_fxd_op.h \
                core/../mp3fxp.h
mp3synth.obj \
mp3synth.eobj: core/pvmp3_poly_phase_synthesis.inc \
                core/pvmp3_poly_phase_synthesis.h \
                core/pvmp3_audio_type_defs.h geos.h core/s_tmp3dec_chan.h \
                core/pvmp3_dec_defs.h core/pvmp3decoder_api.h \
                core/pvmp3_polyphase_filter_window.h \
                core/pv_mp3dec_fxd_op.h core/../mp3fxp.h \
                core/pvmp3_dct_16.h core/pvmp3_equalizer.h \
                core/mp3_mem_funcs.h Ansi/string.h \
                core/pvmp3_equalizer.inc
mp3quant.obj \
mp3quant.eobj: core/pvmp3_dequantize_sample.inc core/pv_mp3dec_fxd_op.h \
                core/pvmp3_audio_type_defs.h geos.h core/../mp3fxp.h \
                core/pvmp3_dec_defs.h core/pvmp3decoder_api.h \
                core/pvmp3_dequantize_sample.h core/pvmp3_normalize.h \
                core/mp3_mem_funcs.h Ansi/string.h core/pvmp3_tables.h \
                core/pv_mp3_huffman.h core/s_mp3bits.h \
                core/s_tmp3dec_file.h core/s_tmp3dec_chan.h \
                core/s_huffcodetab.h core/pvmp3_getbits.h resource.h
mp3ster.obj \
mp3ster.eobj: core/pvmp3_stereo_proc.inc core/pvmp3_stereo_proc.h \
                core/pvmp3_dec_defs.h core/pvmp3_audio_type_defs.h geos.h \
                core/pvmp3decoder_api.h core/pv_mp3dec_fxd_op.h \
                core/../mp3fxp.h core/pvmp3_tables.h \
                core/pv_mp3_huffman.h core/s_mp3bits.h \
                core/s_tmp3dec_file.h core/s_tmp3dec_chan.h \
                core/s_huffcodetab.h core/pvmp3_getbits.h resource.h \
                core/pvmp3_mpeg2_stereo_proc.inc \
                core/pvmp3_mpeg2_stereo_proc.h core/mp3_mem_funcs.h \
                Ansi/string.h
mp3api.obj \
mp3api.eobj: mp3int.h geos.h heap.h ec.h Ansi/string.h mp3dec.h \
                core/pvmp3_framedecoder.h core/pvmp3_dec_defs.h \
                core/pvmp3_audio_type_defs.h core/pvmp3decoder_api.h \
                core/s_mp3bits.h core/s_tmp3dec_file.h \
                core/s_tmp3dec_chan.h core/s_huffcodetab.h
mp3fxp.obj \
mp3fxp.eobj: core/pvmp3_audio_type_defs.h geos.h mp3fxp.h
mp3dsp.obj \
mp3dsp.eobj: stdapp.def geos.def geode.def resource.def ec.def lmem.def \
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

mp3decEC.geo mp3dec.geo : geos.ldf ansic.ldf 
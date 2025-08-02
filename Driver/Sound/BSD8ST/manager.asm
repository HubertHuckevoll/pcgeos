COMMENT @********************************************************

	Copyright (c) Dirk Lausecker -- All Rights Reserved

PROJECT:	BestSound driver

DATEI:		Manager.asm

AUTOR:		Dirk Lausecker

REVISION HISTORY:
	Name	Datum		Beschreibung
	----	-----		------------
	DL	08.08.98	Init
        DL	07.10.1999	Ableitung f�r Recording
        DL	22.12.1999	Ableitung f�r NewWave (Umgehung Soundlib)
        DL	16.08.2000	Translation for ND

*****************************************************************@

;-----------------------------------------------------------------------------
;		Include Files
;-----------------------------------------------------------------------------

;
include	geos.def
include	file.def
include	geode.def
include dirk.def

include dirksnd.def

include	resource.def
include	ec.def
include	driver.def
include	heap.def
include	system.def
include	timer.def
include	initfile.def
include	char.def
include	localize.def

include	Internal/interrup.def

include bsconst.def
include	bserror.def
include bstimer.asm

UseLib	  sound.def
UseDriver Internal/DMADrv.def
UseDriver Internal/strDrInt.def

DefDriver Internal/soundDrv.def

;-----------------------------------------------------------------------------
;		Conditional Compile Flags
;-----------------------------------------------------------------------------

; BS_MIXER_ONLY		equ	1	; mixer functions only
; BS_NO_INT		equ	1	; no use of Hardware Interrupt
; BS_OUTPUT_SPEAKER	equ	1	; Speaker output

BS_OUTPUT_DSP		equ	1	; use soundcard

; BS_SWAT_WARNING	equ	1	; Warnings in subfunctions

;-----------------------------------------------------------------------------
;		Source files for driver
;-----------------------------------------------------------------------------
	.ioenable
include bserror.asm		; Error Checking routines and such

include bsregs.asm		; FM register writing routine and n.e.
include bsinit.asm		; set up board for use
include	bsdelay.asm		; micro second busy-wait code
include	bsstrate.asm		; strategy routine and nothing else
include bsint.asm		; interrupt code for DMA

include	bsvoice.asm		; regular driver code
include bsdac.asm		; DAC driver code

include bsstream.asm		; stream stuff for dac

; additional files by Dirk Lausecker
include	bswav.asm		; additional WAV output code
include	bsmixer.asm		; Mixercontrol
include	mixlib.def		; Mixerdefinitions

include bsrecord.asm		; Recording
include	bsnwav.asm		; NewWave-Play


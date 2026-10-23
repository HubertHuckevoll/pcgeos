; Canonical SBCS bitmap font; generated from the existing BSWF reference.
fdata	segment
include geos.def
include graphics.def
include font.def
UseDriver Internal/fontDr.def
		CheckHack <(size PointSizeEntry) eq 10>
		CheckHack <(offset FB_charTable) eq 71>
		CheckHack <(size CharTableEntry) eq 8>
		byte	"BSWF",0,1
		word	EndHead-StartHead
StartHead label byte
		word	FID_BISON	; font ID
		word	0	; maker
		byte	197	; family
		char	"Bison", 15 dup (0)
		word	BitmapStart-StartHead+2
		word	BitmapEnd-StartHead+2
		word	0,0	; no outlines
BitmapStart label byte
		byte	0x00	; style
		WBFixed	<0,9>	; point size
		word	bison_09EndData-bison_09StartData
		dword	offset bison_09StartData

		byte	0x00	; style
		WBFixed	<0,12>	; point size
		word	bison_12EndData-bison_12StartData
		dword	offset bison_12StartData

		byte	0x00	; style
		WBFixed	<0,14>	; point size
		word	bison_14EndData-bison_14StartData
		dword	offset bison_14StartData

		byte	0x00	; style
		WBFixed	<0,13>	; point size
		word	bison_13EndData-bison_13StartData
		dword	offset bison_13StartData

BitmapEnd label byte
EndHead label byte
fdata	ends
fontgroup group fdata, bison_09Seg, bison_12Seg, bison_14Seg, bison_13Seg

include bison_09.def
include bison_12.def
include bison_14.def
include bison_13.def

end

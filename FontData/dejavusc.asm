; Canonical SBCS bitmap font; generated from the existing BSWF reference.
; DejaVu/Bitstream Vera/Arev font terms: see DejaVuSC.txt.
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
		word	FID_DEJAVUSC	; font ID
		word	0	; maker
		byte	129	; family
		char	"DejaVuSC", 12 dup (0)
		word	BitmapStart-StartHead+2
		word	BitmapEnd-StartHead+2
		word	0,0	; no outlines
BitmapStart label byte
		byte	0x00	; style
		WBFixed	<0,10>	; point size
		word	dejavusc_10EndData-dejavusc_10StartData
		dword	offset dejavusc_10StartData

BitmapEnd label byte
EndHead label byte
fdata	ends
fontgroup group fdata, dejavusc_10Seg

include dejavusc_10.def

end

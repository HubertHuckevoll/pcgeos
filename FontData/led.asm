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
		word	FID_LED	; font ID
		word	0	; maker
		byte	131	; family
		char	"LED", 17 dup (0)
		word	BitmapStart-StartHead+2
		word	BitmapEnd-StartHead+2
		word	0,0	; no outlines
BitmapStart label byte
		byte	0x00	; style
		WBFixed	<0,18>	; point size
		word	led_18EndData-led_18StartData
		dword	offset led_18StartData

BitmapEnd label byte
EndHead label byte
fdata	ends
fontgroup group fdata, led_18Seg

include led_18.def

end

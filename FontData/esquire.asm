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
		word	EndHead-StartHead+8 ; original Esquire includes the prefix
StartHead label byte
		word	FID_ESQUIRE	; font ID
		word	0	; maker
		byte	129	; family
		char	"Esquire", 13 dup (0)
		word	BitmapStart-StartHead+2
		word	BitmapEnd-StartHead+2
		word	0,0	; no outlines
BitmapStart label byte
		byte	0x00	; style
		WBFixed	<0,10>	; point size
		word	esquire_10EndData-esquire_10StartData
		dword	offset esquire_10StartData

		byte	0x00	; style
		WBFixed	<0,12>	; point size
		word	esquire_12EndData-esquire_12StartData
		dword	offset esquire_12StartData

		byte	0x00	; style
		WBFixed	<0,14>	; point size
		word	esquire_14EndData-esquire_14StartData
		dword	offset esquire_14StartData

		byte	0x00	; style
		WBFixed	<0,18>	; point size
		word	esquire_18EndData-esquire_18StartData
		dword	offset esquire_18StartData

		byte	0x00	; style
		WBFixed	<0,9>	; point size
		word	esquire_09EndData-esquire_09StartData
		dword	offset esquire_09StartData

		byte	0x20	; style
		WBFixed	<0,12>	; point size
		word	esquire_bold_12EndData-esquire_bold_12StartData
		dword	offset esquire_bold_12StartData

		byte	0x20	; style
		WBFixed	<0,10>	; point size
		word	esquire_bold_10EndData-esquire_bold_10StartData
		dword	offset esquire_bold_10StartData

		byte	0x20	; style
		WBFixed	<0,14>	; point size
		word	esquire_bold_14EndData-esquire_bold_14StartData
		dword	offset esquire_bold_14StartData

		byte	0x20	; style
		WBFixed	<0,18>	; point size
		word	esquire_bold_18EndData-esquire_bold_18StartData
		dword	offset esquire_bold_18StartData

		byte	0x20	; style
		WBFixed	<0,9>	; point size
		word	esquire_bold_09EndData-esquire_bold_09StartData
		dword	offset esquire_bold_09StartData

BitmapEnd label byte
EndHead label byte
fdata	ends
fontgroup group fdata, esquire_10Seg, esquire_12Seg, esquire_14Seg, esquire_18Seg, esquire_09Seg, esquire_bold_12Seg, esquire_bold_10Seg, esquire_bold_14Seg, esquire_bold_18Seg, esquire_bold_09Seg

include esquire_10.def
include esquire_12.def
include esquire_14.def
include esquire_18.def
include esquire_09.def
include esquire_bold_12.def
include esquire_bold_10.def
include esquire_bold_14.def
include esquire_bold_18.def
include esquire_bold_09.def

end

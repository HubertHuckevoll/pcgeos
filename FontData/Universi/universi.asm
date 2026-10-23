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
		word	FID_UNIVERSITY	; font ID
		word	0	; maker
		byte	129	; family
		char	"University", 10 dup (0)
		word	BitmapStart-StartHead+2
		word	BitmapEnd-StartHead+2
		word	0,0	; no outlines
BitmapStart label byte
		byte	0x00	; style
		WBFixed	<0,10>	; point size
		word	universi_10EndData-universi_10StartData
		dword	offset universi_10StartData

		byte	0x00	; style
		WBFixed	<0,12>	; point size
		word	universi_12EndData-universi_12StartData
		dword	offset universi_12StartData

		byte	0x00	; style
		WBFixed	<0,14>	; point size
		word	universi_14EndData-universi_14StartData
		dword	offset universi_14StartData

		byte	0x00	; style
		WBFixed	<0,18>	; point size
		word	universi_18EndData-universi_18StartData
		dword	offset universi_18StartData

		byte	0x00	; style
		WBFixed	<0,24>	; point size
		word	universi_24EndData-universi_24StartData
		dword	offset universi_24StartData

		byte	0x00	; style
		WBFixed	<0,9>	; point size
		word	universi_09EndData-universi_09StartData
		dword	offset universi_09StartData

BitmapEnd label byte
EndHead label byte
fdata	ends
fontgroup group fdata, universi_10Seg, universi_12Seg, universi_14Seg, universi_18Seg, universi_24Seg, universi_09Seg

include universi_10.def
include universi_12.def
include universi_14.def
include universi_18.def
include universi_24.def
include universi_09.def

end

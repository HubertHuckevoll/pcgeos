DriverInfo segment lmem LMEM_TYPE_GENERAL
DefPrinter PD_NATIVE_PDF, "PDF 1.1 (Native, Print to File)", pdfDeviceInfo
DriverExtendedInfoTable <{}, PrintDevice/2, offset deviceStrings, offset deviceInfoTab>
PrintDriverInfo <90, PR_DONT_RESEND, isoSubstitutions, asciiTranslations, PDT_PRINTER, FALSE>
isoSubstitutions chunk.word 0ffffh
asciiTranslations chunk.char ";;", 0
PrinterTables
DriverInfo ends

pdfDeviceInfo segment resource
; File only; copies and page ordering remain the spooler's responsibility.
PrinterInfo <<PT_RASTER, BMF_24BIT>, <IC_NO_IEEE488, CC_NO_CUSTOM, SC_NO_SCSI, RC_NO_RS232C, CC_NO_CENTRONICS, FC_FILE, AC_NO_APPLETALK>, PS_PDL, NULL, NULL, NULL, NULL, offset pdfGraphics, NULL, NULL, NULL, NULL, <0,0,0,0>, <0,0,0,0>, <MF_NO_MANUAL, TF_NO_TRACTOR, ASF_TRAY1>, <OC_NO_COPIES, PS_NORMAL, OD_SIMPLEX, SO_NO_STAPLER, OS_NO_SORTER, OB_NO_OUTPUTBIN>, 32767, NULL, NULL, NULL>
pdfGraphics GraphicsProperties <300, 300, 1, 1, 1, BMF_24BIT, NULL>
pdfDeviceInfo ends

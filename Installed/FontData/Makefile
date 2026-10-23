# Handcrafted bitmap asset build. Do not regenerate with mkmf.
ROOT_DIR := $(ROOT_DIR:S,\\,/,g)
SOURCE = $(ROOT_DIR)/FontData
INCLUDE = $(ROOT_DIR)/Include

#if defined(linux)
ASM ?= $(ROOT_DIR)/bin/esp
LINK ?= $(ROOT_DIR)/bin/glue
MOVE = mv -f
REMOVE = rm -f
#else
ASM ?= $(ROOT_DIR)/bin/esp.exe
LINK ?= $(ROOT_DIR)/bin/glue.exe
MOVE = cmd /c move /Y
REMOVE = cmd /c del /q
#endif
ASMFLAGS ?=
LINKFLAGS ?=

FONTS = Berkeley.fnt Bison.fnt Esquire.fnt LED.fnt Universi.fnt DejaVuSC.fnt
OBJECTS = $(FONTS:S|.fnt$|.obj|g)

all : $(FONTS)

# Transitive SDK includes verified with esp -M; no generated dependencies.
SDKDEFS = $(INCLUDE)/geos.def $(INCLUDE)/graphics.def $(INCLUDE)/fontID.def \
          $(INCLUDE)/font.def $(INCLUDE)/color.def $(INCLUDE)/Internal/fontDr.def \
          $(INCLUDE)/driver.def $(INCLUDE)/lmem.def $(INCLUDE)/file.def \
          $(INCLUDE)/char.def

Berkeley.obj Berkeley.fnt : $(SOURCE)/Berkeley/berkeley.asm \
    $(SOURCE)/Berkeley/berkeley_09.def $(SOURCE)/Berkeley/berkeley_10.def \
    $(SOURCE)/Berkeley/berkeley_12.def $(SOURCE)/Berkeley/berkeley_14.def $(SOURCE)/Berkeley/berkeley_18.def
Bison.obj Bison.fnt : $(SOURCE)/Bison/bison.asm $(SOURCE)/Bison/bison_09.def $(SOURCE)/Bison/bison_12.def \
    $(SOURCE)/Bison/bison_14.def $(SOURCE)/Bison/bison_13.def
Esquire.obj Esquire.fnt : $(SOURCE)/Esquire/esquire.asm \
    $(SOURCE)/Esquire/esquire_09.def $(SOURCE)/Esquire/esquire_10.def $(SOURCE)/Esquire/esquire_12.def \
    $(SOURCE)/Esquire/esquire_14.def $(SOURCE)/Esquire/esquire_18.def \
    $(SOURCE)/Esquire/esquire_bold_09.def $(SOURCE)/Esquire/esquire_bold_10.def \
    $(SOURCE)/Esquire/esquire_bold_12.def $(SOURCE)/Esquire/esquire_bold_14.def \
    $(SOURCE)/Esquire/esquire_bold_18.def
LED.obj LED.fnt : $(SOURCE)/LED/led.asm $(SOURCE)/LED/led_18.def
Universi.obj Universi.fnt : $(SOURCE)/Universi/universi.asm $(SOURCE)/Universi/universi_09.def \
    $(SOURCE)/Universi/universi_10.def $(SOURCE)/Universi/universi_12.def \
    $(SOURCE)/Universi/universi_14.def $(SOURCE)/Universi/universi_18.def $(SOURCE)/Universi/universi_24.def
DejaVuSC.obj DejaVuSC.fnt : $(SOURCE)/DejaVuSC/dejavusc.asm $(SOURCE)/DejaVuSC/dejavusc_10.def

# Keep inputs on both stages: this pmake uses whole-second timestamps.
$(OBJECTS) $(FONTS) : $(SDKDEFS) Makefile $(ASM)

$(OBJECTS) :
	"$(ASM)" $(ASMFLAGS) -I"$(.ALLSRC:M*.asm:H)" -I"$(INCLUDE)" -o TMP$(.TARGET) $(.ALLSRC:M*.asm)
	$(MOVE) TMP$(.TARGET) $(.TARGET)

$(FONTS) : $(.TARGET:R).obj $(LINK)
	"$(LINK)" $(LINKFLAGS) -Of -o TMP$(.TARGET) $(.ALLSRC:M*.obj)
	$(MOVE) TMP$(.TARGET) $(.TARGET)

check : all .EXEC
	perl "$(SOURCE)/tests/bitmap-fonts.pl"

clean : .EXEC
	$(REMOVE) $(FONTS) $(OBJECTS) $(OBJECTS:S|.obj$|.sym|g) \
	    $(OBJECTS:S|.obj$|.tcl|g) $(FONTS:S|^|TMP|g) \
	    $(OBJECTS:S|^|TMP|g) $(OBJECTS:S|.obj$|.sym|g:S|^|TMP|g) \
	    $(OBJECTS:S|.obj$|.tcl|g:S|^|TMP|g)

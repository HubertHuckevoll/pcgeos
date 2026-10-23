# Shared handcrafted rules for one bitmap font. Do not regenerate with mkmf.
ROOT_DIR := $(ROOT_DIR:S,\\,/,g)
SOURCE = $(ROOT_DIR)/FontData/$(FONT)
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

all : $(FONT).fnt

# Transitive SDK includes verified with esp -M; no generated dependencies.
SDKDEFS = $(INCLUDE)/geos.def $(INCLUDE)/graphics.def $(INCLUDE)/fontID.def \
          $(INCLUDE)/font.def $(INCLUDE)/color.def $(INCLUDE)/Internal/fontDr.def \
          $(INCLUDE)/driver.def $(INCLUDE)/lmem.def $(INCLUDE)/file.def \
          $(INCLUDE)/char.def

# Keep inputs on both stages: this pmake uses whole-second timestamps.
$(FONT).obj $(FONT).fnt : $(SOURCE)/$(NAME).asm $(SOURCE)/*.def \
    $(SDKDEFS) Makefile ../font.mk $(ASM)

$(FONT).obj :
	"$(ASM)" $(ASMFLAGS) -I"$(SOURCE)" -I"$(INCLUDE)" -o TMP$(.TARGET) $(SOURCE)/$(NAME).asm
	$(MOVE) TMP$(.TARGET) $(.TARGET)

$(FONT).fnt : $(FONT).obj $(LINK)
	"$(LINK)" $(LINKFLAGS) -Of -o TMP$(.TARGET) $(FONT).obj
	$(MOVE) TMP$(.TARGET) $(.TARGET)

clean : .EXEC
	$(REMOVE) $(FONT).fnt $(FONT).obj $(FONT).sym $(FONT).tcl \
	    TMP$(FONT).fnt TMP$(FONT).obj TMP$(FONT).sym TMP$(FONT).tcl

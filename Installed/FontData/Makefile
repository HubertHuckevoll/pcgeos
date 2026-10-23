# Handcrafted bitmap font aggregate. Each subdirectory also builds independently.
ROOT_DIR := $(ROOT_DIR:S,\\,/,g)
FONTS = Berkeley Bison Esquire LED Universi DejaVuSC

all : $(FONTS)

$(FONTS) : .EXEC
#if defined(linux)
	cd "$(.TARGET)" && $(MAKE) all
#else
	cd /d "$(ROOT_DIR)\Installed\FontData\$(.TARGET)" && $(MAKE) all
#endif

# Preserve the original individual-target spelling at the aggregate level.
$(FONTS:S|$|.fnt|g) : $(.TARGET:R)

check : all .EXEC
	perl "$(ROOT_DIR)/FontData/tests/bitmap-fonts.pl"

clean : $(FONTS:S|^|clean-|g)

$(FONTS:S|^|clean-|g) : .EXEC
#if defined(linux)
	cd "$(.TARGET:S|clean-||)" && $(MAKE) clean
#else
	cd /d "$(ROOT_DIR)\Installed\FontData\$(.TARGET:S|clean-||)" && $(MAKE) clean
#endif

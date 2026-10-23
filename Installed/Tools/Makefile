
#if defined(linux)
MK_MAKE = mkdir -p $PARAM ; \
		cd $PARAM ; \
		$(MAKE) -k -I$PARAM
#else
MK_MAKE = mkdir %PARAM% & \
		cd %PARAM% & \
		$(MAKE) -k -I%PARAM%
#endif


BINS = Tools/esp Tools/uicpp Tools/goc Tools/grev Tools/loc Tools/nmkmf Tools/pmake/makedpnd \
		Tools/glue Tools/uic Tools/pmake/findlbdr \
		Tools/geodump Tools/sym2dis Tools/ldf2sls Tools/swat Tools/misc/cvtpcx
LIBS =  Tools/utils Tools/compat Tools/winutil Tools/swat/tcl \
	Tools/swat/ntcurses Tools/swat/curses Tools/swat/termcap

install		: $(LIBS) $(BINS) bitmap-fonts

$(LIBS) : 
#if defined(linux)
	mkdir -p $(ROOT_DIR)/Installed/$(.TARGET) && \
	cd $(ROOT_DIR)/Installed/$(.TARGET) && \
	$(MAKE) -k -I$(ROOT_DIR)/Installed/$(.TARGET) all
#else
	if not exist "$(ROOT_DIR)\Installed\$(.TARGET:S/\//\\/g)" mkdir "$(ROOT_DIR)\Installed\$(.TARGET:S/\//\\/g)"
	cd /d "$(ROOT_DIR)\Installed\$(.TARGET:S/\//\\/g)" && \
	$(MAKE) -k -I$(ROOT_DIR)\Installed\$(.TARGET:S/\//\\/g) all
#endif

$(BINS) : $(LIBS)
#if defined(linux)
	mkdir -p $(ROOT_DIR)/Installed/$(.TARGET) && \
	cd $(ROOT_DIR)/Installed/$(.TARGET) && \
	$(MAKE) -k -I$(ROOT_DIR)/Installed/$(.TARGET) installlinux && \
	$(MAKE) -k -I$(ROOT_DIR)/Installed/$(.TARGET) installwin32
#else
	if not exist "$(ROOT_DIR)\Installed\$(.TARGET:S/\//\\/g)" mkdir "$(ROOT_DIR)\Installed\$(.TARGET:S/\//\\/g)"
	cd /d "$(ROOT_DIR)\Installed\$(.TARGET:S/\//\\/g)" && \
	$(MAKE) -k -I$(ROOT_DIR)\Installed\$(.TARGET:S/\//\\/g) install
#endif

# Fonts need the installed native assembler/linker, after all tools succeed.
bitmap-fonts : $(BINS) .EXEC
#if defined(linux)
	cd "$(ROOT_DIR)/Installed/FontData" && $(MAKE) all
#else
	cd /d "$(ROOT_DIR)\Installed\FontData" && $(MAKE) all
#endif

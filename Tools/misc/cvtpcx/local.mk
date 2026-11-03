# Implemented with ChatGPT Codex, prompted by MeyerK
# LodePNG: https://github.com/lvandeve/lodepng
# Unmodified upstream 7b2893e35891c0c85bee5595caafaf3c2044b409,
# with lodepng.cpp named lodepng.c for the C89 host-tool build.
XCFLAGS += -DLODEPNG_NO_COMPILE_ENCODER -DLODEPNG_NO_COMPILE_DISK \
           -DLODEPNG_NO_COMPILE_ANCILLARY_CHUNKS
linuxOBJS += linux.md/lodepng.o
win32OBJS += win32.md/lodepng.obj

#include <$(SYSMAKEFILE)>

linux.md/cvtpcx.o linux.md/lodepng.o win32.md/cvtpcx.obj win32.md/lodepng.obj: lodepng.h

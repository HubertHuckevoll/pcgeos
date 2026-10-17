/*
 * Pull input for image decoders, independent of downloading and display.
 *
 * The caller supplies encoded image bytes; ImpGraph and its decoder libraries
 * consume them and produce GEOS graphics. For example, BbxBrow owns the download,
 * stream buffer and synchronization. Its ImportGraphicInputCallback adapter
 * supplies bytes when a decoder asks for them, waiting for more download data
 * if necessary. The decoder needs no knowledge of browser download state.
 *
 * ImageImportSource (htmldrv.h) explicitly selects file or stream input.
 * ImageImportUpdates independently selects decoded-image notifications.
 * Streaming works without updates, and file input can report updates.
 * BbxBrow controls these with progressLoading and progressDisplay.
 * Streaming support depends on the decoder.
 */
#ifndef __IMPINPUT_H
#define __IMPINPUT_H

#include <geos.h>

typedef enum {
    IIO_READ,           /* Read bytes; retain the first packet for probing. */
    IIO_PEEK,           /* Copy bytes without advancing the read position. */
    IIO_PRE_READ,       /* Advance a temporary offset, retaining probe bytes. */
    IIO_FLUSH_FIRST,    /* Commit size bytes of the retained first packet,
                        * then reset probe state (used between GIF frames). */
    IIO_RESET           /* Reset probe state to retry the retained prefix;
                        * does not rewind already-consumed stream data. */
} ImageInputOperation;

/*
 * Called synchronously on the importing thread. READ, PEEK and PRE_READ copy
 * at most size bytes into bufferP and return the byte count. For live input,
 * wait for size bytes or producer completion; zero means end of input, not
 * temporarily unavailable data. Do not retain bufferP after returning.
 * FLUSH_FIRST and RESET receive no buffer; their return value is ignored.
 * Opening, filling and closing the producer's buffer belong to the caller.
 */
typedef word _pascal _export proc_ImageInputCallback(void *clientDataP,
    ImageInputOperation operation, void *bufferP, word size);
typedef word _pascal pcfm_ImageInputCallback(void *clientDataP,
    ImageInputOperation operation, void *bufferP, word size, void *pf);

/*
 * The caller owns this descriptor and its opaque clientDataP. Keep both and
 * the callback valid until the import returns; the decoder never frees them.
 * A supplied descriptor requires a callback; an invalid one fails the import
 * instead of falling back to file input.
 */
typedef struct {
    void _pascal *callback;
    void *clientDataP;
} ImageInput;

#endif

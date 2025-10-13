#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define FEED_BUF_SIZE  4096  /* small is fine; bigger reduces I/O calls */

int decode_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) return -1;

    mp3dec_t dec;
    mp3dec_init(&dec);

    uint8_t  feed[FEED_BUF_SIZE];
    int      feed_len = 0;                 /* bytes currently in feed[] */
    int16_t  pcm[MINIMP3_MAX_SAMPLES_PER_FRAME]; /* 1152*2 int16 slots */
    mp3dec_frame_info_t info;

    for (;;)
    {
        /* If buffer has room, read more bytes at the end */
        if (feed_len < FEED_BUF_SIZE) {
            int n = fread(feed + feed_len, 1, FEED_BUF_SIZE - feed_len, f);
            if (n > 0) feed_len += n;
        }

        /* Nothing left and no more to read? done. */
        if (feed_len == 0)
            break;

        /* Try to decode from the current buffer */
        int samples = mp3dec_decode_frame(&dec, feed, feed_len, pcm, &info);

        if (info.frame_bytes > 0) {
            /* Consume the bytes the decoder used */
            int used = info.frame_bytes;
            feed_len -= used;
            if (feed_len > 0)
                memmove(feed, feed + used, (size_t)feed_len);
        } else {
            /* Decoder needs more bytes to find/complete a frame */
            /* If file is ended and we still can’t decode, drop 1 byte to resync */
            if (feof(f)) {
                feed_len--;
                if (feed_len > 0)
                    memmove(feed, feed + 1, (size_t)feed_len);
                else
                    break;
            }
        }

        if (samples > 0) {
            /* Use PCM here. If stereo, data is interleaved L R L R ... */
            int channels = info.channels;   /* 1 or 2 */
            int out_count = samples * channels;

            /* TODO: play / write PCM. Example: write to stdout or device */
            /* fwrite(pcm, sizeof(int16_t), out_count, out); */
        }
    }

    fclose(f);
    return 0;
}

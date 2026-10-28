name        mp3dec.lib
longname    "MP3 Decoder"
tokenchars  "MP3D"
tokenid     0
type        library, single, c-api
library     geos
library     ansic
resource    dgroup fixed read-only shared
resource    MP3MathCode code read-only shared
resource    MP3FrameCode code read-only shared
resource    MP3HuffCode code read-only shared
resource    MP3ImdctCode code read-only shared
resource    MP3SynthCode code read-only shared
resource    MP3QuantCode code read-only shared
resource    MP3SterCode code read-only shared
export MP3DECCREATE
export MP3DECFEED
export MP3DECREADPCM
export MP3DECGETFORMAT
export MP3DECRESET
export MP3DECDESTROY

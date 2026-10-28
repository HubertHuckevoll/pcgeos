name        mp3wav.app
longname    "MP3 to WAV"
type        appl, process, single
class       Mp3WavProcessClass
appobj      Mp3WavApp
tokenchars  "MP3W"
tokenid     0
stack       4096
heapspace   4096
library     geos
library     ui
library     ansic
library     mp3dec
resource    AppResource ui-object
resource    Interface ui-object

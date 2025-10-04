########################################################################
#
#     Simple Mixer Application
#
########################################################################

name mixer.app
longname "Mixer"
tokenchars "MIXR"
tokenid 0

type    appl, process, single

class   MixerProcessClass
appobj  MixerApp

library geos
library ui
library mixlib

resource AppResource          ui-object
resource Interface            ui-object


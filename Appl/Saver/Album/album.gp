# Parameters for specific screen saver library
# $Id: album.gp,v 1.1 97/04/04 16:44:09 newdeal Exp $
#
# Permanent name
#
name album.lib
type appl, process, single
#
# This is the name that appears in the generic saver's list
#
longname "Album"
#
# All specific screen savers have a token of SSAV, and for now they must have
# our manufacturer's ID (until the file selector can be told to ignore the
# ID)
#
tokenchars "SSAV"
tokenid 0
#
# We use the saver library, of course.
#
library saver
#
# We have user-savable options.
#
library ui
#
# The need for this is self-evident...
#
library geos
resource AppResource ui-object
resource AlbumOptions ui-object
resource AlbumHelp ui-object
class AlbumProcessClass
appobj AlbumApp
export AlbumApplicationClass

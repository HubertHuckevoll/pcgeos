name dbglog.lib
longname "Debug Logging Library"
type library, single
tokenchars "DLIB"
tokenid 0
library geos
library ansic

export dbgLogInit
export dbgLogStart
export dbgLog
export dbgLogEnd

export dbgLogStrSegment
export dbgLogStrHead
export dbgLogStrTail
export dbgLogStrRange
export dbgLogStrAll

export dbgLogByte
export dbgLogSByte
export dbgLogWord
export dbgLogSWord
export dbgLogDWord
export dbgLogSDWord
export dbgLogBoolean
export dbgLogPtr
export dbgLogChunkHandle
export dbgLogMemHandle
export dbgLogFileHandle
export dbgLogOptr

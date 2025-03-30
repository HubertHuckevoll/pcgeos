name dbglog.lib
longname "Debug Logging Library"
type library, single
tokenchars "DLIB"
tokenid 0
library geos
library ansic

export LogInit
export LogStart
export Log
export LogEnd

export LogStrHead
export LogStrTail
export LogStrRange
export LogStrAll

export LogByte
export LogSByte
export LogWord
export LogSWord
export LogDWord
export LogSDWord
export LogBoolean
export LogPtr
export LogChunkHandle
export LogMemHandle
export LogFileHandle
export LogOptr

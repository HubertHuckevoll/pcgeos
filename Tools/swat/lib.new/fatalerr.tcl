##############################################################################
#
# 	Copyright (c) GeoWorks 1991 -- All Rights Reserved
#
# PROJECT:	PC GEOS
# MODULE:	fatalerr.tcl
# FILE: 	fatalerr.tcl
# AUTHOR: 	Adam de Boor, Nov  4, 1991
#
# COMMANDS:
# 	Name			Description
#	----			-----------
#   	why 	    	    	display the FatalError that killed us
#   	explain	    	    	explain the FatalError that killed us
#
# REVISION HISTORY:
#	Name	Date		Description
#	----	----		-----------
#	ardeb	11/ 4/91	Initial Revision
#
# DESCRIPTION:
#	Functions to decode a fatal error
#
#	$Id: fatalerr.tcl,v 1.37 97/04/29 18:59:32 dbaumann Exp $
#
###############################################################################

#
# Define & create the table into which the text of various error explanations
# can be placed by the individual patient-specific .fei files.
#
defvar fatalerr_info_table nil

if {[null $fatalerr_info_table]} {
   var fatalerr_info_table [table create]
}

[defvar fatalerr_auto_explain 1 {swat_variable.preference}
{Usage:
    var fatalerr_auto_explain (1|0)

Examples:
    "var fatalerr_auto_explain 0"	Turn off automatic generation of
					the explanation for any fatal-error
					hit.

Synopsis:
    Determines if the "why" command will automatically provide you with an
    explanation of any fatal error you encounter. If non-zero, they will
    be provided whenever FatalError is hit.

Notes:
    * Explanations are loaded from <patient>.fei files stored in the system
      Tcl library directory when an error in <patient> is encountered.

    * You can also obtain an explanation of an error via the "explain" command.

See also:
    why, explain
}]

##############################################################################
#				geterror
##############################################################################
#
# SYNOPSIS:	Get the reason for death
# PASS:		none
# RETURN:	error - FatalErrors value (NULL if not in FatalError)
#   	    	pname - name of patient defining the FatalError
#   	    	nf - frame token of caller
#
# REVISION HISTORY:
#	Name	Date		Description
#	----	----		-----------
#	gene	3/16/92		Initial Revision
#
##############################################################################

[defsubr geterror {}
{
    [set-stack-frame-for-gym-files]
    # only look up to 3 frames down, otherwise forget it
    [for {var f [frame top] level 0}
    	 {![null $f] && [frame function $f] != FatalError && $level < 3}
	 {var f [frame next $f] level [expr $level+1]}
	{}
    ]

    if {![null $f] && $level < 3} {
	#
	# Find the symbol of the caller of FatalError
	#
    	var nf [frame next $f]
    	if {[null $nf] || [frame function [frame top]] == AppFatalError} {
    	    var	ft [frame top]
    	    var addr [format {%d:%d} [frame register cs $ft]
   	    	    	    	[frame register ip $ft]]
    	    [if {[string c [symbol-kernel-internal $addr] FatalError] == 0 &&
    	    	[string c [sym name [frame funcsym $ft]] AppFatalError] == 0}
    	    {
#       	    	var myss [frame register ss $ft]
#    	    	var mysp [frame register sp $ft]
#    	    	var mycs [frame register cs $ft]
#    	    	var myoff  [expr [value fetch $myss:$mysp word]+1]
    	    	var frpc [frame register pc [frame next $ft]]
	    	var pname [patient name [handle patient [handle find
			[frame register cs [frame next [frame top]]]:0]]]
    	    	    var fe [symbol find type $pname::FatalErrors]
#        	    var error [type emap [value fetch $mycs:$myoff word] $fe]
		    var error [type emap [value fetch $frpc+1 word] $fe]
		    return [concat $error $pname [frame next [frame top]]]
    	    }]
    	}
	var fs [frame funcsym $nf]
	#
	# Fetch its full name so we find the patient and figure if we were
	# called from outside the kernel.
	#
	var fn [symbol fullname $fs]
    	if {[string match $fn *::AppFatalError]} {
    	    # called through external kernel entry point, so need to go up one
	    # more level.
	    var nf [frame next $nf]
	    var fs [frame funcsym $nf]
	    var error_val [value fetch [frame register pc $nf]+1 word]
    	} elif {[string match $fn *::CFATALERROR]} {
	    # called through external C kernel entry point, so need to go up
	    # one more level and get the error code off the stack.
	    var nf [frame next $nf]
	    var fs [frame funcsym $nf]
    	    # +4 skips over the return address to $nf, which is the
	    # one that called CFATALERROR
    	    var error_val [value fetch [frame register ss $nf]:[frame register sp $nf]+4 word]
    	} else {
    	    var error_val [value fetch [frame register pc $nf]+1 word]
    	}
    	if {[null $fs]} {
    	    var fe [symbol find type geos::FatalErrors]
    	} else {
	    var fe [symbol find type [patient name [symbol patient $fs]]::FatalErrors]
    	}
	var error [type emap $error_val $fe]
	var pname [index [range [patient fullname [symbol patient $fe]] 0 7 char] 0]
	#
	# Make sure we've tried to load the error-description file for this
	# patient.
	#
	global ${pname}_errs_loaded
	if {[null [var ${pname}_errs_loaded]]} {
	    catch {load ${pname}.fei}
	    var ${pname}_errs_loaded 1
    	}

    	return [concat $error $pname $nf]
    } else {
	var ft [frame top]
	var fn [frame next $ft]
    	var addr [format {%d:%d} [frame register cs $ft]
    	    	    	    	[frame register ip $ft]]

    	if {![null [frame funcsym $ft]] && [string m [sym name [frame funcsym $ft]] *CFATALERROR] == 1} {
    	    if {![null $fn]} {
    	    	var myss [frame register ss $fn]
		var mysp [frame register sp $fn]
       	    	var pname [patient name [handle patient [handle find
    	    	    				[frame register cs $fn]:0]]]
    	    	var fe [sym find type $pname::FatalErrors]
    	    	if {[null $fe]} {
    	    	    var fe [sym find type geos::FatalErrors]
    	    	}
    	    	var error [type emap [value fetch $myss:$mysp+4 word] $fe]
    	    	if {[null $error]} {
		    var error [type emap [value fetch $mycs:$myoff word]
 	    	       	    [sym find type geos::FatalErrors]]
    	    	}
    	    }
    	    return [concat $error $pname $ft]
    	}

    	if {[string c [symbol-kernel-internal $addr] FatalError] == 0} {

    	    if [null $fn] {
    	    	var pname geos
    	    } else {
       	    	var pname [patient name [handle patient [handle find
    	    	    				[frame register cs $fn]:0]]]
    	    }
    	    var fe [symbol find type $pname::FatalErrors]
    	    var	myss [frame register ss $ft]
    	    var	mysp [frame register sp $ft]
    	    if {[null $fn]} {
    	   	var mycs [frame register cs $ft]
		var myoff  [expr [value fetch $myss:$mysp word]]
    	    } else {
    	   	var mycs [frame register cs $fn]
		var myoff [expr [frame register ip $fn]]
    	    }
    	    var	opcode [value fetch $mycs:$myoff byte]
    	    # if the opcode is wrong try using the value at ss:sp as an
    	    # offset into kcode
    	    if {$opcode != 184} {
    	    	var myoff [value fetch ss:sp word]
    	    	var mycs kcode
    	    	var fe [sym find type geos::FatalErrors]
    	    	var opcode [value fetch kcode:$myoff byte]
    	    }
    	    if {$opcode == 184} {
    	    	var myoff [expr $myoff+1]
    	    	var error [type emap [value fetch $mycs:$myoff word] $fe]
    	    	if {[null $error]} {
		    var error [type emap [value fetch $mycs:$myoff word]
 	    	       	    [sym find type geos::FatalErrors]]
    	    	}
    	    }
    	    return [concat $error $pname $ft]
    	} else {
    	    error {Unable to determine cause of death as current thread has not called FatalError}
    	}
    }
}]


##############################################################################
#				why
##############################################################################
#
# SYNOPSIS:	    Main function for decoding a fatal error
# PASS:		    nothing
# CALLED BY:	    breakpoint, user
# RETURN:
# SIDE EFFECTS:
#
# STRATEGY
#
# REVISION HISTORY:
#	Name	Date		Description
#	----	----		-----------
#	ardeb	11/ 4/91	Initial Revision
#
##############################################################################
[defcommand why {} top.crash
{Usage:
    why

Example:
    "why"

Synopsis:
    Print a description of why the system crashed.

Notes:
    * This must be run from within the frame of the FatalError
      function.  Sometimes GEOS is not quite there.  In this case,
      step an instruction or two and then try the 'why' command
      again.

    * This simply looks up the enumerated constant for the error code
      in AX in the "FatalErrors" enumerated type defined by the geode that
      called FatalError. For example, if a function in the kernel called
      FatalError, AX would be looked up in geos::FatalErrors, while if a
      function in your application called FatalError, this function would
      look it up in the FatalErrors type defined by your application.  Each
      application defines this enumerated type by virtue of having included
      ec.def

    * For certain fatal errors, additional information is provided by invoking
      the command <patient>::<error code name>, if it exists.

See also:
    regs, where, explain.
}
{
    var error [geterror]
    var errno [index $error 0]
    var pname [index $error 1]
    echo Death due to $errno

    frame set [index $error 2]

    if {![null [info proc $pname::$errno]]} {
	eval $pname::$errno
    }

    global fatalerr_auto_explain
    if {$fatalerr_auto_explain} {
	explain
    }
}]

##############################################################################
#				explain
##############################################################################
#
# SYNOPSIS:	Explain a FatalError, ie. why we crashed
# PASS:		none
# RETURN:	none
#
# REVISION HISTORY:
#	Name	Date		Description
#	----	----		-----------
#	gene	3/16/92		Initial Revision
#
##############################################################################

[defcommand explain {args} top.crash
{Usage:
    explain

Example:
    "explain"

Synopsis:
    Print a more detailed description of why the system crashed, if possible.

Notes:
    * This must be run from within the frame of the FatalError
      function.  Sometimes GEOS is not quite there.  In this case,
      step an instruction or two and then try the 'why' command
      again.

    * This simply looks up the enumerated constant for the error code
      in AX in the "FatalErrors" enumerated type defined by the geode that
      called FatalError. For example, if a function in the kernel called
      FatalError, AX would be looked up in geos::FatalErrors, while if a
      function in your application called FatalError, this function would
      look it up in the FatalErrors type defined by your application.  Each
      application defines this enumerated type by virtue of having included
      ec.def

    * This command also relies on programmers having explained their
      FatalErrors when defining them.  If you come across a FatalError that
      isn't documented, do so.  It will help the next person.

See also:
    regs, where, why.
}
{
    #
    # Figure out why and where we crashed
    #
    var error [geterror]
    var ename [index $error 0]
    #
    # Explain why we crashed
    #
    echo Execution died in patient [index $error 1]:
    frame set [index $error 2]

    global fatalerr_info_table
    var exp [table lookup ${fatalerr_info_table} [index $error 1]::$ename]

    if {[null $exp]} {
    	echo *** No explanation available ***
    } else {
    	echo $exp
    }
}]

##############################################################################
#				why-warning
##############################################################################
#
# SYNOPSIS:	Print out the warning code when someone calls WarningNotice.
# PASS:		nothing
# CALLED BY:	breakpoint module
# RETURN:	0 (continue the machine)
# SIDE EFFECTS:
#
# STRATEGY
#
# REVISION HISTORY:
#	Name	Date		Description
#	----	----		-----------
#	ardeb	10/25/92	Initial Revision
#
##############################################################################
defvar warning-ignore-list nil

[defsubr why-warning-ec-find-var-symbol-in-scope-chain {name scope}
{
    var ssym [symbol find scope $scope]
    if {[null $ssym]} {
        return nil
    }

    while {[string c [symbol type $ssym] module] != 0} {
        foreach class {locvar var} {
            if {[catch {var sym [symbol find $class $name $ssym]} symErr] == 0 &&
                ![null $sym]} {
                return $sym
            }
        }
        var ssym [symbol scope $ssym 1]
    }

    return nil
}]

[defsubr why-warning-ec-find-var-symbol {name callerFrame callerP patientName}
{
    if {![null $callerP]} {
        if {[catch {var callerSym [symbol faddr proc $callerP]} callerErr] == 0 &&
            ![null $callerSym]} {
            if {[catch {var sym [symbol find locvar $name $callerSym]} symErr] == 0 &&
                ![null $sym]} {
                return $sym
            }

            if {[catch {var sym [symbol find var $name $callerSym]} symErr] == 0 &&
                ![null $sym]} {
                return $sym
            }

            if {[catch {var callerScope [symbol fullname $callerSym]} cscopeErr] == 0 &&
                ![null $callerScope]} {
                var sym [why-warning-ec-find-var-symbol-in-scope-chain $name $callerScope]
                if {![null $sym]} {
                    return $sym
                }
            }
        }
    }

    if {![null $callerFrame] && ![null [frame funcsym $callerFrame]]} {
        var callerFrameSym [frame funcsym $callerFrame]

        if {[catch {var sym [symbol find locvar $name $callerFrameSym]} symErr] == 0 &&
            ![null $sym]} {
            return $sym
        }

        if {[catch {var sym [symbol find var $name $callerFrameSym]} symErr] == 0 &&
            ![null $sym]} {
            return $sym
        }

        if {[catch {var scopeName [frame scope $callerFrame]} scopeErr] == 0 &&
            ![null $scopeName]} {
            var sym [why-warning-ec-find-var-symbol-in-scope-chain $name $scopeName]
            if {![null $sym]} {
                return $sym
            }
        }
    }

    if {![null $patientName]} {
        if {[catch {var sym [symbol find var [format {%s::%s} $patientName $name]]}
                   symErr] == 0 &&
            ![null $sym]} {
            return $sym
        }
    }

    if {[catch {var sym [symbol find var $name]} symErr] == 0 &&
        ![null $sym]} {
        return $sym
    }

    if {[catch {var sym [symbol find any $name]} symErr] == 0 &&
        ![null $sym]} {
        var symClass [symbol class $sym]
        if {[string c $symClass var] == 0 ||
            [string c $symClass locvar] == 0} {
            return $sym
        }
    }

    return nil
}]

[defsubr why-warning-ec-c-to-swat-expr {expr}
{
    var idx [string first -> $expr]
    if {$idx < 0} {
        return $expr
    }

    var base [range $expr 0 [expr {$idx-1}] c]
    var rest [range $expr [expr {$idx+2}] end c]
    if {[null $base] || [null $rest]} {
        return $expr
    }

    var out $base
    while {1} {
        var nextIdx [string first -> $rest]
        if {$nextIdx < 0} {
            var field $rest
            if {[null $field]} {
                return $expr
            }
            var out [format {(*%s).%s} $out $field]
            return $out
        }
        var field [range $rest 0 [expr {$nextIdx-1}] c]
        if {[null $field]} {
            return $expr
        }
        var out [format {(*%s).%s} $out $field]
        var rest [range $rest [expr {$nextIdx+2}] end c]
    }
}]

[defsubr why-warning-ec-find-member-op {expr}
{
    var arrowIdx [string first -> $expr]
    var dotIdx [string first . $expr]

    if {$arrowIdx < 0 && $dotIdx < 0} {
        return [list -1 {}]
    }
    if {$arrowIdx >= 0 && ($dotIdx < 0 || $arrowIdx < $dotIdx)} {
        return [list $arrowIdx ->]
    }
    return [list $dotIdx .]
}]

[defsubr why-warning-ec-find-field-type {structType fieldName}
{
    if {[catch {var fieldList [type fields $structType]} fieldsErr] != 0} {
        return nil
    }

    foreach field $fieldList {
        if {[string c [index $field 0] $fieldName] == 0} {
            return [index $field 3]
        }
    }

    return nil
}]

[defsubr why-warning-ec-get-member-expression-type {expr callerFrame callerP patientName}
{
    var opInfo [why-warning-ec-find-member-op $expr]
    var opPos [index $opInfo 0]
    if {$opPos < 0} {
        return nil
    }

    var baseExpr [range $expr 0 [expr {$opPos-1}] c]
    if {[null $baseExpr]} {
        return nil
    }

    var baseSym [why-warning-ec-find-var-symbol $baseExpr $callerFrame $callerP $patientName]
    if {[null $baseSym]} {
        return nil
    }

    var symData [symbol get $baseSym]
    if {[null [index $symData 2]]} {
        return nil
    }
    var curType [index $symData 2]

    var rest [range $expr $opPos end c]
    while {![null $rest]} {
        var opLen 0
        var op {}
        if {[string first -> $rest] == 0} {
            var opLen 2
            var op ->
        } elif {[string first . $rest] == 0} {
            var opLen 1
            var op .
        } else {
            return nil
        }

        var rest [range $rest $opLen end c]
        if {[null $rest]} {
            return nil
        }

        var nextInfo [why-warning-ec-find-member-op $rest]
        var nextPos [index $nextInfo 0]
        if {$nextPos < 0} {
            var fieldName $rest
            var rest {}
        } else {
            var fieldName [range $rest 0 [expr {$nextPos-1}] c]
            var rest [range $rest $nextPos end c]
        }
        if {[null $fieldName]} {
            return nil
        }

        if {[string c $op ->] == 0} {
            if {[string c [type class $curType] pointer] != 0} {
                return nil
            }
            if {[catch {var pinfo [type pget $curType]} pgetErr] != 0} {
                return nil
            }
            var pointeeType [index $pinfo 1]
            if {[null $pointeeType]} {
                return nil
            }
            var curType $pointeeType
        }

        var curClass [type class $curType]
        if {[string c $curClass struct] != 0 &&
            [string c $curClass union] != 0} {
            return nil
        }

        var nextType [why-warning-ec-find-field-type $curType $fieldName]
        if {[null $nextType]} {
            return nil
        }
        var curType $nextType
    }

    return $curType
}]

[defsubr why-warning-ec-get-expression-type {expr callerFrame callerP patientName}
{
    var memberType [why-warning-ec-get-member-expression-type $expr $callerFrame $callerP $patientName]
    if {![null $memberType]} {
        return $memberType
    }

    var candidate1 $expr
    var candidate2 [why-warning-ec-c-to-swat-expr $expr]

    foreach candidate [list $candidate1 $candidate2] {
        if {[null $candidate]} {
            continue
        }
        if {![null $callerFrame]} {
            if {[catch {var parsed [addr-parse $candidate 0 $callerFrame]} parseErr] == 0 &&
                ![null [index $parsed 2]]} {
                return [index $parsed 2]
            }
        } else {
            if {[catch {var parsed [addr-parse $candidate 0]} parseErr] == 0 &&
                ![null [index $parsed 2]]} {
                return [index $parsed 2]
            }
        }
    }

    return nil
}]

[defsubr why-warning-ec-print-type-value {valueType p callerFrame}
{
    var oldFrame nil
    if {![null $callerFrame]} {
        if {[catch {var cur [frame cur]} frameErr] == 0 &&
            ![null $cur] &&
            [catch {frame set $callerFrame 0} setErr] == 0} {
            var oldFrame $cur
        }
    }

    var printed 0
    if {[catch {var fetched [value fetch $p $valueType]} fetchErr] == 0} {
        var fmtType $valueType
        var fmtValue $fetched
        if {[string c [type class $valueType] pointer] == 0} {
            var pinfo [type pget $valueType]
            var ptrKind [index $pinfo 0]
            var pointeeType [index $pinfo 1]
            if {![null $pointeeType]} {
                var pointeeClass [type class $pointeeType]
                if {([string c $pointeeClass struct] == 0 ||
                     [string c $pointeeClass union] == 0 ||
                     [string c $pointeeClass array] == 0) &&
                    $fetched != 0 &&
                    $fetched != 0xffff} {
                    var targetP nil
                    [case $ptrKind in
                        {far virtual} {
                            var targetP [format %04xh:%04xh
                                         [expr {($fetched >> 16) & 0xffff}]
                                         [expr {$fetched & 0xffff}]]
                        }
                        near {
                            if {[catch {addr-preprocess $p baseSeg baseOff} addrErr] == 0} {
                                var targetP [format %04xh:%04xh $baseSeg
                                             [expr {$fetched & 0xffff}]]
                            }
                        }
                    ]
                    if {![null $targetP] &&
                        [catch {var pointeeValue [value fetch $targetP $pointeeType]}
                               derefErr] == 0} {
                        var fmtType $pointeeType
                        var fmtValue $pointeeValue
                    }
                }
            }
        }

        if {[catch {require fmtval print} loadErr] == 0 &&
            [catch {fmtval $fmtValue $fmtType 0} fmtErr] == 0} {
            var printed 1
        } else {
            # Fallback to expression parsing for unusual cases.
            if {[catch {var valueTypeName [type name $fmtType {} 0]} typeNameErr] == 0 &&
                [catch {_print $valueTypeName $p} printErr] == 0} {
                var printed 1
            } elif {[catch {var fullTypeName [symbol fullname $fmtType]} fullTypeErr] == 0 &&
                    ![null $fullTypeName] &&
                    [catch {_print $fullTypeName $p} printErr2] == 0} {
                var printed 1
            }
        }
    }

    if {![null $oldFrame]} {
        catch {frame set $oldFrame 0} restoreErr
    }

    return $printed
}]

[defsubr why-warning-ec-print-symbol-value {sym p callerFrame}
{
    var symData [symbol get $sym]
    if {[null [index $symData 2]]} {
        return 0
    }

    return [why-warning-ec-print-type-value [index $symData 2] $p $callerFrame]
}]

[defsubr why-warning-ec-print-raw-fallback {varSym exprType varName p callerP}
{
    if {[catch {var rawWord [value fetch $p word]} rawWordErr] == 0 &&
        [catch {var rawDWord [value fetch $p dword]} rawDWordErr] == 0} {
        if {![null $varSym]} {
            echo [format {<resolved symbol %s but could not print typed value; fallback raw word=%04xh dword=%08xh at %s (caller %s)>} [symbol fullname $varSym] $rawWord $rawDWord $p $callerP]
        } elif {![null $exprType]} {
            echo [format {<resolved expression type %s but could not print typed value; fallback raw word=%04xh dword=%08xh at %s (caller %s)>} [type name $exprType {} 0] $rawWord $rawDWord $p $callerP]
        } else {
            echo [format {<unresolved var %s from %s; fallback raw word=%04xh dword=%08xh at %s>} $varName $callerP $rawWord $rawDWord $p]
        }
    } elif {[catch {var rawWord [value fetch $p word]} rawWordErr] == 0} {
        if {![null $varSym]} {
            echo [format {<resolved symbol %s but could not print typed value; fallback raw word=%04xh at %s (caller %s)>} [symbol fullname $varSym] $rawWord $p $callerP]
        } elif {![null $exprType]} {
            echo [format {<resolved expression type %s but could not print typed value; fallback raw word=%04xh at %s (caller %s)>} [type name $exprType {} 0] $rawWord $p $callerP]
        } else {
            echo [format {<unresolved var %s from %s; fallback raw word=%04xh at %s>} $varName $callerP $rawWord $p]
        }
    } else {
        if {![null $varSym]} {
            echo [format {<resolved symbol %s but could not print typed value at %s (caller %s)>} [symbol fullname $varSym] $p $callerP]
        } elif {![null $exprType]} {
            echo [format {<resolved expression type %s but could not print typed value at %s (caller %s)>} [type name $exprType {} 0] $p $callerP]
        } else {
            echo [format {<unresolved var %s from %s at %s>} $varName $callerP $p]
        }
    }
}]

[defsubr why-warning-handle-ec-log {code warningFrame}
{
    var geosWarnings [symbol find type geos::Warnings]
    if {[null $geosWarnings] ||
        [string c [type emap $code $geosWarnings] EC_LOG_WARNING] != 0} {
        return 0
    }

    var warnCaller [frame next $warningFrame]
    var patientName {}
    if {![null $warnCaller] && ![null [frame funcsym $warnCaller]]} {
        var patientName [patient name [symbol patient [frame funcsym $warnCaller]]]
    }

    var varName [getstring ECLogVarName]
    var addr [value fetch ECLogAddr dword]
    var callerAddr [value fetch ECLogCaller dword]
    var off [expr {$addr & 0xffff}]
    var seg [expr {($addr >> 16) & 0xffff}]
    var callerOff [expr {$callerAddr & 0xffff}]
    var callerSeg [expr {($callerAddr >> 16) & 0xffff}]
    if {$addr == 0} {
        echo [format {EC log (%s): (null)} $varName]
        return 1
    }

    var p [format %04xh:%04xh $seg $off]
    var callerP [format %04xh:%04xh $callerSeg $callerOff]
    var callerFrame nil
    if {![null $warnCaller]} {
        var callerFrame [frame next $warnCaller]
    }

    var callerPatientName $patientName
    if {![null $callerFrame] && ![null [frame funcsym $callerFrame]]} {
        var callerPatientName [patient name [symbol patient [frame funcsym $callerFrame]]]
    }
    if {[catch {var callerSym [symbol faddr proc $callerP]} callerErr] == 0 &&
        ![null $callerSym]} {
        var callerPatientName [patient name [symbol patient $callerSym]]
    }

    if {[null $varName]} {
        var varName {<?>}
    }

    if {[string c [range $varName 0 0 chars] {$}] == 0} {
        var strName [range $varName 1 end chars]
        if {[null $strName]} {
            var strName {<?>}
        }
        echo -n [format {EC log (%s): } $strName]
        if {[catch {pstring $p} pstringErr] != 0} {
            echo [format {<could not print string at %s>} $p]
        }
        return 1
    }

    var varSym [why-warning-ec-find-var-symbol $varName $callerFrame $callerP $callerPatientName]
    var exprType nil
    if {[null $varSym]} {
        var exprType [why-warning-ec-get-expression-type $varName $callerFrame $callerP $callerPatientName]
        if {[catch {var addrSym [symbol faddr var $p]} addrSymErr] == 0 &&
            ![null $addrSym] &&
            [string c [symbol name $addrSym] $varName] == 0} {
            var varSym $addrSym
        }
    }

    echo -n [format {EC log (%s): } $varName]
    if {![null $varSym] &&
        [why-warning-ec-print-symbol-value $varSym $p $callerFrame]} {
        # printed
    } elif {![null $exprType] &&
             [why-warning-ec-print-type-value $exprType $p $callerFrame]} {
        # printed
    } else {
        [why-warning-ec-print-raw-fallback $varSym $exprType $varName $p $callerP]
    }

    return 1
}]

[defsubr why-warning {}
{
    global warning-ignore-list

    var f [frame top]

    if {![catch {symbol name [frame funcsym $f]} name] &&
	[string match $name Writable*]} {
	    var f [frame next $f]
	}

    if {[null $f] || [null [frame next $f]] || [null [frame funcsym $f]]} {
	var w {unable to determine warning code, as top frame is invalid}
	var patientName ""
    } else {
	if {[string c [symbol name [frame funcsym $f]] WarningNotice] == 0} {
	    # assembly version: code is in mov ax instruction following the
	    # call

	    var nframe [frame next $f]
	    if {[catch {[var rframe [frame register pc $nframe]]} wrn] != 0} {
		echo Warning: $wrn, continuing...
		return 0
	    }
	    var code [value fetch $rframe+1 word]
	} else {
	    # C version: code is pushed on the stack
	    var code [value fetch ss:sp+4 word]
	}

	if {[why-warning-handle-ec-log $code $f]} {
	    return 0
	}

	var f [frame next $f]
	if {[null [frame funcsym $f]]} {
	    return 0
	}
	var patientName [patient name
				 [symbol patient
				  [frame funcsym $f]]]
	var t [symbol find type $patientName::Warnings]
	var func [frame function $f]

	if {![null $t]} {
	    var w [type emap $code $t]
	    if {[null $w]} {
		var t {}
	    }
	}
	if {[null $t]} {
	    var a [frame retaddr [frame prev $f]]
	    if {[catch {src line [index $a 0]:[index $a 1] $f} w_info] != 0} {
		var w UNKNOWN_WARNING
	    } else {
		var w [format {UNKNOWN_WARNING at %s} $w_info]
	    }
	} else {
	    var w [type emap $code $t]
	}
	frame set $f 0
    }
    # suppress output if user so desires
    [case $w in
	${warning-ignore-list} {}
	default {echo WARNING($patientName::$func): $w}
    ]
    if {![null [info proc $patientName::$w]]} {
            var res [eval $patientName::$w]
    }

    if {[null $res]} {
	return 0
    } else {
        return $res
    }
}]


##############################################################################
#   	2.0 ERRORS							     #
##############################################################################


##############################################################################
#	INVALID_DIRNAME_FILE
##############################################################################
#
# SYNOPSIS:	Print the current working directory
# PASS:
# CALLED BY:
# RETURN:	nothing
# SIDE EFFECTS:	none
#
# STRATEGY:
#
# REVISION HISTORY:
#	Name	Date		Description
#	----	----		-----------
#       chrisb 	11/ 6/92   	Initial Revision
#
##############################################################################
[defsubr    dri::INVALID_DIRNAME_FILE {} {
    echo [pwd]
}]
[defsubr    ms3::INVALID_DIRNAME_FILE {} {
    echo [pwd]
}]
[defsubr    ms4::INVALID_DIRNAME_FILE {} {
    echo [pwd]
}]
[defsubr    shell::DIRINFO_FILE_NOT_SORTED {} {
    echo [pwd]
}]


[defsubr    geos::MEM_FREE_BLOCK_DATA_NOT_CC {}
{
    var start [expr [read-reg di]-2]
    if {[value fetch es:di-2 byte] == 0xcc} {
    	var start [expr $start+1]
    }
    echo [format {Scribbled data @ %04xh:%04xh:} [read-reg es] $start]
    bytes es:$start 32

    #
    # Print out info on the 5 blocks before this one (this one's handle is
    # in bx...)
    #
    var hid [read-reg bx]
    var handles {}

    [for {var i 5}
	 {$hid != [value fetch loaderVars.KLV_handleBottomBlock] && $i}
	 {var i [expr $i-1]}
    {
    	var hid [value fetch kdata:$hid.HM_prev]
	var handles [concat [list $hid] $handles]
    }]

    echo [format {%d handles before corrupted one (%04xh)} [length $handles]
    	    [read-reg bx]]

    foreach hid $handles {
    	echo [format {====== Handle %04xh} $hid]
	phandle $hid
	echo
    }
}]

[defsubr    geos::CANNOT_CALL_MEM_LOCK_ON_AN_OBJECT_BLOCK {} {
	bt 10
}]
[defsubr    geos::BLOCK_ALLOCATED_WITH_NO_FLAGS {} {
	bt 10
}]

[defsubr    geos::XIP_RESOURCE_LEFT_LOCKED_WHEN_GEODE_EXITED {} {
	var han [handle lookup [read-reg bx]]
	echo [format {Locked handle = %04xh (%s::%s)} [read-reg bx]
			[patient name [handle patient $han]]
			[symbol name [handle other $han]]]
	phandle bx
}]


[defsubr geos::TRIED_TO_BORROW_AMOUNT_GREATER_THAN_STACK_SIZE {}
{
    [for {var f [frame next [frame top]]}
	 {![string match [frame function $f] *Borrow*]}
	 {var f [frame next $f]}
    {}]
    var f [frame next $f]

    echo [frame function $f] is trying to borrow [expr [read-reg di]-100-[value fetch ss:geos::TPD_stackBot]]
    echo Current stack is [read-reg ax] ([expr [read-reg ax]-100-[value fetch ss:geos::TPD_stackBot]] after space for ints etc.)
}]



[defsubr    geos::NON_RESOURCE_BLOCK_BEING_SAVED_TO_STATE_FILE {} {
	var han [handle lookup [read-reg bx]]
	echo [format {Saved block handle handle = %04xh (%s)} [read-reg bx]
			[patient name [handle patient $han]]]
}]

[defsubr    geos::APP_DOES_NOT_HAVE_HEAP_SPACE_VALUE {} {
	if {[read-reg ds] != [read-reg ss]} {
		pstring -s -l 8 ds:GH_geodeName
		echo does not have a heapspace value yet
	}
}]

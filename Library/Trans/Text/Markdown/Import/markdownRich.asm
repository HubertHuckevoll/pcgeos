COMMENT @%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
 PC/GEOS Markdown rich-text import support

 This file is included by Import/importManager.asm after importMain.asm.
 MDReadAndImport inherits TransImport; helpers use state in the input block.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%@

MD_MAX_LINE             equ 2048
MD_MAX_INPUT            equ MD_MAX_LINE-5
MD_RAW_BYTE             equ MD_MAX_LINE-1
MD_MAX_RUNS             equ 96

MD_STYLE_BOLD           equ 0001h
MD_STYLE_ITALIC         equ 0002h
MD_STYLE_CODE           equ 0004h

MDRun struc
    MDR_startLo         word
    MDR_startHi         word
    MDR_endLo           word
    MDR_endHi           word
    MDR_style           word
MDRun ends

;
; The input block contains both the decoded source line and this state.  DS
; remains the input block throughout an import, so state is per import and
; does not require writable global storage or implicit segment overrides.
;
MDState struc
    MDS_mdRunCount           word
    MDS_mdHeadingLevel       word
    MDS_mdHeadingStart       word
    MDS_mdQuote              word
    MDS_mdCurrentLineLength  word
    MDS_mdTextEnd            word
    MDS_mdBaseLo             word
    MDS_mdBaseHi             word
    MDS_mdAbsStartLo         word
    MDS_mdAbsStartHi         word
    MDS_mdAbsEndLo           word
    MDS_mdAbsEndHi           word
    MDS_mdLastError          word
    MDS_mdSourceFile         hptr
    MDS_mdTextObj            optr
    MDS_mdDeferredError      word
    MDS_mdNewlineChar        byte
    MDS_mdCharPending        byte
    MDS_mdCharPendingValid   word
    MDS_mdUTFLead            byte
    MDS_mdUTFSecond          byte
    MDS_mdUTFThird           byte
    MDS_mdRawPushCount       word
    MDS_mdRawPush            byte 3 dup (?)
    MDS_mdRuns               MDRun MD_MAX_RUNS dup (<>)
MDState ends

MD_STATE_OFFSET         equ MD_MAX_LINE
MD_INPUT_SIZE           equ MD_MAX_LINE + size MDState

MD_runCount             equ MD_STATE_OFFSET + MDState.MDS_mdRunCount
MD_headingLevel         equ MD_STATE_OFFSET + MDState.MDS_mdHeadingLevel
MD_headingStart         equ MD_STATE_OFFSET + MDState.MDS_mdHeadingStart
MD_quote                equ MD_STATE_OFFSET + MDState.MDS_mdQuote
MD_currentLineLength    equ MD_STATE_OFFSET + MDState.MDS_mdCurrentLineLength
MD_textEnd              equ MD_STATE_OFFSET + MDState.MDS_mdTextEnd
MD_baseLo               equ MD_STATE_OFFSET + MDState.MDS_mdBaseLo
MD_baseHi               equ MD_STATE_OFFSET + MDState.MDS_mdBaseHi
MD_absStartLo           equ MD_STATE_OFFSET + MDState.MDS_mdAbsStartLo
MD_absStartHi           equ MD_STATE_OFFSET + MDState.MDS_mdAbsStartHi
MD_absEndLo             equ MD_STATE_OFFSET + MDState.MDS_mdAbsEndLo
MD_absEndHi             equ MD_STATE_OFFSET + MDState.MDS_mdAbsEndHi
MD_lastError            equ MD_STATE_OFFSET + MDState.MDS_mdLastError
MD_sourceFile           equ MD_STATE_OFFSET + MDState.MDS_mdSourceFile
MD_textObj              equ MD_STATE_OFFSET + MDState.MDS_mdTextObj
MD_deferredError        equ MD_STATE_OFFSET + MDState.MDS_mdDeferredError
MD_newlineChar          equ MD_STATE_OFFSET + MDState.MDS_mdNewlineChar
MD_charPending          equ MD_STATE_OFFSET + MDState.MDS_mdCharPending
MD_charPendingValid     equ MD_STATE_OFFSET + MDState.MDS_mdCharPendingValid
MD_utfLead              equ MD_STATE_OFFSET + MDState.MDS_mdUTFLead
MD_utfSecond            equ MD_STATE_OFFSET + MDState.MDS_mdUTFSecond
MD_utfThird             equ MD_STATE_OFFSET + MDState.MDS_mdUTFThird
MD_rawPushCount         equ MD_STATE_OFFSET + MDState.MDS_mdRawPushCount
MD_rawPush              equ MD_STATE_OFFSET + MDState.MDS_mdRawPush
MD_runs                 equ MD_STATE_OFFSET + MDState.MDS_mdRuns

ImportCode segment resource

;
; Read a source file line by line, translate Markdown to display text,
; append it, then apply native text attributes to the appended ranges.
;
MDReadAndImport proc near uses bx,cx,dx,si,di,bp,ds,es
    .enter inherit TransImport

    mov ax, ss:[sourceFile]
    mov ds:[MD_sourceFile], ax
    mov ax, word ptr ss:[textObj]
    mov word ptr ds:[MD_textObj], ax
    mov ax, word ptr ss:[textObj+2]
    mov word ptr ds:[MD_textObj]+2, ax

    mov ax, MD_INPUT_SIZE
    mov cx, ALLOC_DYNAMIC_LOCK
    call MemAlloc
    LONG jc  mdiOOM
    push bx                         ; input block
    mov ds, ax

    mov ax, MD_MAX_LINE
    mov cx, ALLOC_DYNAMIC_LOCK
    call MemAlloc
    jc  mdiFreeInput
    push bx                         ; output block
    mov es, ax

    mov word ptr ds:[MD_deferredError], 0
    mov word ptr ds:[MD_charPendingValid], 0
    mov word ptr ds:[MD_rawPushCount], 0
    call MDSkipUTF8BOM
    jc  mdiError
mdiNextLine:
    call MDReadLine                 ; ds:0, cx=len, ax=error if carry
    jnc mdiHaveLine
    tst ax
    jz  mdiDone
    jmp mdiError
mdiHaveLine:
    call MDParseLine                ; es:0 output, cx=len, run table follows
    mov ax, cx
    dec ax
    mov ds:[MD_currentLineLength], ax
    push cx
    push ds
    push es
    call MDGetTextSize              ; dx:ax = base
    pop es
    pop ds
    pop cx

    ; Append output block. MSG_VIS_TEXT_APPEND_BLOCK copies from this block.
    pop dx                          ; output handle
    push dx
    movdw bxsi, ss:[textObj]
    mov ax, MSG_VIS_TEXT_APPEND_BLOCK
    clr di
    push ds
    call ObjMessage
    pop ds

    ; Apply ranges emitted by MDParseLine.
    ; base is saved by MDParseLine in mdBase*, because ObjMessage may destroy regs.
    call MDApplyRuns
    jmp mdiNextLine

mdiDone:
    pop bx
    call MemFree
    pop bx
    call MemFree
    clr ax
    jmp mdiExit
mdiError:
    mov ds:[MD_lastError], ax
    pop bx
    call MemFree
    pop bx
    call MemFree
    mov ax, ds:[MD_lastError]
    jmp mdiExit
mdiFreeInput:
    pop bx
    call MemFree
    mov ax, TE_OUT_OF_MEMORY
    jmp mdiExit
mdiOOM:
    mov ax, TE_OUT_OF_MEMORY
mdiExit:
    .leave
    ret
MDReadAndImport endp

;
; Read one normalized line into ds:0. The input buffer holds GEOS SBCS
; characters, not the UTF-8 bytes read from the source file.
; Carry set returns ax=0 at EOF or a TransError on failure.
;
MDReadLine proc near uses bx,dx,si,di
    .enter
    clr di
mdrlLoop:
    cmp di, MD_MAX_INPUT
    jae mdrlTooLong
    call MDReadChar
    jc  mdrlNoChar
    cmp al, C_LF
    je  mdrlNewline
    cmp al, C_CR
    je  mdrlNewline
    mov ds:[di], al
    inc di
    jmp mdrlLoop
mdrlNoChar:
    tst ax
    jnz mdrlError
    tst di
    jz  mdrlEOF
    jmp mdrlFinish
mdrlNewline:
    mov ds:[MD_newlineChar], al
    call MDReadChar
    jc  mdrlPairError
    mov ah, ds:[MD_newlineChar]
    cmp ah, C_CR
    jne mdrlCheckCR
    cmp al, C_LF
    je  mdrlFinish
    jmp mdrlSavePending
mdrlCheckCR:
    cmp al, C_CR
    je  mdrlFinish
mdrlSavePending:
    mov ds:[MD_charPending], al
    mov word ptr ds:[MD_charPendingValid], 1
    jmp mdrlFinish
mdrlPairError:
    tst ax
    jz  mdrlFinish
    mov ds:[MD_deferredError], ax
mdrlFinish:
    mov byte ptr ds:[di], C_CR
    inc di
    mov byte ptr ds:[di], C_NULL
    mov cx, di
    clr ax
    clc
    .leave
    ret
mdrlTooLong:
    mov ax, TE_IMPORT_ERROR
    stc
    .leave
    ret
mdrlError:
    stc
    .leave
    ret
mdrlEOF:
    clr cx
    clr ax
    stc
    .leave
    ret
MDReadLine endp

;
; Read a raw byte, using a tiny push-back stack for BOM recognition and
; malformed UTF-8 recovery. Carry set returns ax=0 at EOF or TE_FILE_READ.
;
MDRawRead proc near uses bx,cx,dx
    .enter
    mov bx, ds:[MD_rawPushCount]
    tst bx
    jz  mdrrFile
    dec bx
    mov ds:[MD_rawPushCount], bx
    mov al, ds:[MD_rawPush][bx]
    clc
    .leave
    ret
mdrrFile:
    mov bx, ds:[MD_sourceFile]
    mov cx, 1
    mov dx, MD_RAW_BYTE
    clr ax
    call FileRead
    jnc mdrrRead
    cmp ax, ERROR_SHORT_READ_WRITE
    jne mdrrError
mdrrEOF:
    clr ax
    stc
    .leave
    ret
mdrrRead:
    jcxz mdrrEOF
    mov al, ds:[MD_RAW_BYTE]
    clc
    .leave
    ret
mdrrError:
    mov ax, TE_FILE_READ
    stc
    .leave
    ret
MDRawRead endp

MDRawPush proc near uses bx
    .enter
    mov bx, ds:[MD_rawPushCount]
    cmp bx, 3
    jae mdrpDone
    mov ds:[MD_rawPush][bx], al
    inc bx
    mov ds:[MD_rawPushCount], bx
mdrpDone:
    .leave
    ret
MDRawPush endp

;
; Consume a UTF-8 BOM if present. All non-BOM bytes are pushed back in
; original order for MDReadChar.
;
MDSkipUTF8BOM proc near
    .enter
    call MDRawRead
    jc  mdsbStatus
    cmp al, 0efh
    jne mdsbPushOne
    mov ds:[MD_utfLead], al
    call MDRawRead
    jc  mdsbPushLead
    cmp al, 0bbh
    jne mdsbPushTwo
    mov ds:[MD_utfSecond], al
    call MDRawRead
    jc  mdsbPushLeadSecond
    cmp al, 0bfh
    je  mdsbDone
    call MDRawPush
mdsbPushLeadSecond:
    mov al, ds:[MD_utfSecond]
    call MDRawPush
mdsbPushLead:
    mov al, ds:[MD_utfLead]
    call MDRawPush
mdsbStatus:
    tst ax
    jz  mdsbDone
    stc
    .leave
    ret
mdsbPushTwo:
    call MDRawPush
    mov al, ds:[MD_utfLead]
    call MDRawPush
mdsbDone:
    clc
    .leave
    ret
mdsbPushOne:
    call MDRawPush
    clc
    .leave
    ret
MDSkipUTF8BOM endp

;
; Return one GEOS SBCS character in AL. UTF-8 is decoded here so Markdown
; syntax remains ASCII while visible text uses the native character set.
;
MDReadChar proc near uses bx,cx,dx,si,di,ds,es
    .enter
    mov ax, ds:[MD_deferredError]
    tst ax
    jz  mdrcPending
    mov word ptr ds:[MD_deferredError], 0
    stc
    .leave
    ret
mdrcPending:
    cmp word ptr ds:[MD_charPendingValid], 0
    jz  mdrcRaw
    mov word ptr ds:[MD_charPendingValid], 0
    mov al, ds:[MD_charPending]
    clc
    .leave
    ret
mdrcRaw:
    call MDRawRead
    LONG jc  mdrcStatus
    cmp al, 80h
    LONG jb  mdrcDone
    mov ds:[MD_utfLead], al
    cmp al, 0c2h
    LONG jb  mdrcBad
    cmp al, 0dfh
    jbe mdrcTwo
    cmp al, 0efh
    jbe mdrcThree
    cmp al, 0f4h
    LONG jbe mdrcFour
    jmp mdrcBad
mdrcTwo:
    call MDRawRead
    LONG jc  mdrcIncomplete
    mov ds:[MD_utfSecond], al
    and al, 0c0h
    cmp al, 80h
    je  mdrcTwoDecode
    mov al, ds:[MD_utfSecond]
    call MDRawPush
    jmp mdrcBad
mdrcTwoDecode:
    mov bl, ds:[MD_utfLead]
    and bl, 01fh
    xor bh, bh
    shl bx, 1
    shl bx, 1
    shl bx, 1
    shl bx, 1
    shl bx, 1
    shl bx, 1
    mov al, ds:[MD_utfSecond]
    and al, 03fh
    xor ah, ah
    add ax, bx
    jmp mdrcMap
mdrcThree:
    call MDRawRead
    LONG jc  mdrcIncomplete
    mov ds:[MD_utfSecond], al
    and al, 0c0h
    cmp al, 80h
    LONG jne mdrcPushBad
    mov al, ds:[MD_utfLead]
    cmp al, 0e0h
    jne mdrcNoOverlong
    cmp ds:[MD_utfSecond], 0a0h
    jb  mdrcBad
mdrcNoOverlong:
    cmp al, 0edh
    jne mdrcThird
    cmp ds:[MD_utfSecond], 0a0h
    jae mdrcBad
mdrcThird:
    call MDRawRead
    jc  mdrcIncomplete
    mov ds:[MD_utfThird], al
    and al, 0c0h
    cmp al, 80h
    je  mdrcThreeDecode
    mov al, ds:[MD_utfThird]
    call MDRawPush
    jmp mdrcBad
mdrcThreeDecode:
    mov bl, ds:[MD_utfLead]
    and bl, 00fh
    xor bh, bh
    shl bx, 1
    shl bx, 1
    shl bx, 1
    shl bx, 1
    shl bx, 1
    shl bx, 1
    mov al, ds:[MD_utfSecond]
    and al, 03fh
    xor ah, ah
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    shl ax, 1
    add bx, ax
    mov al, ds:[MD_utfThird]
    and al, 03fh
    xor ah, ah
    add ax, bx
    jmp mdrcMap
mdrcFour:
    mov cx, 3
mdrcFourLoop:
    call MDRawRead
    jc  mdrcIncomplete
    mov ah, al
    and ah, 0c0h
    cmp ah, 80h
    jne mdrcPushBad
    loop mdrcFourLoop
    jmp mdrcBad
mdrcPushBad:
    call MDRawPush
mdrcBad:
    mov al, '?'
    clc
    .leave
    ret
mdrcIncomplete:
    tst ax
    jnz mdrcStatus
    jmp mdrcBad
mdrcMap:
    call MDMapUnicode
    clc
    .leave
    ret
mdrcStatus:
    stc
    .leave
    ret
mdrcDone:
    clc
    .leave
    ret
MDReadChar endp

MDMapUnicode proc near uses bx,cx,dx,si,di,bp,ds,es
    .enter
    push ax
    call HTMLTRANSLATECHARNUM
    add sp, 2
    tst ax
    jnz mdmuDone
    mov ax, '?'
mdmuDone:
    .leave
    ret
MDMapUnicode endp

;
; Parse one line.
; Input: ds:0, cx bytes including C_CR
; Output: es:0, cx bytes; run count/table stored in the input block.
;
MDParseLine proc near uses ax,bx,dx,si,di,bp
    .enter
    clr si
    clr di
    mov word ptr ds:[MD_runCount], 0
    mov word ptr ds:[MD_headingLevel], 0
    mov word ptr ds:[MD_quote], 0

    call MDIsHRule
    jnc mdplNotHRule
    mov cx, 40
    mov al, '-'
    cld
    rep stosb
    mov byte ptr es:[di], C_CR
    inc di
    mov cx, di
    .leave
    ret
mdplNotHRule:
    ; heading
    mov bx, si
mdplHashes:
    cmp byte ptr ds:[si], '#'
    jne mdplAfterHashes
    inc si
    inc word ptr ds:[MD_headingLevel]
    cmp word ptr ds:[MD_headingLevel], 6
    jb  mdplHashes
mdplAfterHashes:
    cmp word ptr ds:[MD_headingLevel], 0
    jz  mdplQuote
    cmp byte ptr ds:[si], ' '
    jne mdplNotHeading
    inc si
    jmp mdplPrefixesDone
mdplNotHeading:
    mov si, bx
    mov word ptr ds:[MD_headingLevel], 0

mdplQuote:
    cmp byte ptr ds:[si], '>'
    jne mdplList
    inc si
    cmp byte ptr ds:[si], ' '
    jne mdplQuotePrefix
    inc si
mdplQuotePrefix:
    mov byte ptr es:[di], '"'
    inc di
    mov byte ptr es:[di], ' '
    inc di
    mov word ptr ds:[MD_quote], 1
    jmp mdplPrefixesDone

mdplList:
    ; unordered marker
    mov al, ds:[si]
    cmp al, '-'
    je  mdplMaybeBullet
    cmp al, '*'
    je  mdplMaybeBullet
    cmp al, '+'
    jne mdplOrdered
mdplMaybeBullet:
    cmp byte ptr ds:[si+1], ' '
    jne mdplOrdered
    add si, 2
    mov byte ptr es:[di], 0a5h      ; GEOS bullet in SBCS fonts
    inc di
    mov byte ptr es:[di], ' '
    inc di
    jmp mdplPrefixesDone

mdplOrdered:
    mov bx, si
mdplDigits:
    mov al, ds:[si]
    cmp al, '0'
    jb  mdplNotOrdered
    cmp al, '9'
    ja  mdplNotOrdered
    mov es:[di], al
    inc si
    inc di
    jmp mdplDigits
mdplNotOrdered:
    cmp si, bx
    je  mdplRestoreOrdered
    cmp byte ptr ds:[si], '.'
    jne mdplRestoreOrdered
    cmp byte ptr ds:[si+1], ' '
    jne mdplRestoreOrdered
    mov byte ptr es:[di], '.'
    inc di
    mov byte ptr es:[di], ' '
    inc di
    add si, 2
    jmp mdplPrefixesDone
mdplRestoreOrdered:
    mov si, bx
    clr di

mdplPrefixesDone:
    ; Heading run starts at first visible heading character.
    cmp word ptr ds:[MD_headingLevel], 0
    jz  mdplInline
    mov ds:[MD_headingStart], di

mdplInline:
    mov al, ds:[si]
    cmp al, C_CR
    LONG je  mdplEndLine

    ; inline code
    cmp al, '`'
    jne mdplBoldStar
    mov cx, 1
    call MDHasClosing
    LONG jnc mdplPlain
    inc si
    mov bx, di
mdplCodeCopy:
    mov al, ds:[si]
    cmp al, C_CR
    je  mdplCodeClose
    cmp al, '`'
    je  mdplCodeClose
    mov es:[di], al
    inc si
    inc di
    jmp mdplCodeCopy
mdplCodeClose:
    cmp byte ptr ds:[si], '`'
    jne mdplCodeRun
    inc si
mdplCodeRun:
    mov ax, MD_STYLE_CODE
    call MDAddRun
    jmp mdplInline

mdplBoldStar:
    cmp al, '*'
    jne mdplBoldUnder
    cmp byte ptr ds:[si+1], '*'
    jne mdplItalicStar
    mov cx, 2
    call MDHasClosing
    LONG jnc mdplPlain
    add si, 2
    mov bx, di
mdplBoldStarCopy:
    cmp byte ptr ds:[si], C_CR
    je  mdplBoldStarRun
    cmp byte ptr ds:[si], '*'
    jne mdplBoldStarChar
    cmp byte ptr ds:[si+1], '*'
    je  mdplBoldStarClose
mdplBoldStarChar:
    mov al, ds:[si]
    mov es:[di], al
    inc si
    inc di
    jmp mdplBoldStarCopy
mdplBoldStarClose:
    add si, 2
mdplBoldStarRun:
    mov ax, MD_STYLE_BOLD
    call MDAddRun
    jmp mdplInline

mdplBoldUnder:
    cmp al, '_'
    LONG jne mdplLink
    cmp byte ptr ds:[si+1], '_'
    jne mdplItalicUnder
    mov cx, 2
    call MDHasClosing
    LONG jnc mdplPlain
    add si, 2
    mov bx, di
mdplBoldUnderCopy:
    cmp byte ptr ds:[si], C_CR
    je  mdplBoldUnderRun
    cmp byte ptr ds:[si], '_'
    jne mdplBoldUnderChar
    cmp byte ptr ds:[si+1], '_'
    je  mdplBoldUnderClose
mdplBoldUnderChar:
    mov al, ds:[si]
    mov es:[di], al
    inc si
    inc di
    jmp mdplBoldUnderCopy
mdplBoldUnderClose:
    add si, 2
mdplBoldUnderRun:
    mov ax, MD_STYLE_BOLD
    call MDAddRun
    jmp mdplInline

mdplItalicStar:
    mov cx, 1
    call MDHasClosing
    LONG jnc mdplPlain
    inc si
    mov bx, di
mdplItalicStarCopy:
    cmp byte ptr ds:[si], C_CR
    je  mdplItalicStarRun
    cmp byte ptr ds:[si], '*'
    je  mdplItalicStarClose
    mov al, ds:[si]
    mov es:[di], al
    inc si
    inc di
    jmp mdplItalicStarCopy
mdplItalicStarClose:
    inc si
mdplItalicStarRun:
    mov ax, MD_STYLE_ITALIC
    call MDAddRun
    jmp mdplInline

mdplItalicUnder:
    mov cx, 1
    call MDHasClosing
    LONG jnc mdplPlain
    inc si
    mov bx, di
mdplItalicUnderCopy:
    cmp byte ptr ds:[si], C_CR
    je  mdplItalicUnderRun
    cmp byte ptr ds:[si], '_'
    je  mdplItalicUnderClose
    mov al, ds:[si]
    mov es:[di], al
    inc si
    inc di
    jmp mdplItalicUnderCopy
mdplItalicUnderClose:
    inc si
mdplItalicUnderRun:
    mov ax, MD_STYLE_ITALIC
    call MDAddRun
    jmp mdplInline

mdplLink:
    cmp al, '['
    jne mdplPlain
    call MDHasLink
    jnc mdplPlain
    push si
    inc si
    mov bx, di
mdplLinkLabel:
    cmp byte ptr ds:[si], C_CR
    je  mdplLinkFail
    cmp byte ptr ds:[si], ']'
    je  mdplLinkAfterLabel
    mov al, ds:[si]
    mov es:[di], al
    inc si
    inc di
    jmp mdplLinkLabel
mdplLinkAfterLabel:
    cmp byte ptr ds:[si+1], '('
    jne mdplLinkFail
    add si, 2
    mov byte ptr es:[di], ' '
    inc di
    mov byte ptr es:[di], '('
    inc di
mdplLinkURL:
    cmp byte ptr ds:[si], C_CR
    je  mdplLinkFail
    cmp byte ptr ds:[si], ')'
    je  mdplLinkDone
    mov al, ds:[si]
    mov es:[di], al
    inc si
    inc di
    jmp mdplLinkURL
mdplLinkDone:
    inc si
    mov byte ptr es:[di], ')'
    inc di
    pop ax
    jmp mdplInline
mdplLinkFail:
    pop si
    mov di, bx
    mov al, ds:[si]

mdplPlain:
    mov es:[di], al
    inc si
    inc di
    jmp mdplInline

mdplEndLine:
    cmp word ptr ds:[MD_quote], 0
    jz  mdplNoQuoteEnd
    mov byte ptr es:[di], '"'
    inc di
mdplNoQuoteEnd:
    mov ds:[MD_textEnd], di
    mov byte ptr es:[di], C_CR
    inc di

    cmp word ptr ds:[MD_headingLevel], 0
    jz  mdplDone
    mov bx, ds:[MD_headingStart]
    mov di, ds:[MD_textEnd]
    mov ax, MD_STYLE_BOLD
    call MDAddRun
mdplDone:
    mov cx, di
    .leave
    ret
MDParseLine endp

;
; Return carry set if the complete line is a Markdown horizontal rule.
; Only '-', '_' and '*' are accepted, with optional spaces or tabs.
;
MDIsHRule proc near uses ax,bx,cx,si
    .enter
    clr si
    clr bx
    clr cx
mdihrLoop:
    mov al, ds:[si]
    cmp al, C_CR
    je  mdihrDone
    cmp al, ' '
    je  mdihrNext
    cmp al, C_TAB
    je  mdihrNext
    tst bl
    jnz mdihrMatch
    cmp al, '-'
    je  mdihrSet
    cmp al, '_'
    je  mdihrSet
    cmp al, '*'
    jne mdihrNo
mdihrSet:
    mov bl, al
    jmp mdihrCount
mdihrMatch:
    cmp al, bl
    jne mdihrNo
mdihrCount:
    inc cx
mdihrNext:
    inc si
    jmp mdihrLoop
mdihrDone:
    cmp cx, 3
    jb  mdihrNo
    stc
    .leave
    ret
mdihrNo:
    clc
    .leave
    ret
MDIsHRule endp

;
; Input: ds:si points at an opening delimiter, AL is its character and
; CX is its width. Return carry set only when a matching closing delimiter
; occurs before the line terminator.
;
MDHasClosing proc near uses ax,bx,di,si
    .enter
    mov bl, al
    mov di, si
    add di, cx
mdhcLoop:
    mov al, ds:[di]
    cmp al, C_CR
    je  mdhcNo
    cmp al, bl
    jne mdhcNext
    cmp cx, 1
    je  mdhcYes
    cmp byte ptr ds:[di+1], bl
    je  mdhcYes
mdhcNext:
    inc di
    jmp mdhcLoop
mdhcYes:
    stc
    .leave
    ret
mdhcNo:
    clc
    .leave
    ret
MDHasClosing endp

;
; Return carry set for a complete [label](url) sequence on this line.
;
MDHasLink proc near uses ax,bx,di,si
    .enter
    mov di, si
    inc di
mdhlLabel:
    mov al, ds:[di]
    cmp al, C_CR
    je  mdhlNo
    cmp al, ']'
    je  mdhlAfterLabel
    inc di
    jmp mdhlLabel
mdhlAfterLabel:
    cmp byte ptr ds:[di+1], '('
    jne mdhlNo
    add di, 2
mdhlURL:
    mov al, ds:[di]
    cmp al, C_CR
    je  mdhlNo
    cmp al, ')'
    je  mdhlYes
    inc di
    jmp mdhlURL
mdhlYes:
    stc
    .leave
    ret
mdhlNo:
    clc
    .leave
    ret
MDHasLink endp

; BX=start, DI=end, AX=style
MDAddRun proc near uses cx,dx,si
    .enter
    cmp bx, di
    jae mdarDone
    mov cx, ds:[MD_runCount]
    cmp cx, MD_MAX_RUNS
    jae mdarDone
    mov si, cx
    shl si, 1
    mov dx, si
    shl si, 1
    shl si, 1                       ; *8
    add si, dx                       ; *10
    add si, MD_runs
    mov ds:[si].MDR_startLo, bx
    clr ds:[si].MDR_startHi
    mov ds:[si].MDR_endLo, di
    clr ds:[si].MDR_endHi
    mov ds:[si].MDR_style, ax
    inc word ptr ds:[MD_runCount]
mdarDone:
    .leave
    ret
MDAddRun endp

MDGetTextSize proc near uses bx,si,di
    .enter
    movdw bxsi, ds:[MD_textObj]
    mov ax, MSG_VIS_TEXT_GET_TEXT_SIZE
    mov di, mask MF_CALL
    push ds
    call ObjMessage                  ; documented return is dx:ax
    pop ds
    mov ds:[MD_baseLo], ax
    mov ds:[MD_baseHi], dx
    .leave
    ret
MDGetTextSize endp

MDApplyRuns proc near uses ax,bx,cx,dx,si,di,bp
    .enter
    clr si
mdarLoop:
    cmp si, ds:[MD_runCount]
    jae mdarHeading
    mov ax, si
    shl ax, 1
    mov di, ax
    shl ax, 1
    shl ax, 1
    add ax, di
    mov di, ax
    add di, MD_runs

    mov ax, ds:[di].MDR_startLo
    mov dx, ds:[di].MDR_startHi
    add ax, ds:[MD_baseLo]
    adc dx, ds:[MD_baseHi]
    mov ds:[MD_absStartLo], ax
    mov ds:[MD_absStartHi], dx
    mov ax, ds:[di].MDR_endLo
    mov dx, ds:[di].MDR_endHi
    add ax, ds:[MD_baseLo]
    adc dx, ds:[MD_baseHi]
    mov ds:[MD_absEndLo], ax
    mov ds:[MD_absEndHi], dx

    test ds:[di].MDR_style, MD_STYLE_CODE
    jz   mdarStyle
    call MDSetMonoRange
mdarStyle:
    mov cx, ds:[di].MDR_style
    and cx, MD_STYLE_BOLD or MD_STYLE_ITALIC
    jcxz mdarNext
    call MDSetStyleRange
mdarNext:
    inc si
    jmp mdarLoop

mdarHeading:
    cmp word ptr ds:[MD_headingLevel], 0
    jz  mdarQuote
    call MDSetHeadingSize
mdarQuote:
    cmp word ptr ds:[MD_quote], 0
    jz  mdarDone
    mov cx, MD_STYLE_ITALIC
    mov ax, ds:[MD_baseLo]
    mov ds:[MD_absStartLo], ax
    mov ax, ds:[MD_baseHi]
    mov ds:[MD_absStartHi], ax
    mov ax, ds:[MD_baseLo]
    mov dx, ds:[MD_baseHi]
    add ax, ds:[MD_currentLineLength]
    adc dx, 0
    mov ds:[MD_absEndLo], ax
    mov ds:[MD_absEndHi], dx
    call MDSetStyleRange
mdarDone:
    .leave
    ret
MDApplyRuns endp

MDSetStyleRange proc near uses ax,bx,dx,si,di,bp
    .enter
    sub sp, size VisTextSetTextStyleParams
    mov bp, sp
    mov ax, ds:[MD_absStartLo]
    mov ss:[bp].VTSTSP_range.VTR_start.low, ax
    mov ax, ds:[MD_absStartHi]
    mov ss:[bp].VTSTSP_range.VTR_start.high, ax
    mov ax, ds:[MD_absEndLo]
    mov ss:[bp].VTSTSP_range.VTR_end.low, ax
    mov ax, ds:[MD_absEndHi]
    mov ss:[bp].VTSTSP_range.VTR_end.high, ax
    clr ax
    test cx, MD_STYLE_BOLD
    jz  mdssNoBold
    ornf ax, mask TS_BOLD
mdssNoBold:
    test cx, MD_STYLE_ITALIC
    jz  mdssNoItalic
    ornf ax, mask TS_ITALIC
mdssNoItalic:
    mov ss:[bp].VTSTSP_styleBitsToSet, ax
    clr ss:[bp].VTSTSP_styleBitsToClear
    clr ss:[bp].VTSTSP_extendedBitsToSet
    clr ss:[bp].VTSTSP_extendedBitsToClear
    movdw bxsi, ds:[MD_textObj]
    mov ax, MSG_VIS_TEXT_SET_TEXT_STYLE
    mov dx, size VisTextSetTextStyleParams
    mov di, mask MF_STACK
    push ds
    call ObjMessage
    pop ds
    add sp, size VisTextSetTextStyleParams
    .leave
    ret
MDSetStyleRange endp

MDSetMonoRange proc near uses ax,bx,dx,si,di,bp
    .enter
    sub sp, size VisTextSetFontIDParams
    mov bp, sp
    mov ax, ds:[MD_absStartLo]
    mov ss:[bp].VTSFIDP_range.VTR_start.low, ax
    mov ax, ds:[MD_absStartHi]
    mov ss:[bp].VTSFIDP_range.VTR_start.high, ax
    mov ax, ds:[MD_absEndLo]
    mov ss:[bp].VTSFIDP_range.VTR_end.low, ax
    mov ax, ds:[MD_absEndHi]
    mov ss:[bp].VTSFIDP_range.VTR_end.high, ax
    mov ss:[bp].VTSFIDP_fontID, FID_DTC_URW_MONO
    movdw bxsi, ds:[MD_textObj]
    mov ax, MSG_VIS_TEXT_SET_FONT_ID
    mov dx, size VisTextSetFontIDParams
    mov di, mask MF_STACK
    push ds
    call ObjMessage
    pop ds
    add sp, size VisTextSetFontIDParams
    .leave
    ret
MDSetMonoRange endp

MDSetHeadingSize proc near uses ax,bx,cx,dx,si,di,bp
    .enter
    mov ax, 13
    cmp word ptr ds:[MD_headingLevel], 6
    je  mdshHave
    mov ax, 14
    cmp word ptr ds:[MD_headingLevel], 5
    je  mdshHave
    mov ax, 16
    cmp word ptr ds:[MD_headingLevel], 4
    je  mdshHave
    mov ax, 18
    cmp word ptr ds:[MD_headingLevel], 3
    je  mdshHave
    mov ax, 20
    cmp word ptr ds:[MD_headingLevel], 2
    je  mdshHave
    mov ax, 24
mdshHave:
    sub sp, size VisTextSetPointSizeParams
    mov bp, sp
    mov cx, ds:[MD_baseLo]
    mov ss:[bp].VTSPSP_range.VTR_start.low, cx
    mov cx, ds:[MD_baseHi]
    mov ss:[bp].VTSPSP_range.VTR_start.high, cx
    mov cx, ds:[MD_baseLo]
    mov dx, ds:[MD_baseHi]
    add cx, ds:[MD_currentLineLength]
    adc dx, 0
    mov ss:[bp].VTSPSP_range.VTR_end.low, cx
    mov ss:[bp].VTSPSP_range.VTR_end.high, dx
    mov ss:[bp].VTSPSP_pointSize.WWF_int, ax
    clr ss:[bp].VTSPSP_pointSize.WWF_frac
    movdw bxsi, ds:[MD_textObj]
    mov ax, MSG_VIS_TEXT_SET_POINT_SIZE
    mov dx, size VisTextSetPointSizeParams
    mov di, mask MF_STACK
    push ds
    call ObjMessage
    pop ds
    add sp, size VisTextSetPointSizeParams
    .leave
    ret
MDSetHeadingSize endp

ImportCode ends

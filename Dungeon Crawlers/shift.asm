; ============================================================
;  shift.asm the shifting maze
;  Procs: SetupLevel10, ShiftMaze, ScanNearest, PlaceFar,
;         ResetShiftTimer, CheckShiftTimer
;  Every 10 seconds one of the 25 pool maps replaces the current
;  maze. The player is moved to the nearest floor tile, the exit
;  moves with the map, and the surviving monsters are re-scattered.
;  (included by main.asm - do NOT build this file on its own)
; ============================================================
.data
shiftM     DWORD 0              ; goblins alive at the moment of the shift
shiftD     DWORD 0              ; dragons alive
lastPool   DWORD 99             ; pool map used last (so we never repeat it)
spTries    DWORD 0
oldX       DWORD 0
oldY       DWORD 0
bestDist   DWORD 0
bestX      DWORD 1
bestY      DWORD 1
exitX      DWORD 0
exitY      DWORD 0
scanX      DWORD 0
scanY      DWORD 0
pfTile     BYTE  '.'
pfCount    DWORD 0
pfTries    DWORD 0
pfX        DWORD 0
pfY        DWORD 0
shownSec   DWORD 0
lastShown  DWORD 99

msgShift   BYTE "THE DUNGEON SHIFTS! The maze has been reshuffled...",0
lblShift   BYTE "Maze shifts in: ",0
lblSec     BYTE " s  ",0

.code
; ------------------------------------------------------------
; SetupLevel10 : first load of level 10
;   random pool map, then monsters and items scattered on it
; ------------------------------------------------------------
SetupLevel10 PROC
    mov  eax, POOL_COUNT
    call RandomRange
    mov  lastPool, eax
    add  eax, POOL_BASE
    imul eax, MAP_SIZE
    add  eax, OFFSET mapBank
    mov  esi, eax
    mov  edi, OFFSET mapData
    mov  ecx, MAP_SIZE
    cld
    rep  movsb

    mov  al, 'M'
    mov  ecx, 6
    call PlaceFar
    mov  al, 'D'
    mov  ecx, 3
    call PlaceFar
    mov  al, 'P'
    mov  ecx, 3
    call PlaceFar
    mov  al, '$'
    mov  ecx, 5
    call PlaceFar
    ret
SetupLevel10 ENDP

; ------------------------------------------------------------
; ShiftMaze : swap in a different pool map, keep the player alive
;             and the monsters (by type) in play
; ------------------------------------------------------------
ShiftMaze PROC
    pushad
    mov  shiftM, 0              ; count the monsters still alive
    mov  shiftD, 0
    mov  esi, OFFSET mapData
    mov  ecx, MAP_SIZE
smCount:
    cmp  BYTE PTR [esi], 'M'
    jne  smC2
    inc  shiftM
smC2:
    cmp  BYTE PTR [esi], 'D'
    jne  smC3
    inc  shiftD
smC3:
    inc  esi
    loop smCount

    mov  eax, playerX           ; remember where the player stands
    mov  oldX, eax
    mov  eax, playerY
    mov  oldY, eax
    mov  spTries, 25

smPick:
    mov  eax, POOL_COUNT
    call RandomRange
    cmp  eax, lastPool
    je   smPick                 ; never the same map twice in a row
    mov  lastPool, eax
    add  eax, POOL_BASE
    imul eax, MAP_SIZE
    add  eax, OFFSET mapBank
    mov  esi, eax
    mov  edi, OFFSET mapData
    mov  ecx, MAP_SIZE
    cld
    rep  movsb
    call ScanNearest            ; player -> nearest floor, finds the exit

    mov  eax, playerX           ; the exit must not be right next to us
    sub  eax, exitX
    jge  smAbsX
    neg  eax
smAbsX:
    mov  ecx, playerY
    sub  ecx, exitY
    jge  smAbsY
    neg  ecx
smAbsY:
    add  eax, ecx
    cmp  eax, 6
    jae  smAccept
    dec  spTries
    jnz  smPick                 ; too close: try another map

smAccept:
    mov  edi, OFFSET seenData   ; the new maze is unexplored
    mov  ecx, MAP_SIZE
    xor  eax, eax
    cld
    rep  stosb

    mov  al, 'M'
    mov  ecx, shiftM
    call PlaceFar
    mov  al, 'D'
    mov  ecx, shiftD
    call PlaceFar
    mov  eax, shiftM
    add  eax, shiftD
    mov  enemyCount, eax
    call ResetShiftTimer
    popad
    ret
ShiftMaze ENDP

; ------------------------------------------------------------
; ScanNearest : moves (playerX,playerY) to the floor tile closest
;               to (oldX,oldY) and records the exit position
; ------------------------------------------------------------
ScanNearest PROC
    pushad
    mov  bestDist, 9999
    mov  scanY, 0
snRow:
    mov  scanX, 0
snCol:
    mov  eax, scanX
    mov  ebx, scanY
    call GetTileAt              ; AL = tile
    cmp  al, 'E'
    jne  snNotExit
    mov  ecx, scanX
    mov  exitX, ecx
    mov  ecx, scanY
    mov  exitY, ecx
    jmp  snNext
snNotExit:
    cmp  al, '.'
    jne  snNext
    mov  eax, scanX             ; distance to where the player was
    sub  eax, oldX
    jge  snAbsX
    neg  eax
snAbsX:
    mov  ecx, scanY
    sub  ecx, oldY
    jge  snAbsY
    neg  ecx
snAbsY:
    add  eax, ecx
    cmp  eax, bestDist
    jae  snNext
    mov  bestDist, eax
    mov  eax, scanX
    mov  bestX, eax
    mov  eax, scanY
    mov  bestY, eax
snNext:
    inc  scanX
    cmp  scanX, MAP_WIDTH
    jb   snCol
    inc  scanY
    cmp  scanY, MAP_HEIGHT
    jb   snRow
    mov  eax, bestX
    mov  playerX, eax
    mov  eax, bestY
    mov  playerY, eax
    popad
    ret
ScanNearest ENDP

; ------------------------------------------------------------
; PlaceFar : AL = tile character, ECX = how many to place
;   random floor tiles at least 6 steps (Manhattan) from the player
; ------------------------------------------------------------
PlaceFar PROC
    mov  pfTile, al
    mov  pfCount, ecx
pfNext:
    cmp  pfCount, 0
    je   pfDone
    mov  pfTries, 300
pfTry:
    dec  pfTries
    jz   pfGiveUp
    mov  eax, 18
    call RandomRange
    inc  eax
    mov  pfX, eax               ; x = 1..18
    mov  eax, 13
    call RandomRange
    inc  eax
    mov  pfY, eax               ; y = 1..13
    mov  eax, pfX
    sub  eax, playerX
    jge  pfAbsX
    neg  eax
pfAbsX:
    mov  ecx, pfY
    sub  ecx, playerY
    jge  pfAbsY
    neg  ecx
pfAbsY:
    add  eax, ecx
    cmp  eax, 6
    jb   pfTry                  ; too close to the player
    mov  ebx, pfY
    imul ebx, MAP_WIDTH
    add  ebx, pfX
    cmp  BYTE PTR mapData[ebx], '.'
    jne  pfTry
    mov  al, pfTile
    mov  BYTE PTR mapData[ebx], al
pfGiveUp:
    dec  pfCount
    jmp  pfNext
pfDone:
    ret
PlaceFar ENDP

; ------------------------------------------------------------
; ResetShiftTimer : next reshuffle in SHIFT_MS milliseconds
; ------------------------------------------------------------
ResetShiftTimer PROC
    push eax
    call GetMseconds
    add  eax, SHIFT_MS
    mov  nextShiftTime, eax
    pop  eax
    ret
ResetShiftTimer ENDP

; ------------------------------------------------------------
; CheckShiftTimer : called while idle on level 10
;   - redraws the "Maze shifts in: N s" line once per second
;   - reshuffles the maze when the time is up
; ------------------------------------------------------------
CheckShiftTimer PROC
    pushad
    call GetMseconds
    mov  ebx, nextShiftTime
    sub  ebx, eax               ; EBX = ms remaining (signed)
    cmp  ebx, 60000             ; far too big = the clock wrapped at midnight
    jle  cstOK
    call ResetShiftTimer
    jmp  cstDone
cstOK:
    cmp  ebx, 0
    jg   cstShow

    call ShiftMaze              ; time is up
    call DrawHUD
    call DrawMap
    mov  edx, OFFSET msgShift
    call ShowMessage
    call SndShift
    mov  lastShown, 99
    jmp  cstDone

cstShow:
    mov  eax, ebx               ; seconds left, rounded up
    add  eax, 999
    xor  edx, edx
    mov  ecx, 1000
    div  ecx
    cmp  eax, lastShown
    je   cstDone                ; only redraw when the number changes
    mov  lastShown, eax
    mov  shownSec, eax
    mov  dl, 0
    mov  dh, MSG_ROW + 3
    call Gotoxy
    mov  eax, lightCyan
    call SetTextColor
    mov  edx, OFFSET lblShift
    call WriteString
    mov  eax, shownSec
    call WriteDec
    mov  edx, OFFSET lblSec
    call WriteString
cstDone:
    popad
    ret
CheckShiftTimer ENDP
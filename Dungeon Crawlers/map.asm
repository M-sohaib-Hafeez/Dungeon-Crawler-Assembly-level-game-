; ============================================================
;  map.asm Map Engine
;  Procs: LoadLevel, NextLevel, GetTileAt, SetTileAt, DrawMap,
;         IsVisible, PrintTile, PrintDim, PrintBlank2
;  Maps live in leveldata.asm (mapBank, 50 maps x 300 bytes).
;  (included by main.asm - do NOT build this file on its own)
; ============================================================
EMOJI_COUNT EQU 10

.data
seenData  BYTE MAP_SIZE DUP(0)  ; 1 = tile has been seen (fog of war memory)

drawX     DWORD 0
drawY     DWORD 0
cellIdx   DWORD 0
llTmp     DWORD 0
ptIdx     DWORD 0
tileTmp   BYTE  ' '
ptChar    BYTE  ' '

; ---- emoji for each tile type (UTF-16, two WORDs = one emoji) ----
emojiChars BYTE '@','$','M','D','P','W','A','K','L','E'
emojiData  WORD 0D83Eh,0DDD9h       ; @ player   U+1F9D9
           WORD 0D83Dh,0DCB0h       ; $ gold     U+1F4B0
           WORD 0D83Dh,0DC7Ah       ; M goblin   U+1F47A
           WORD 0D83Dh,0DC09h       ; D dragon   U+1F409
           WORD 0D83Eh,0DDEAh       ; P potion   U+1F9EA
           WORD 0D83Ch,0DFF9h       ; W weapon   U+1F3F9
           WORD 0D83Eh,0DDE5h       ; A armor    U+1F9E5
           WORD 0D83Dh,0DD11h       ; K key      U+1F511
           WORD 0D83Dh,0DEAAh       ; L door     U+1F6AA
           WORD 0D83Ch,0DFC1h       ; E exit     U+1F3C1
emojiWritten DWORD 0

.code
; ------------------------------------------------------------
; LoadLevel : builds the map for 'currentLevel', resets the fog,
;             puts the player at (1,1), counts the monsters,
;             arms the level-10 shift timer
;   level 1       -> bank map 0
;   levels 2..9   -> one of 3 variants (random)
;   level 10      -> random pool map + monsters/items (shift.asm)
; ------------------------------------------------------------
LoadLevel PROC
    pushad
    cld
    mov  edi, OFFSET seenData   ; forget what we have seen
    mov  ecx, MAP_SIZE
    xor  eax, eax
    rep  stosb

    mov  playerX, 1
    mov  playerY, 1

    cmp  currentLevel, MAX_LEVEL
    je   llTen
    xor  eax, eax               ; level 1 = bank map 0
    cmp  currentLevel, 1
    je   llCopy
    mov  eax, currentLevel      ; levels 2..9: 1 + (level-2)*3 + random(0..2)
    sub  eax, 2
    imul eax, 3
    inc  eax
    mov  llTmp, eax
    mov  eax, 3
    call RandomRange
    add  eax, llTmp
llCopy:
    imul eax, MAP_SIZE
    add  eax, OFFSET mapBank
    mov  esi, eax
    mov  edi, OFFSET mapData
    mov  ecx, MAP_SIZE
    cld
    rep  movsb
    jmp  llCountStart
llTen:
    call SetupLevel10           ; shift.asm

llCountStart:
    mov  enemyCount, 0
    mov  esi, OFFSET mapData
    mov  ecx, MAP_SIZE
llCount:
    cmp  BYTE PTR [esi], 'M'
    je   llInc
    cmp  BYTE PTR [esi], 'D'
    jne  llNext
llInc:
    inc  enemyCount
llNext:
    inc  esi
    loop llCount
    call ResetShiftTimer        ; shift.asm
    popad
    ret
LoadLevel ENDP

; ------------------------------------------------------------
; NextLevel : called when gameState = 4 (level complete)
;   next level exists -> bonus, load it, gameState = 0
;   otherwise         -> gameState = 1 (victory)
; ------------------------------------------------------------
NextLevel PROC
    mov  eax, currentLevel
    cmp  eax, MAX_LEVEL
    jae  nlWin
    inc  currentLevel
    mov  gameState, 0
    add  playerGold, 25
    mov  eax, playerMaxHP
    sub  eax, playerHP          ; missing HP
    cmp  eax, 50
    jbe  nlHeal
    mov  eax, 50                ; heal 50 HP (never above the maximum)
nlHeal:
    add  playerHP, eax
    call LoadLevel
    call SndLevel               ; ui.asm
    ret
nlWin:
    mov  gameState, 1
    ret
NextLevel ENDP

; ------------------------------------------------------------
; GetTileAt : in EAX = x, EBX = y     out EAX = tile character
; ------------------------------------------------------------
GetTileAt PROC
    push ecx
    mov  ecx, ebx
    imul ecx, MAP_WIDTH
    add  ecx, eax
    movzx eax, BYTE PTR mapData[ecx]
    pop  ecx
    ret
GetTileAt ENDP

; ------------------------------------------------------------
; SetTileAt : in EAX = x, EBX = y, DL = new tile character
; ------------------------------------------------------------
SetTileAt PROC
    push ecx
    mov  ecx, ebx
    imul ecx, MAP_WIDTH
    add  ecx, eax
    mov  BYTE PTR mapData[ecx], dl
    pop  ecx
    ret
SetTileAt ENDP

; ------------------------------------------------------------
; IsVisible : is cell (drawX, drawY) inside the player's view?
;   out EAX = 1 visible, 0 hidden   (always 1 if fog is off)
; ------------------------------------------------------------
IsVisible PROC
    cmp  fogEnabled, 0
    je   ivYes
    mov  eax, drawX
    sub  eax, playerX
    jge  ivAbsX
    neg  eax
ivAbsX:
    mov  ecx, drawY
    sub  ecx, playerY
    jge  ivAbsY
    neg  ecx
ivAbsY:
    add  eax, ecx               ; Manhattan distance
    cmp  eax, FOG_RADIUS
    jbe  ivYes
    xor  eax, eax
    ret
ivYes:
    mov  eax, 1
    ret
IsVisible ENDP

; ------------------------------------------------------------
; DrawMap : visible cells in colour, remembered cells dimmed
;           (monsters/items are not remembered), unseen cells blank
; ------------------------------------------------------------
DrawMap PROC
    pushad
    mov  drawY, 0
dmRow:
    mov  dl, 0
    mov  dh, BYTE PTR drawY
    add  dh, MAP_TOP
    call Gotoxy
    mov  drawX, 0
dmCol:
    mov  eax, drawX
    mov  ebx, drawY
    call GetTileAt
    mov  tileTmp, al
    mov  ecx, drawY
    imul ecx, MAP_WIDTH
    add  ecx, drawX
    mov  cellIdx, ecx
    call IsVisible
    cmp  eax, 0
    je   dmHidden

    ; ----- visible -----
    mov  ecx, cellIdx
    mov  BYTE PTR seenData[ecx], 1
    mov  al, tileTmp
    mov  ecx, drawX
    cmp  ecx, playerX
    jne  dmPrint
    mov  ecx, drawY
    cmp  ecx, playerY
    jne  dmPrint
    mov  al, '@'                ; player is standing here
dmPrint:
    call PrintTile
    jmp  dmNext

    ; ----- hidden by fog -----
dmHidden:
    mov  ecx, cellIdx
    mov  al, ' '                ; never seen: blank
    cmp  BYTE PTR seenData[ecx], 0
    je   dmDim
    mov  al, tileTmp            ; seen before: remember walls and the exit
    cmp  al, '#'
    je   dmDim
    cmp  al, 'E'
    je   dmDim
    mov  al, '.'                ; everything else is forgotten
dmDim:
    call PrintDim

dmNext:
    inc  drawX
    cmp  drawX, MAP_WIDTH
    jb   dmCol
    inc  drawY
    cmp  drawY, MAP_HEIGHT
    jb   dmRow
    popad
    ret
DrawMap ENDP

; ------------------------------------------------------------
; PrintBlank2 : two spaces in the current colours
;               (a solid 2-column "block" when the background is set)
; ------------------------------------------------------------
PrintBlank2 PROC
    mov  al, ' '
    call WriteChar
    mov  al, ' '
    call WriteChar
    ret
PrintBlank2 ENDP

; ------------------------------------------------------------
; PrintTile : AL = tile character, draws one 2-column cell
;   '#'            -> solid brown block (background colour only)
;   emoji mode on  -> emoji via WriteConsoleW (exactly 2 columns wide)
;   emoji mode off -> coloured letter + space
; ------------------------------------------------------------
PrintTile PROC
    mov  ptChar, al
    cmp  al, '#'
    jne  ptNotWall
    mov  eax, brown SHL 4       ; background = brown, no text
    call SetTextColor
    call PrintBlank2
    ret

ptNotWall:
    cmp  emojiMode, 0
    je   ptLetter
    xor  ecx, ecx
ptFind:
    cmp  ecx, EMOJI_COUNT
    jae  ptLetter               ; no emoji for this tile (e.g. floor)
    mov  al, emojiChars[ecx]
    cmp  al, ptChar
    je   ptEmoji
    inc  ecx
    jmp  ptFind
ptEmoji:
    mov  ptIdx, ecx
    mov  eax, white
    call SetTextColor
    mov  ecx, ptIdx
    mov  esi, OFFSET emojiData
    lea  esi, [esi + ecx*4]     ; 2 WORDs per emoji
    INVOKE WriteConsoleW, consoleOut, esi, 2, OFFSET emojiWritten, 0
    ret

ptLetter:                       ; ---- coloured letters ----
    mov  eax, lightGray         ; floor / default
    cmp  ptChar, '$'
    jne  ptC2
    mov  eax, yellow
ptC2:
    cmp  ptChar, 'M'
    jne  ptC3
    mov  eax, lightRed
ptC3:
    cmp  ptChar, 'D'
    jne  ptC4
    mov  eax, red
ptC4:
    cmp  ptChar, 'E'
    jne  ptC5
    mov  eax, lightGreen
ptC5:
    cmp  ptChar, 'P'
    jne  ptC6
    mov  eax, lightMagenta
ptC6:
    cmp  ptChar, '@'
    jne  ptC7
    mov  eax, lightCyan
ptC7:
    cmp  ptChar, 'W'
    jne  ptC8
    mov  eax, green
ptC8:
    cmp  ptChar, 'A'
    jne  ptC9
    mov  eax, cyan
ptC9:
    cmp  ptChar, 'K'
    jne  ptC10
    mov  eax, white
ptC10:
    cmp  ptChar, 'L'
    jne  ptC11
    mov  eax, lightBlue
ptC11:
    call SetTextColor
    mov  al, ptChar
    call WriteChar
    mov  al, ' '
    call WriteChar
    ret
PrintTile ENDP

; ------------------------------------------------------------
; PrintDim : AL = ' ' (never seen), '#', 'E', or anything else
;   unseen -> black   wall -> dark grey block
;   exit   -> normal exit tile   other -> dim floor dot
; ------------------------------------------------------------
PrintDim PROC
    cmp  al, '#'
    jne  pdNotWall
    mov  eax, gray SHL 4        ; remembered wall = dark grey block
    call SetTextColor
    call PrintBlank2
    ret
pdNotWall:
    cmp  al, 'E'
    jne  pdNotExit
    call PrintTile              ; AL is still 'E'
    ret
pdNotExit:
    cmp  al, ' '
    je   pdUnseen
    mov  eax, gray              ; remembered floor: dim dot
    call SetTextColor
    mov  al, '.'
    call WriteChar
    mov  al, ' '
    call WriteChar
    ret
pdUnseen:
    xor  eax, eax               ; black on black
    call SetTextColor
    call PrintBlank2
    ret
PrintDim ENDP
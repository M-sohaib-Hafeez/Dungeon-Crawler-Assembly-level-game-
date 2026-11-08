; ============================================================
;  enemy.asm Enemy AI (BFS chase) & Statistics
;  Procs: MoveEnemies, BuildDistMap, BdTry, ChooseStep, CsTry,
;         CheckWinCondition, CalcScore
;  (included by main.asm - do NOT build this file on its own)
; ============================================================
.data
enIdx      DWORD 0
enX        DWORD 0
enY        DWORD 0
newX       DWORD 0
newY       DWORD 0
enChar     BYTE  'M'            ; type of the monster being moved

distMap    BYTE  MAP_SIZE DUP(255)   ; BFS distance from the player (255 = unreachable)
bfsQueue   DWORD MAP_SIZE DUP(0)
bfsHead    DWORD 0
bfsTail    DWORD 0
csDir      DWORD 4              ; chosen direction: 0 up 1 down 2 left 3 right 4 none

.code
; ------------------------------------------------------------
; MoveEnemies : every monster takes one step.
;   - a BFS distance map from the player is built first
;   - path to player <= CHASE_RANGE  -> step along the shortest path
;   - otherwise                      -> random step / stay
;   - dragons only act every other turn
;   - a monster that steps onto the player starts combat (ambush)
;   Moved monsters are marked lowercase ('m'/'d') so they are not
;   moved twice in one scan; they are restored at the end.
; ------------------------------------------------------------
MoveEnemies PROC
    pushad
    call BuildDistMap
    mov  enIdx, 0

meScan:
    cmp  enIdx, MAP_SIZE
    jae  meFinish
    mov  esi, enIdx
    mov  al, BYTE PTR mapData[esi]
    cmp  al, 'M'
    je   meIsMon
    cmp  al, 'D'
    jne  meNext
meIsMon:
    mov  enChar, al
    cmp  al, 'D'                ; dragons are slow
    jne  meGo
    mov  eax, 2
    call RandomRange
    cmp  eax, 0
    je   meNext

meGo:
    mov  eax, enIdx             ; index -> (x, y)
    xor  edx, edx
    mov  ecx, MAP_WIDTH
    div  ecx                    ; EAX = y, EDX = x
    mov  enY, eax
    mov  enX, edx
    mov  eax, enX
    mov  newX, eax
    mov  eax, enY
    mov  newY, eax

    mov  esi, enIdx             ; close enough to chase?
    movzx eax, BYTE PTR distMap[esi]
    cmp  eax, CHASE_RANGE
    ja   meRandom
    call ChooseStep             ; sets newX/newY to the best neighbour
    mov  eax, newX
    cmp  eax, enX
    jne  meTry
    mov  eax, newY
    cmp  eax, enY
    jne  meTry
    jmp  meNext                 ; no better step: stay

    ; --- random wandering ---
meRandom:
    mov  eax, 5
    call RandomRange            ; 0 up, 1 down, 2 left, 3 right, 4 stay
    cmp  eax, 0
    je   meUp
    cmp  eax, 1
    je   meDown
    cmp  eax, 2
    je   meLeft
    cmp  eax, 3
    je   meRight
    jmp  meNext
meUp:
    dec  newY
    jmp  meTry
meDown:
    inc  newY
    jmp  meTry
meLeft:
    dec  newX
    jmp  meTry
meRight:
    inc  newX

meTry:
    mov  eax, newX              ; bounds check (negative = huge unsigned)
    cmp  eax, MAP_WIDTH
    jae  meNext
    mov  eax, newY
    cmp  eax, MAP_HEIGHT
    jae  meNext

    ; --- stepping onto the player = ambush ---
    mov  eax, newX
    cmp  eax, playerX
    jne  meFree
    mov  eax, newY
    cmp  eax, playerY
    jne  meFree
    mov  al, enChar
    call StartCombat            ; EAX: 1 dead, 2 fled, 0 player dead
    cmp  eax, 1
    jne  meNotDead
    mov  eax, enX               ; monster died: remove it from its tile
    mov  ebx, enY
    mov  dl, '.'
    call SetTileAt
    jmp  meFinish
meNotDead:
    cmp  eax, 2
    jne  meFinish               ; player died
    mov  eax, enX               ; player dodged: land 3 tiles from the monster
    mov  ebx, enY
    call DodgeAway              ; player.asm
    jmp  meFinish

    ; --- move only onto empty floor ---
meFree:
    mov  eax, newX
    mov  ebx, newY
    call GetTileAt
    cmp  al, '.'
    jne  meNext
    mov  eax, enX
    mov  ebx, enY
    mov  dl, '.'
    call SetTileAt
    mov  dl, enChar
    or   dl, 20h                ; lowercase = "already moved this turn"
    mov  eax, newX
    mov  ebx, newY
    call SetTileAt

meNext:
    inc  enIdx
    jmp  meScan

meFinish:
    mov  esi, OFFSET mapData    ; restore 'm' -> 'M' and 'd' -> 'D'
    mov  ecx, MAP_SIZE
meFix:
    cmp  BYTE PTR [esi], 'm'
    jne  meFix2
    mov  BYTE PTR [esi], 'M'
meFix2:
    cmp  BYTE PTR [esi], 'd'
    jne  meFixNext
    mov  BYTE PTR [esi], 'D'
meFixNext:
    inc  esi
    loop meFix
    popad
    ret
MoveEnemies ENDP

; ------------------------------------------------------------
; BuildDistMap : breadth-first search outward from the player.
;   distMap[i] = number of steps from the player to cell i
;   Walls and locked doors block; everything else is passable.
; ------------------------------------------------------------
BuildDistMap PROC
    pushad
    cld
    mov  edi, OFFSET distMap
    mov  ecx, MAP_SIZE
    mov  al, 255
    rep  stosb                  ; everything unreachable

    mov  eax, playerY
    imul eax, MAP_WIDTH
    add  eax, playerX           ; start = player's cell
    mov  BYTE PTR distMap[eax], 0
    mov  bfsQueue[0], eax
    mov  bfsHead, 0
    mov  bfsTail, 1

bdLoop:
    mov  eax, bfsHead
    cmp  eax, bfsTail
    jae  bdDone
    mov  esi, bfsQueue[eax*4]   ; current cell
    inc  bfsHead
    movzx edi, BYTE PTR distMap[esi]
    inc  edi                    ; distance given to the neighbours

    mov  ebx, esi               ; up
    sub  ebx, MAP_WIDTH
    call BdTry
    mov  ebx, esi               ; down
    add  ebx, MAP_WIDTH
    call BdTry
    mov  ebx, esi               ; left
    dec  ebx
    call BdTry
    mov  ebx, esi               ; right
    inc  ebx
    call BdTry
    jmp  bdLoop
bdDone:
    popad
    ret
BuildDistMap ENDP

; BdTry : EBX = neighbour cell, EDI = distance to give it
BdTry PROC
    cmp  ebx, MAP_SIZE
    jae  btRet                  ; off the map
    cmp  BYTE PTR distMap[ebx], 255
    jne  btRet                  ; already reached
    mov  al, BYTE PTR mapData[ebx]
    cmp  al, '#'
    je   btRet
    cmp  al, 'L'
    je   btRet
    mov  eax, edi
    mov  BYTE PTR distMap[ebx], al
    mov  eax, bfsTail
    mov  bfsQueue[eax*4], ebx
    inc  bfsTail
btRet:
    ret
BdTry ENDP

; ------------------------------------------------------------
; ChooseStep : looks at the 4 neighbours of (enX,enY) and moves
;              (newX,newY) to the one closest to the player.
;              A neighbour must be floor, or be the player's cell.
;              If none is closer, newX/newY stay unchanged.
; ------------------------------------------------------------
ChooseStep PROC
    pushad
    mov  csDir, 4
    mov  esi, enY
    imul esi, MAP_WIDTH
    add  esi, enX               ; my cell
    movzx edi, BYTE PTR distMap[esi]   ; best distance so far = mine

    mov  ebx, esi
    sub  ebx, MAP_WIDTH
    mov  ecx, 0
    call CsTry
    mov  ebx, esi
    add  ebx, MAP_WIDTH
    mov  ecx, 1
    call CsTry
    mov  ebx, esi
    dec  ebx
    mov  ecx, 2
    call CsTry
    mov  ebx, esi
    inc  ebx
    mov  ecx, 3
    call CsTry

    cmp  csDir, 0
    jne  csNotUp
    dec  newY
    jmp  csDone
csNotUp:
    cmp  csDir, 1
    jne  csNotDown
    inc  newY
    jmp  csDone
csNotDown:
    cmp  csDir, 2
    jne  csNotLeft
    dec  newX
    jmp  csDone
csNotLeft:
    cmp  csDir, 3
    jne  csDone
    inc  newX
csDone:
    popad
    ret
ChooseStep ENDP

; CsTry : EBX = neighbour cell, ECX = direction code,
;         EDI = best distance so far (updated if this one is better)
CsTry PROC
    cmp  ebx, MAP_SIZE
    jae  cstNo
    movzx eax, BYTE PTR distMap[ebx]
    cmp  eax, edi
    jae  cstNo                  ; not closer than the best so far
    cmp  eax, 0
    je   cstOK                  ; distance 0 = the player's cell
    cmp  BYTE PTR mapData[ebx], '.'
    jne  cstNo                  ; can't walk onto items / other monsters
cstOK:
    mov  edi, eax
    mov  csDir, ecx
cstNo:
    ret
CsTry ENDP

; ------------------------------------------------------------
; CheckWinCondition : recount monsters; none left -> level complete
; ------------------------------------------------------------
CheckWinCondition PROC
    pushad
    mov  esi, OFFSET mapData
    mov  ecx, MAP_SIZE
    xor  ebx, ebx
cwLoop:
    cmp  BYTE PTR [esi], 'M'
    je   cwInc
    cmp  BYTE PTR [esi], 'D'
    jne  cwNext
cwInc:
    inc  ebx
cwNext:
    inc  esi
    loop cwLoop
    mov  enemyCount, ebx
    cmp  ebx, 0
    jne  cwDone
    mov  gameState, 4           ; all monsters dead: level complete
cwDone:
    popad
    ret
CheckWinCondition ENDP

; ------------------------------------------------------------
; CalcScore : EAX = gold + kills*25 + remaining HP + level*100
; ------------------------------------------------------------
CalcScore PROC
    mov  eax, kills
    imul eax, 25
    add  eax, playerGold
    add  eax, playerHP
    mov  ecx, currentLevel
    imul ecx, 100
    add  eax, ecx
    ret
CalcScore ENDP
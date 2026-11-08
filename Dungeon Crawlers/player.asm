; ============================================================
;  player.asm Player Movement, Pickups, Doors
;  Procs: MovePlayer, CheckTile, ClearPlayerTile
;  (included by main.asm - do NOT build this file on its own)
; ============================================================
.data
prevX        DWORD 1
prevY        DWORD 1
msgWall      BYTE "Ouch! A solid wall blocks your way.",0
msgLocked    BYTE "The door is locked. Find a key (K)!",0
msgUnlock    BYTE "You unlock the door with your key!",0
msgGold      BYTE "You found gold! (+10)",0
msgPotionUp  BYTE "You picked up a healing potion!",0
msgKeyUp     BYTE "You picked up a key!",0
msgWeaponUp  BYTE "You found a better weapon! (+3 attack)",0
msgArmorUp   BYTE "You found armor! (monsters hit 2 less)",0

; ---- DodgeAway working variables ----
dgMX         DWORD 0            ; monster position
dgMY         DWORD 0
dgD          DWORD 3            ; wanted distance from the monster
dgCnt        DWORD 0
dgPick       DWORD 0
dgMode       DWORD 0            ; 0 = count candidates, 1 = place on the chosen one
dgX          DWORD 0
dgY          DWORD 0

.code
; ------------------------------------------------------------
; MovePlayer : AL = key (w/a/s/d)
;   returns EAX = 1 if the player moved (turn used), 0 if blocked
; ------------------------------------------------------------
MovePlayer PROC
    movzx ecx, al
    mov  eax, playerX
    mov  ebx, playerY

    cmp  cl, 'w'
    jne  mpS
    dec  ebx
    jmp  mpTry
mpS:
    cmp  cl, 's'
    jne  mpA
    inc  ebx
    jmp  mpTry
mpA:
    cmp  cl, 'a'
    jne  mpD
    dec  eax
    jmp  mpTry
mpD:
    cmp  cl, 'd'
    jne  mpNone
    inc  eax

mpTry:                          ; (EAX,EBX) = wanted position
    push eax
    push ebx
    call GetTileAt              ; EAX = tile at wanted position
    mov  dl, al
    pop  ebx
    pop  eax
    cmp  dl, '#'
    je   mpBlocked
    cmp  dl, 'L'
    jne  mpCommit

    ; ----- locked door -----
    cmp  playerKeys, 0
    je   mpLocked
    dec  playerKeys
    mov  dl, '.'
    call SetTileAt              ; open the door (EAX,EBX = door position)
    mov  edx, OFFSET msgUnlock
    call ShowMessage
    call SndDoor
    mov  dl, '.'                ; we now step onto plain floor

mpCommit:
    ; remember where we were (needed if we flee from a fight)
    mov  ecx, playerX
    mov  prevX, ecx
    mov  ecx, playerY
    mov  prevY, ecx

    mov  playerX, eax
    mov  playerY, ebx
    mov  al, dl
    call CheckTile              ; react to what we stepped on
    mov  eax, 1
    ret

mpLocked:
    mov  edx, OFFSET msgLocked
    call ShowMessage
    jmp  mpNone

mpBlocked:
    mov  edx, OFFSET msgWall
    call ShowMessage
mpNone:
    xor  eax, eax
    ret
MovePlayer ENDP

; ------------------------------------------------------------
; CheckTile : AL = tile the player just stepped on
; ------------------------------------------------------------
CheckTile PROC
    cmp  al, '$'
    je   ctGold
    cmp  al, 'P'
    je   ctPotion
    cmp  al, 'K'
    je   ctKey
    cmp  al, 'W'
    je   ctWeapon
    cmp  al, 'A'
    je   ctArmor
    cmp  al, 'M'
    je   ctMonster
    cmp  al, 'D'
    je   ctMonster
    cmp  al, 'E'
    je   ctExit
    ret

ctGold:
    add  playerGold, 10
    call ClearPlayerTile
    mov  edx, OFFSET msgGold
    call ShowMessage
    call SndPickup
    ret

ctPotion:
    inc  playerPotions
    call ClearPlayerTile
    mov  edx, OFFSET msgPotionUp
    call ShowMessage
    call SndPickup
    ret

ctKey:
    inc  playerKeys
    call ClearPlayerTile
    mov  edx, OFFSET msgKeyUp
    call ShowMessage
    call SndPickup
    ret

ctWeapon:
    add  weaponBonus, WEAPON_BONUS
    call ClearPlayerTile
    mov  edx, OFFSET msgWeaponUp
    call ShowMessage
    call SndPickup
    ret

ctArmor:
    add  armorBonus, ARMOR_BONUS
    call ClearPlayerTile
    mov  edx, OFFSET msgArmorUp
    call ShowMessage
    call SndPickup
    ret

ctMonster:
    call StartCombat            ; AL = monster type. EAX: 1 dead, 2 fled, 0 player dead
    cmp  eax, 1
    je   ctWon
    cmp  eax, 2
    je   ctFled
    ret                         ; player died: gameState was set by combat
ctWon:
    call ClearPlayerTile        ; remove the dead monster
    ret
ctFled:
    mov  eax, playerX           ; we are standing on the monster's tile:
    mov  ebx, playerY           ; dodge past it and land 3 tiles away
    call DodgeAway
    ret

ctExit:
    mov  gameState, 4           ; level complete
    ret
CheckTile ENDP

; ------------------------------------------------------------
; ClearPlayerTile : turn the tile under the player into floor
; ------------------------------------------------------------
ClearPlayerTile PROC
    mov  eax, playerX
    mov  ebx, playerY
    mov  dl, '.'
    call SetTileAt
    ret
ClearPlayerTile ENDP

; ------------------------------------------------------------
; DodgeAway : the player successfully ran away from a monster.
;   in : EAX = monster x, EBX = monster y
;   The player is moved to a random floor tile exactly 3 tiles
;   (Manhattan distance) from the monster - straight through walls
;   and over the monster itself, the path doesn't matter. Only tiles
;   the player can walk to without opening a door are used (so a
;   dodge can never trap you in a locked vault). If no tile is
;   exactly 3 away, 4, 5, ... are tried. Only empty floor ('.') is
;   chosen, so a dodge never triggers a pickup or another fight.
; ------------------------------------------------------------
DodgeAway PROC
    pushad
    mov  dgMX, eax
    mov  dgMY, ebx
    call BuildDistMap           ; enemy.asm: tiles reachable from the player
    mov  dgD, 3
dgTry:
    mov  dgCnt, 0
    mov  dgMode, 0
    call DgScan                 ; count the candidates at this distance
    cmp  dgCnt, 0
    jne  dgChoose
    inc  dgD                    ; none: look a little further away
    cmp  dgD, 14
    jbe  dgTry
    jmp  dgDone                 ; nowhere to go (never happens on our maps)
dgChoose:
    mov  eax, dgCnt
    call RandomRange            ; pick one of them
    mov  dgPick, eax
    mov  dgCnt, 0
    mov  dgMode, 1
    call DgScan                 ; second pass: put the player there
dgDone:
    popad
    ret
DodgeAway ENDP

; DgScan : mode 0 counts, mode 1 teleports the player to candidate #dgPick
DgScan PROC
    pushad
    mov  dgY, 0
dsRow:
    mov  dgX, 0
dsCol:
    mov  eax, dgY
    imul eax, MAP_WIDTH
    add  eax, dgX               ; EAX = cell index
    cmp  BYTE PTR distMap[eax], 255
    je   dsNext                 ; not reachable without a key
    cmp  BYTE PTR mapData[eax], '.'
    jne  dsNext                 ; only empty floor
    mov  eax, dgX               ; Manhattan distance to the monster
    sub  eax, dgMX
    jge  dsAbsX
    neg  eax
dsAbsX:
    mov  ecx, dgY
    sub  ecx, dgMY
    jge  dsAbsY
    neg  ecx
dsAbsY:
    add  eax, ecx
    cmp  eax, dgD
    jne  dsNext
    cmp  dgMode, 0
    jne  dsPlace
    inc  dgCnt
    jmp  dsNext
dsPlace:
    mov  eax, dgCnt
    cmp  eax, dgPick
    jne  dsCount
    mov  eax, dgX
    mov  playerX, eax
    mov  eax, dgY
    mov  playerY, eax
    mov  dgPick, 0FFFFFFFFh     ; done - never match again
dsCount:
    inc  dgCnt
dsNext:
    inc  dgX
    cmp  dgX, MAP_WIDTH
    jb   dsCol
    inc  dgY
    cmp  dgY, MAP_HEIGHT
    jb   dsRow
    popad
    ret
DgScan ENDP
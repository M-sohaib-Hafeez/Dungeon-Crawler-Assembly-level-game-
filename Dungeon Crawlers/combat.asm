; ============================================================
;  combat.asm Turn-Based Combat
;  Procs: StartCombat (wrapper), CombatInner, PlayerAttack,
;         MonsterAttack, ShowCombatStatus
;  Monster types:  M = goblin (weak)   D = dragon (tough)
;  Monsters get stronger every level:
;     HP     +10 % per level after level 1
;     damage +1 per level after level 1
;  (included by main.asm - do NOT build this file on its own)
; ============================================================
.data
monsterHP     DWORD 0
monsterMin    DWORD 3           ; monster damage range
monsterMax    DWORD 9
monsterReward DWORD 15          ; gold for killing it
monsterName   DWORD 0           ; pointer to name string
baseHP        DWORD 0
dmg           DWORD 0
cbKey         BYTE  0
combatT0      DWORD 0           ; time the fight started (for the shift timer)
ccResult      DWORD 0

nameGoblin    BYTE "goblin",0
nameDragon    BYTE "dragon",0

msgEncA       BYTE "*** A ",0
msgEncB       BYTE " blocks your path! ***",0
msgMenu       BYTE "[A]ttack   [P]otion   [R]un  > ",0
msgYouHit     BYTE "You hit the ",0
msgThe        BYTE "The ",0
msgHitsYou    BYTE " hits you for ",0
msgFor        BYTE " for ",0
msgDamage     BYTE " damage!",0
msgCrit       BYTE "CRITICAL HIT! ",0
msgIsDead     BYTE " is defeated! (+",0
msgGoldEnd    BYTE " gold)",0
msgFlee       BYTE "You dodge past it and slip away!",0
msgNoFlee     BYTE "You couldn't get away!",0
msgDied       BYTE "You have been slain...",0
msgYourHP     BYTE "Your HP: ",0
msgMonHP      BYTE "     Monster HP: ",0
msgPotLeft    BYTE "     Potions: ",0

.code
; ------------------------------------------------------------
; StartCombat : AL = monster type ('M' or 'D')
;   returns EAX = 1 monster dead | 2 player fled | 0 player dead
;   Wrapper: the level-10 shift timer is paused while fighting.
; ------------------------------------------------------------
StartCombat PROC
    pushad
    push eax                    ; keep AL (monster type)
    call GetMseconds
    mov  combatT0, eax
    pop  eax
    call CombatInner
    mov  ccResult, eax
    call GetMseconds
    sub  eax, combatT0          ; time spent fighting
    jb   scSkip                 ; (clock wrapped: ignore)
    add  nextShiftTime, eax     ; push the next reshuffle back by that much
scSkip:
    popad
    mov  eax, ccResult
    ret
StartCombat ENDP

CombatInner PROC
    cmp  al, 'D'
    je   scDragon

    ; ----- goblin -----
    mov  monsterMin, 3
    mov  monsterMax, 9
    mov  monsterReward, 15
    mov  monsterName, OFFSET nameGoblin
    mov  eax, 25
    mov  ebx, 40
    jmp  scSpawn
scDragon:
    mov  monsterMin, 6
    mov  monsterMax, 12
    mov  monsterReward, 50
    mov  monsterName, OFFSET nameDragon
    mov  eax, 50
    mov  ebx, 70
scSpawn:
    call RandRange              ; EAX = base HP
    mov  baseHP, eax
    mov  ecx, currentLevel
    dec  ecx                    ; levels above 1
    imul ecx, eax               ; baseHP * (level-1)
    mov  eax, ecx
    xor  edx, edx
    mov  ebx, 10
    div  ebx                    ; ... / 10  = +10 % per level
    add  eax, baseHP
    mov  monsterHP, eax
    mov  eax, currentLevel      ; damage +1 per level
    dec  eax
    add  monsterMin, eax
    add  monsterMax, eax

    call Clrscr
    mov  eax, lightRed
    call SetTextColor
    mov  edx, OFFSET msgEncA
    call WriteString
    mov  edx, monsterName
    call WriteString
    mov  edx, OFFSET msgEncB
    call WriteString
    call Crlf
    call Crlf

cbLoop:
    mov  eax, white
    call SetTextColor
    call ShowCombatStatus
    mov  edx, OFFSET msgMenu
    call WriteString
    call ReadChar
    or   al, 20h
    mov  cbKey, al
    call Crlf
    mov  al, cbKey
    cmp  al, 'a'
    je   cbAttack
    cmp  al, 'p'
    je   cbPotion
    cmp  al, 'r'
    je   cbRun
    jmp  cbLoop

cbAttack:
    call PlayerAttack
    cmp  monsterHP, 0
    jle  cbVictory
    jmp  cbMonsterTurn

cbPotion:
    call UsePotion              ; ui.asm - returns EAX=1 if used
    cmp  eax, 0
    je   cbLoop                 ; nothing happened, ask again
    jmp  cbMonsterTurn

cbRun:
    mov  eax, 2
    call RandomRange            ; 50 % chance
    cmp  eax, 0
    je   cbFled
    mov  edx, OFFSET msgNoFlee
    call WriteString
    call Crlf

cbMonsterTurn:
    call MonsterAttack
    cmp  playerHP, 0
    jle  cbDead
    call Crlf
    jmp  cbLoop

cbVictory:
    dec  enemyCount
    inc  kills
    mov  eax, monsterReward
    add  playerGold, eax
    call SndKill
    mov  eax, lightGreen
    call SetTextColor
    mov  edx, OFFSET msgThe
    call WriteString
    mov  edx, monsterName
    call WriteString
    mov  edx, OFFSET msgIsDead
    call WriteString
    mov  eax, monsterReward
    call WriteDec
    mov  edx, OFFSET msgGoldEnd
    call WriteString
    call Crlf
    call WaitMsg
    call Clrscr
    mov  eax, 1
    ret

cbFled:
    mov  edx, OFFSET msgFlee
    call WriteString
    call Crlf
    call WaitMsg
    call Clrscr
    mov  eax, 2
    ret

cbDead:
    mov  gameState, 2
    mov  eax, lightRed
    call SetTextColor
    mov  edx, OFFSET msgDied
    call WriteString
    call Crlf
    call WaitMsg
    call Clrscr
    xor  eax, eax
    ret
CombatInner ENDP

; ------------------------------------------------------------
; PlayerAttack : 5-15 (+ weapons + attack upgrades), 10 % chance of x2 crit
; ------------------------------------------------------------
PlayerAttack PROC
    mov  eax, 5
    mov  ebx, 15
    call RandRange
    mov  dmg, eax
    call GetTotalAtk            ; shop.asm: weapon pickups + attack upgrades
    add  dmg, eax

    mov  eax, 10
    call RandomRange            ; 0..9
    cmp  eax, 0
    jne  paNoCrit
    shl  dmg, 1                 ; critical hit: x2
    mov  edx, OFFSET msgCrit
    call WriteString
paNoCrit:
    mov  eax, dmg
    sub  monsterHP, eax
    cmp  monsterHP, 0
    jge  paPrint
    mov  monsterHP, 0
paPrint:
    call SndHit
    mov  edx, OFFSET msgYouHit
    call WriteString
    mov  edx, monsterName
    call WriteString
    mov  edx, OFFSET msgFor
    call WriteString
    mov  eax, dmg
    call WriteDec
    mov  edx, OFFSET msgDamage
    call WriteString
    call Crlf
    ret
PlayerAttack ENDP

; ------------------------------------------------------------
; MonsterAttack : random damage in [monsterMin..monsterMax],
;                 reduced by armor (never below 1)
; ------------------------------------------------------------
MonsterAttack PROC
    mov  eax, monsterMin
    mov  ebx, monsterMax
    call RandRange
    mov  dmg, eax
    call GetTotalDef            ; shop.asm: armor pickups + resistance upgrades
    mov  ecx, eax
    mov  eax, dmg
    sub  eax, ecx
    cmp  eax, 1
    jge  maApply
    mov  eax, 1                 ; armor can't block everything
maApply:
    mov  dmg, eax
    sub  playerHP, eax
    cmp  playerHP, 0
    jge  maPrint
    mov  playerHP, 0
maPrint:
    call SndHurt
    mov  edx, OFFSET msgThe
    call WriteString
    mov  edx, monsterName
    call WriteString
    mov  edx, OFFSET msgHitsYou
    call WriteString
    mov  eax, dmg
    call WriteDec
    mov  edx, OFFSET msgDamage
    call WriteString
    call Crlf
    ret
MonsterAttack ENDP

; ------------------------------------------------------------
; ShowCombatStatus : "Your HP: x   Monster HP: y   Potions: z"
; ------------------------------------------------------------
ShowCombatStatus PROC
    mov  edx, OFFSET msgYourHP
    call WriteString
    mov  eax, playerHP
    call WriteDec
    mov  edx, OFFSET msgMonHP
    call WriteString
    mov  eax, monsterHP
    call WriteDec
    mov  edx, OFFSET msgPotLeft
    call WriteString
    mov  eax, playerPotions
    call WriteDec
    call Crlf
    ret
ShowCombatStatus ENDP
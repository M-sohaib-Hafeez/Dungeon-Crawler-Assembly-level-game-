; ============================================================
;  ui.asm HUD, Messages, Inventory, Sound, End Screens
;  Procs: DrawHUD, DrawLegend, ShowMessage, ClearMsgArea,
;         InventoryMenu, UsePotion, GameOverScreen, PlayBeep, Snd*
;  (included by main.asm - do NOT build this file on its own)
; ============================================================
LEGEND_COUNT EQU 9

.data
hudHP        BYTE "HP: ",0
hudGold      BYTE "  |  Gold: ",0
hudPotions   BYTE "  |  Potions: ",0
hudEnemies   BYTE "  |  Enemies left: ",0
hudLevel     BYTE "Level: ",0
hudLevelOf   BYTE "/10",0
hudKeys      BYTE "  |  Keys: ",0
hudAtk       BYTE "  |  ATK +",0
hudDef       BYTE "  |  DEF +",0
hudSound     BYTE "  |  Snd:",0
hudFog       BYTE " Fog:",0
hudEmoji     BYTE " Emoji:",0
txtOn        BYTE "ON ",0
txtOff       BYTE "OFF",0
hudControls  BYTE "WASD move  I inv  B shop  V save  L load  F fog  M snd  E emoji  Q quit",0

; legend: one tile + its name (the tile is drawn with PrintTile, so it
; shows as an emoji or a letter depending on the [E] setting)
legendChars  BYTE "$MDPWAKLE"
legendNames  DWORD OFFSET nmGold, OFFSET nmGoblin, OFFSET nmDragon, OFFSET nmPotion
             DWORD OFFSET nmWeapon, OFFSET nmArmor, OFFSET nmKey, OFFSET nmDoor, OFFSET nmExit
nmGold       BYTE "gold ",0
nmGoblin     BYTE "goblin ",0
nmDragon     BYTE "dragon ",0
nmPotion     BYTE "potion ",0
nmWeapon     BYTE "weapon ",0
nmArmor      BYTE "armor ",0
nmKey        BYTE "key ",0
nmDoor       BYTE "door ",0
nmExit       BYTE "exit",0
legIdx       DWORD 0

blankLine    BYTE 78 DUP(' '),0
msgPtr       DWORD 0

msgInvPrompt BYTE "INVENTORY: press [U] to drink a potion, any other key to close",0
msgNoPotion  BYTE "You have no potions!",0
msgFullHP    BYTE "You are already at full health.",0
msgDrink     BYTE "You drink a potion and recover ",0
msgHPUnit    BYTE " HP.",0
healAmt      DWORD 0
invT0        DWORD 0

artVictory   BYTE 0Dh,0Ah
             BYTE "   ============================",0Dh,0Ah
             BYTE "   =        V I C T O R Y     =",0Dh,0Ah
             BYTE "   ============================",0Dh,0Ah,0Dh,0Ah,0
artDefeat    BYTE 0Dh,0Ah
             BYTE "   ============================",0Dh,0Ah
             BYTE "   =     G A M E   O V E R    =",0Dh,0Ah
             BYTE "   ============================",0Dh,0Ah,0Dh,0Ah,0
artQuit      BYTE 0Dh,0Ah
             BYTE "   ============================",0Dh,0Ah
             BYTE "   =      Y O U   Q U I T     =",0Dh,0Ah
             BYTE "   ============================",0Dh,0Ah,0Dh,0Ah,0

lblLevel     BYTE "   Level reached  : ",0
lblKills     BYTE "   Monsters slain : ",0
lblGold      BYTE "   Gold collected : ",0
lblScore     BYTE "   FINAL SCORE    : ",0
lblHigh      BYTE "   HIGH SCORE     : ",0
msgNewHS     BYTE "   *** NEW HIGH SCORE! ***",0
scoreTmp     DWORD 0

.code
; ------------------------------------------------------------
; DrawHUD : row 0 stats, row 1 level/equipment/toggles,
;           row 2 controls, legend under the message area
; ------------------------------------------------------------
DrawHUD PROC
    pushad

    ; ---------- row 0 ----------
    mov  dl, 0
    mov  dh, 0
    call Gotoxy
    mov  eax, white
    call SetTextColor
    mov  edx, OFFSET blankLine  ; wipe the row first (no stale digits)
    call WriteString
    mov  dl, 0
    mov  dh, 0
    call Gotoxy
    mov  edx, OFFSET hudHP
    call WriteString

    mov  eax, lightGreen        ; HP turns red when low
    cmp  playerHP, 30
    jge  hudColourOK
    mov  eax, lightRed
hudColourOK:
    call SetTextColor
    mov  eax, playerHP
    call WriteDec

    mov  eax, white
    call SetTextColor
    mov  edx, OFFSET hudGold
    call WriteString
    mov  eax, playerGold
    call WriteDec
    mov  edx, OFFSET hudPotions
    call WriteString
    mov  eax, playerPotions
    call WriteDec
    mov  edx, OFFSET hudEnemies
    call WriteString
    mov  eax, enemyCount
    call WriteDec

    ; ---------- row 1 ----------
    mov  dl, 0
    mov  dh, 1
    call Gotoxy
    mov  edx, OFFSET blankLine
    call WriteString
    mov  dl, 0
    mov  dh, 1
    call Gotoxy
    mov  edx, OFFSET hudLevel
    call WriteString
    mov  eax, currentLevel
    call WriteDec
    mov  edx, OFFSET hudLevelOf
    call WriteString
    mov  edx, OFFSET hudKeys
    call WriteString
    mov  eax, playerKeys
    call WriteDec
    mov  edx, OFFSET hudAtk
    call WriteString
    call GetTotalAtk            ; shop.asm
    call WriteDec
    mov  edx, OFFSET hudDef
    call WriteString
    call GetTotalDef            ; shop.asm
    call WriteDec
    mov  edx, OFFSET hudSound
    call WriteString
    mov  edx, OFFSET txtOn
    cmp  soundOn, 0
    jne  hudSndShow
    mov  edx, OFFSET txtOff
hudSndShow:
    call WriteString
    mov  edx, OFFSET hudFog
    call WriteString
    mov  edx, OFFSET txtOn
    cmp  fogEnabled, 0
    jne  hudFogShow
    mov  edx, OFFSET txtOff
hudFogShow:
    call WriteString
    mov  edx, OFFSET hudEmoji
    call WriteString
    mov  edx, OFFSET txtOn
    cmp  emojiMode, 0
    jne  hudEmojiShow
    mov  edx, OFFSET txtOff
hudEmojiShow:
    call WriteString

    ; ---------- row 2: controls ----------
    mov  dl, 0
    mov  dh, 2
    call Gotoxy
    mov  eax, gray
    call SetTextColor
    mov  edx, OFFSET hudControls
    call WriteString

    call DrawLegend
    popad
    ret
DrawHUD ENDP

; ------------------------------------------------------------
; DrawLegend : "<tile> gold <tile> goblin ..." under the map
; ------------------------------------------------------------
DrawLegend PROC
    pushad
    mov  dl, 0
    mov  dh, MSG_ROW + 2
    call Gotoxy
    mov  legIdx, 0
dlLoop:
    cmp  legIdx, LEGEND_COUNT
    jae  dlDone
    mov  ecx, legIdx
    mov  al, legendChars[ecx]
    call PrintTile
    mov  eax, gray
    call SetTextColor
    mov  ecx, legIdx
    mov  edx, legendNames[ecx*4]
    call WriteString
    inc  legIdx
    jmp  dlLoop
dlDone:
    popad
    ret
DrawLegend ENDP

; ------------------------------------------------------------
; ShowMessage : EDX = offset of a 0-terminated string
;               prints it on the message line (clears it first)
;               all registers preserved
; ------------------------------------------------------------
ShowMessage PROC
    pushad
    mov  msgPtr, edx
    mov  eax, white
    call SetTextColor
    mov  dl, 0
    mov  dh, MSG_ROW
    call Gotoxy
    mov  edx, OFFSET blankLine
    call WriteString
    mov  dl, 0
    mov  dh, MSG_ROW
    call Gotoxy
    mov  edx, msgPtr
    call WriteString
    popad
    ret
ShowMessage ENDP

; ------------------------------------------------------------
; ClearMsgArea : blank the two message rows (registers preserved)
; ------------------------------------------------------------
ClearMsgArea PROC
    pushad
    mov  eax, white
    call SetTextColor
    mov  dl, 0
    mov  dh, MSG_ROW
    call Gotoxy
    mov  edx, OFFSET blankLine
    call WriteString
    mov  dl, 0
    mov  dh, MSG_ROW + 1
    call Gotoxy
    mov  edx, OFFSET blankLine
    call WriteString
    popad
    ret
ClearMsgArea ENDP

; ------------------------------------------------------------
; InventoryMenu : returns EAX = 1 if a turn was used
;   (the level-10 shift timer is paused while the menu is open)
; ------------------------------------------------------------
InventoryMenu PROC
    mov  edx, OFFSET msgInvPrompt
    call ShowMessage
    call GetMseconds
    mov  invT0, eax
    call ReadChar
    push eax
    call GetMseconds
    sub  eax, invT0
    jb   invNoFix
    add  nextShiftTime, eax
invNoFix:
    pop  eax
    or   al, 20h
    cmp  al, 'u'
    jne  invClose

    call ClearMsgArea
    mov  dl, 0
    mov  dh, MSG_ROW
    call Gotoxy
    mov  eax, white
    call SetTextColor
    call UsePotion              ; EAX = 1 if potion used
    ret

invClose:
    call ClearMsgArea
    xor  eax, eax
    ret
InventoryMenu ENDP

; ------------------------------------------------------------
; UsePotion : heals up to 25 HP. Prints a message at the cursor.
;   returns EAX = 1 if a potion was used, 0 otherwise
; ------------------------------------------------------------
UsePotion PROC
    cmp  playerPotions, 0
    jne  upHas
    mov  edx, OFFSET msgNoPotion
    call WriteString
    call Crlf
    xor  eax, eax
    ret

upHas:
    mov  eax, playerMaxHP
    cmp  playerHP, eax
    jl   upHeal
    mov  edx, OFFSET msgFullHP
    call WriteString
    call Crlf
    xor  eax, eax
    ret

upHeal:
    dec  playerPotions
    mov  eax, playerMaxHP
    sub  eax, playerHP          ; missing HP
    cmp  eax, 25
    jbe  upApply
    mov  eax, 25                ; heal at most 25
upApply:
    mov  healAmt, eax
    add  playerHP, eax
    call SndPickup
    mov  edx, OFFSET msgDrink
    call WriteString
    mov  eax, healAmt
    call WriteDec
    mov  edx, OFFSET msgHPUnit
    call WriteString
    call Crlf
    mov  eax, 1
    ret
UsePotion ENDP

; ------------------------------------------------------------
; GameOverScreen : banner + statistics + high score
; ------------------------------------------------------------
GameOverScreen PROC
    call Clrscr
    cmp  gameState, 1
    je   goVictory
    cmp  gameState, 2
    je   goDefeat
    mov  eax, white
    call SetTextColor
    mov  edx, OFFSET artQuit
    jmp  goPrint
goVictory:
    mov  eax, lightGreen
    call SetTextColor
    mov  edx, OFFSET artVictory
    jmp  goPrint
goDefeat:
    mov  eax, lightRed
    call SetTextColor
    mov  edx, OFFSET artDefeat
goPrint:
    call WriteString

    mov  eax, white
    call SetTextColor
    mov  edx, OFFSET lblLevel
    call WriteString
    mov  eax, currentLevel
    call WriteDec
    call Crlf
    mov  edx, OFFSET lblKills
    call WriteString
    mov  eax, kills
    call WriteDec
    call Crlf
    mov  edx, OFFSET lblGold
    call WriteString
    mov  eax, playerGold
    call WriteDec
    call Crlf

    mov  eax, yellow
    call SetTextColor
    mov  edx, OFFSET lblScore
    call WriteString
    call CalcScore              ; enemy.asm
    mov  scoreTmp, eax
    call WriteDec
    call Crlf

    mov  eax, scoreTmp          ; new record?
    cmp  eax, highScore
    jbe  goNoRecord
    mov  highScore, eax
    call SaveHighScore          ; save.asm
    mov  eax, lightGreen
    call SetTextColor
    mov  edx, OFFSET msgNewHS
    call WriteString
    call Crlf
goNoRecord:
    mov  eax, white
    call SetTextColor
    mov  edx, OFFSET lblHigh
    call WriteString
    mov  eax, highScore
    call WriteDec
    call Crlf
    call Crlf

    cmp  gameState, 1           ; jingle
    jne  goNotWin
    call SndWin
    jmp  goJingleDone
goNotWin:
    cmp  gameState, 2
    jne  goJingleDone
    call SndLose
goJingleDone:
    call WaitMsg
    ret
GameOverScreen ENDP

; ============================================================
;  SOUND  (Win32 Beep, blocking - keep the durations short)
;  Every proc here preserves all registers.
; ============================================================

; PlayBeep : EAX = frequency (Hz), EBX = duration (ms)
PlayBeep PROC
    cmp  soundOn, 0
    je   pbRet
    pushad
    INVOKE Beep, eax, ebx
    popad
pbRet:
    ret
PlayBeep ENDP

SndHit PROC
    pushad
    mov  eax, 700
    mov  ebx, 50
    call PlayBeep
    popad
    ret
SndHit ENDP

SndHurt PROC
    pushad
    mov  eax, 250
    mov  ebx, 90
    call PlayBeep
    popad
    ret
SndHurt ENDP

SndPickup PROC
    pushad
    mov  eax, 1000
    mov  ebx, 40
    call PlayBeep
    mov  eax, 1400
    mov  ebx, 60
    call PlayBeep
    popad
    ret
SndPickup ENDP

SndDoor PROC
    pushad
    mov  eax, 400
    mov  ebx, 60
    call PlayBeep
    mov  eax, 600
    mov  ebx, 60
    call PlayBeep
    popad
    ret
SndDoor ENDP

SndKill PROC
    pushad
    mov  eax, 800
    mov  ebx, 70
    call PlayBeep
    mov  eax, 1100
    mov  ebx, 70
    call PlayBeep
    mov  eax, 1500
    mov  ebx, 100
    call PlayBeep
    popad
    ret
SndKill ENDP

SndLevel PROC
    pushad
    mov  eax, 600
    mov  ebx, 80
    call PlayBeep
    mov  eax, 800
    mov  ebx, 80
    call PlayBeep
    mov  eax, 1000
    mov  ebx, 80
    call PlayBeep
    mov  eax, 1300
    mov  ebx, 150
    call PlayBeep
    popad
    ret
SndLevel ENDP

; maze reshuffle: a low rumble
SndShift PROC
    pushad
    mov  eax, 150
    mov  ebx, 120
    call PlayBeep
    mov  eax, 110
    mov  ebx, 160
    call PlayBeep
    popad
    ret
SndShift ENDP

SndWin PROC
    pushad
    mov  eax, 700
    mov  ebx, 120
    call PlayBeep
    mov  eax, 900
    mov  ebx, 120
    call PlayBeep
    mov  eax, 1100
    mov  ebx, 120
    call PlayBeep
    mov  eax, 1400
    mov  ebx, 300
    call PlayBeep
    popad
    ret
SndWin ENDP

SndLose PROC
    pushad
    mov  eax, 400
    mov  ebx, 200
    call PlayBeep
    mov  eax, 300
    mov  ebx, 200
    call PlayBeep
    mov  eax, 200
    mov  ebx, 400
    call PlayBeep
    popad
    ret
SndLose ENDP
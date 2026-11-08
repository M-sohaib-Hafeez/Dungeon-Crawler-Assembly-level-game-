; ============================================================
;  main.asm  -  Text Dungeon Crawler  v3  (MASM32 + Irvine32)
; ============================================================
INCLUDE Irvine32.inc

; Win32 functions used for sound and emoji output.
; If you get a "redefinition" error on one of these, delete that line.
Beep          PROTO, dwFreq:DWORD, dwDuration:DWORD
WriteConsoleW PROTO, hOut:DWORD, lpBuf:DWORD, nChars:DWORD, lpWritten:DWORD, lpRsvd:DWORD

; ---------- constants ----------
MAP_WIDTH    EQU 20
MAP_HEIGHT   EQU 15
MAP_SIZE     EQU 300            ; 20 * 15
MAP_TOP      EQU 3              ; map starts on screen row 3 (rows 0-2 = HUD)
MSG_ROW      EQU MAP_TOP + MAP_HEIGHT + 1   ; message line under the map
MAX_LEVEL    EQU 10
POOL_BASE    EQU 25             ; first level-10 map inside mapBank
POOL_COUNT   EQU 25             ; number of level-10 maps
SHIFT_MS     EQU 10000          ; level 10: maze reshuffles every 10 s
FOG_RADIUS   EQU 4              ; how far the player can see (Manhattan distance)
CHASE_RANGE  EQU 8              ; monsters chase if path to player <= this
WEAPON_BONUS EQU 3              ; extra damage per weapon pickup
ARMOR_BONUS  EQU 2              ; damage absorbed per armor pickup
CHEAT_MS     EQU 700            ; how long a half-typed code waits for the next key

.data
; ---------- the "shared brain" ----------
; # wall   . floor   $ gold   M goblin   D dragon   P potion
; W weapon   A armor   K key   L locked door   E exit
mapData       BYTE MAP_SIZE DUP(0)

playerX       DWORD 1
playerY       DWORD 1
playerHP      DWORD 100
playerMaxHP   DWORD 100
playerGold    DWORD 0
playerPotions DWORD 1           ; harder: only one starting potion
playerKeys    DWORD 0
weaponBonus   DWORD 0
armorBonus    DWORD 0
hpLevel       DWORD 1           ; shop levels (1..10): health / attack / resistance
atkLevel      DWORD 1
resLevel      DWORD 1

enemyCount    DWORD 0           ; filled by LoadLevel
kills         DWORD 0
currentLevel  DWORD 1           ; 1..MAX_LEVEL

fogEnabled    DWORD 1           ; [F] toggles
soundOn       DWORD 1           ; [M] toggles
emojiMode     DWORD 1           ; [E] toggles (0 = coloured letters)
consoleOut    DWORD 0           ; console output handle (for emoji)
nextShiftTime DWORD 0           ; level 10: GetMseconds value of the next reshuffle

; hidden level-jump code (type l v l + 1..10 on the keyboard, nothing is shown)
cheatState    DWORD 0           ; 0 idle, 1 "l", 2 "lv", 3 "lvl", 4 "lvl1" (maybe 10)
cheatT        DWORD 0           ; time of the last code key
lastKey       BYTE  0

; 0 = running, 1 = victory, 2 = defeat, 3 = quit, 4 = level complete
gameState     DWORD 0

msgWelcome    BYTE "Level 1 - Defeat all monsters or find the exit. Good luck!",0
msgNextLevel  BYTE "Level complete! (+25 gold, +50 HP) Monsters grow stronger...",0
msgSaveOK     BYTE "Game saved to savegame.dat",0
msgSaveFail   BYTE "Could not save the game!",0
msgLoadOK     BYTE "Game loaded.",0
msgLoadFail   BYTE "No valid save file found.",0

.code
main PROC
    call Randomize
    INVOKE GetStdHandle, -11    ; STD_OUTPUT_HANDLE, needed for emoji output
    mov  consoleOut, eax
    call LoadHighScore          ; save.asm
    call LoadLevel              ; map.asm: pick/copy the map, count monsters
    call Clrscr
    call DrawHUD                ; ui.asm
    call DrawMap                ; map.asm
    mov  edx, OFFSET msgWelcome
    call ShowMessage

game_loop:
    call ReadKey                ; non-blocking: ZF = 1 when no key is waiting
    jnz  got_key
    cmp  cheatState, 0          ; a half-typed code that timed out?
    je   no_cheat_wait
    call GetMseconds
    sub  eax, cheatT
    cmp  eax, CHEAT_MS
    jae  cheat_timeout
no_cheat_wait:
    cmp  currentLevel, MAX_LEVEL
    jne  idle
    call CheckShiftTimer        ; shift.asm: countdown + maze reshuffle
idle:
    mov  eax, 15
    call Delay                  ; don't burn the CPU while waiting
    jmp  game_loop

got_key:
    or   al, 20h                ; make letters lowercase
    mov  lastKey, al
    cmp  cheatState, 0
    je   ck_idle
    cmp  cheatState, 1
    je   ck_s1
    cmp  cheatState, 2
    je   ck_s2
    cmp  cheatState, 3
    je   ck_s3
    jmp  ck_s4

ck_idle:                        ; AL = key, no code in progress
    cmp  al, 'l'
    jne  dispatch
    mov  cheatState, 1
    call StampCheat
    jmp  game_loop
ck_s1:                          ; typed "l"
    cmp  al, 'v'
    jne  ck_s1_other
    mov  cheatState, 2
    call StampCheat
    jmp  game_loop
ck_s1_other:                    ; it was just a normal Load
    mov  cheatState, 0
    call DoLoad
    mov  al, lastKey
    jmp  ck_idle
ck_s2:                          ; typed "lv"
    cmp  al, 'l'
    jne  ck_s2_other
    mov  cheatState, 3
    call StampCheat
    jmp  game_loop
ck_s2_other:                    ; Load then Save, as typed
    mov  cheatState, 0
    call DoLoad
    call DoSave
    mov  al, lastKey
    jmp  ck_idle
ck_s3:                          ; typed "lvl" - waiting for the level number
    cmp  al, '1'
    je   ck_s3_one
    cmp  al, '2'
    jb   ck_s3_other
    cmp  al, '9'
    ja   ck_s3_other
    movzx eax, al
    sub  eax, '0'               ; lvl2 .. lvl9
    mov  cheatState, 0
    call GotoLevel
    jmp  game_loop
ck_s3_one:                      ; "lvl1" - could still become lvl10
    mov  cheatState, 4
    call StampCheat
    jmp  game_loop
ck_s3_other:
    mov  cheatState, 0
    mov  al, lastKey
    jmp  ck_idle
ck_s4:                          ; typed "lvl1"
    cmp  al, '0'
    jne  ck_s4_other
    mov  cheatState, 0
    mov  eax, 10                ; lvl10
    call GotoLevel
    jmp  game_loop
ck_s4_other:
    mov  cheatState, 0
    mov  eax, 1                 ; it really was lvl1
    call GotoLevel
    mov  al, lastKey
    jmp  ck_idle

cheat_timeout:                  ; the next key never came
    mov  eax, cheatState
    mov  cheatState, 0
    cmp  eax, 1
    je   ct_s1
    cmp  eax, 2
    je   ct_s2
    cmp  eax, 4
    je   ct_s4
    jmp  game_loop              ; "lvl" without a number: ignore
ct_s1:
    call DoLoad
    jmp  game_loop
ct_s2:
    call DoLoad
    call DoSave
    jmp  game_loop
ct_s4:
    mov  eax, 1                 ; lvl1
    call GotoLevel
    jmp  game_loop

dispatch:                       ; normal key handling, AL = key
    cmp  al, 'q'
    je   quit_game
    cmp  al, 'i'
    je   open_inventory
    cmp  al, 'w'
    je   do_move
    cmp  al, 's'
    je   do_move
    cmp  al, 'a'
    je   do_move
    cmp  al, 'd'
    je   do_move
    cmp  al, 'v'
    je   do_save
    cmp  al, 'b'
    je   open_shop
    cmp  al, 'f'
    je   do_fog
    cmp  al, 'm'
    je   do_mute
    cmp  al, 'e'
    je   do_emoji
    jmp  game_loop

do_move:
    call ClearMsgArea           ; keeps AL
    call MovePlayer             ; AL = key, returns EAX=1 if a turn was used
    cmp  eax, 0
    je   game_loop              ; bumped into wall / locked door: no turn used
    jmp  after_turn

open_inventory:
    call ClearMsgArea
    call InventoryMenu          ; returns EAX=1 if a potion was drunk
    cmp  eax, 0
    je   redraw_only

after_turn:
    cmp  gameState, 0
    jne  state_change
    call MoveEnemies            ; enemy.asm: monsters take a turn
    cmp  gameState, 0
    jne  state_change
    call CheckWinCondition      ; enemy.asm
    cmp  gameState, 0
    jne  state_change

redraw_only:
    call DrawHUD
    call DrawMap
    jmp  game_loop

; ---------- hotkeys ----------
open_shop:
    call ShopMenu               ; shop.asm (clears the screen when it closes)
    jmp  redraw_only

do_fog:
    xor  fogEnabled, 1
    jmp  redraw_only

do_mute:
    xor  soundOn, 1
    jmp  redraw_only

do_emoji:
    xor  emojiMode, 1
    call Clrscr
    jmp  redraw_only

do_save:
    call DoSave
    jmp  game_loop

; ---------- level / game end ----------
state_change:
    cmp  gameState, 4           ; 4 = level complete
    jne  game_over
    call NextLevel              ; map.asm: sets gameState 0 (next level) or 1 (won)
    cmp  gameState, 0
    jne  game_over
    call ShopMenu               ; spend gold between levels
    call Clrscr
    call DrawHUD
    call DrawMap
    mov  edx, OFFSET msgNextLevel
    call ShowMessage
    jmp  game_loop

quit_game:
    mov  gameState, 3

game_over:
    call GameOverScreen         ; ui.asm
    exit
main ENDP

; ------------------------------------------------------------
; RandRange : random number in [EAX .. EBX] (inclusive)
;   in : EAX = min, EBX = max      out: EAX = result
; ------------------------------------------------------------
RandRange PROC
    push ebx
    push eax                    ; save min
    sub  ebx, eax
    inc  ebx                    ; size of range
    mov  eax, ebx
    call RandomRange            ; EAX = 0 .. size-1
    pop  ebx                    ; EBX = min
    add  eax, ebx
    pop  ebx
    ret
RandRange ENDP

; ------------------------------------------------------------
; DoSave / DoLoad : the [V] and [L] actions (with their messages)
; ------------------------------------------------------------
DoSave PROC
    call SaveGame               ; save.asm: EAX = 1 on success
    mov  edx, OFFSET msgSaveOK
    cmp  eax, 0
    jne  dsMsg
    mov  edx, OFFSET msgSaveFail
dsMsg:
    call ShowMessage
    ret
DoSave ENDP

DoLoad PROC
    call LoadGame               ; save.asm: EAX = 1 on success
    cmp  eax, 0
    jne  dlOK
    mov  edx, OFFSET msgLoadFail
    call ShowMessage
    ret
dlOK:
    call ResetShiftTimer        ; shift.asm
    call Clrscr
    call DrawHUD
    call DrawMap
    mov  edx, OFFSET msgLoadOK
    call ShowMessage
    ret
DoLoad ENDP

; ------------------------------------------------------------
; GotoLevel : EAX = level 1..MAX_LEVEL  (used by the hidden code)
;   keeps HP / gold / items, just builds that level and redraws
; ------------------------------------------------------------
GotoLevel PROC
    mov  currentLevel, eax
    mov  gameState, 0
    mov  lastShown, 99          ; shift.asm: redraw the level-10 countdown
    call LoadLevel
    call Clrscr
    call DrawHUD
    call DrawMap
    ret
GotoLevel ENDP

StampCheat PROC
    push eax
    call GetMseconds
    mov  cheatT, eax
    pop  eax
    ret
StampCheat ENDP

; ---------- module files (each one is owned by one teammate) ----------
INCLUDE map.asm
INCLUDE player.asm
INCLUDE combat.asm
INCLUDE ui.asm
INCLUDE shop.asm
INCLUDE enemy.asm
INCLUDE shift.asm
INCLUDE leveldata.asm
INCLUDE save.asm

END main
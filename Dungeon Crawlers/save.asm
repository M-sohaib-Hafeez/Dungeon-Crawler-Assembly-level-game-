; ============================================================
;  save.asm  -  File I/O: high score + save/load game
;  Procs: LoadHighScore, SaveHighScore, SaveGame, LoadGame
;  Files (created next to the .exe / in the working directory):
;     highscore.dat  - 4 bytes
;     savegame.dat   - 60 bytes of stats + 300 bytes map + 300 bytes fog
;  (included by main.asm - do NOT build this file on its own)
; ============================================================
.data
hsFile      BYTE "highscore.dat",0
saveFile    BYTE "savegame.dat",0
fileHandle  DWORD 0
highScore   DWORD 0

saveStats   DWORD 15 DUP(0)     ; packed copy of the player/game variables
tmpMap      BYTE  MAP_SIZE DUP(0)   ; load into temp buffers first so a bad
tmpSeen     BYTE  MAP_SIZE DUP(0)   ; file can never corrupt the running game

.code
; ------------------------------------------------------------
; LoadHighScore : reads highscore.dat (if it exists) into highScore
; ------------------------------------------------------------
LoadHighScore PROC
    mov  edx, OFFSET hsFile
    call OpenInputFile          ; EAX = handle or INVALID_HANDLE_VALUE
    cmp  eax, INVALID_HANDLE_VALUE
    je   lhDone
    mov  fileHandle, eax
    mov  eax, fileHandle
    mov  edx, OFFSET highScore
    mov  ecx, 4
    call ReadFromFile
    mov  eax, fileHandle
    call CloseFile
lhDone:
    ret
LoadHighScore ENDP

; ------------------------------------------------------------
; SaveHighScore : writes highScore to highscore.dat
; ------------------------------------------------------------
SaveHighScore PROC
    mov  edx, OFFSET hsFile
    call CreateOutputFile       ; overwrites an existing file
    cmp  eax, INVALID_HANDLE_VALUE
    je   shDone
    mov  fileHandle, eax
    mov  eax, fileHandle
    mov  edx, OFFSET highScore
    mov  ecx, 4
    call WriteToFile
    mov  eax, fileHandle
    call CloseFile
shDone:
    ret
SaveHighScore ENDP

; ------------------------------------------------------------
; SaveGame : returns EAX = 1 on success, 0 on failure
; ------------------------------------------------------------
SaveGame PROC
    mov  eax, playerX           ; pack the variables
    mov  saveStats[0], eax
    mov  eax, playerY
    mov  saveStats[4], eax
    mov  eax, playerHP
    mov  saveStats[8], eax
    mov  eax, playerMaxHP
    mov  saveStats[12], eax
    mov  eax, playerGold
    mov  saveStats[16], eax
    mov  eax, playerPotions
    mov  saveStats[20], eax
    mov  eax, enemyCount
    mov  saveStats[24], eax
    mov  eax, kills
    mov  saveStats[28], eax
    mov  eax, currentLevel
    mov  saveStats[32], eax
    mov  eax, playerKeys
    mov  saveStats[36], eax
    mov  eax, weaponBonus
    mov  saveStats[40], eax
    mov  eax, armorBonus
    mov  saveStats[44], eax
    mov  eax, hpLevel
    mov  saveStats[48], eax
    mov  eax, atkLevel
    mov  saveStats[52], eax
    mov  eax, resLevel
    mov  saveStats[56], eax

    mov  edx, OFFSET saveFile
    call CreateOutputFile
    cmp  eax, INVALID_HANDLE_VALUE
    je   sgFail
    mov  fileHandle, eax

    mov  eax, fileHandle
    mov  edx, OFFSET saveStats
    mov  ecx, 60
    call WriteToFile
    mov  eax, fileHandle
    mov  edx, OFFSET mapData
    mov  ecx, MAP_SIZE
    call WriteToFile
    mov  eax, fileHandle
    mov  edx, OFFSET seenData
    mov  ecx, MAP_SIZE
    call WriteToFile
    mov  eax, fileHandle
    call CloseFile
    mov  eax, 1
    ret
sgFail:
    xor  eax, eax
    ret
SaveGame ENDP

; ------------------------------------------------------------
; LoadGame : returns EAX = 1 on success, 0 on failure
;   (the running game is only touched once the whole file is valid)
; ------------------------------------------------------------
LoadGame PROC
    mov  edx, OFFSET saveFile
    call OpenInputFile
    cmp  eax, INVALID_HANDLE_VALUE
    je   lgFail
    mov  fileHandle, eax

    mov  eax, fileHandle
    mov  edx, OFFSET saveStats
    mov  ecx, 60
    call ReadFromFile
    jc   lgBad
    cmp  eax, 60
    jne  lgBad
    mov  eax, fileHandle
    mov  edx, OFFSET tmpMap
    mov  ecx, MAP_SIZE
    call ReadFromFile
    jc   lgBad
    cmp  eax, MAP_SIZE
    jne  lgBad
    mov  eax, fileHandle
    mov  edx, OFFSET tmpSeen
    mov  ecx, MAP_SIZE
    call ReadFromFile
    jc   lgBad
    cmp  eax, MAP_SIZE
    jne  lgBad

    mov  eax, saveStats[32]     ; sanity check: level must be 1..MAX_LEVEL
    cmp  eax, 1
    jb   lgBad
    cmp  eax, MAX_LEVEL
    ja   lgBad
    mov  eax, saveStats[48]     ; sanity check: shop levels 1..SHOP_MAX
    cmp  eax, 1
    jb   lgBad
    cmp  eax, SHOP_MAX
    ja   lgBad
    mov  eax, saveStats[52]
    cmp  eax, 1
    jb   lgBad
    cmp  eax, SHOP_MAX
    ja   lgBad
    mov  eax, saveStats[56]
    cmp  eax, 1
    jb   lgBad
    cmp  eax, SHOP_MAX
    ja   lgBad
    mov  eax, saveStats[0]      ; sanity check: position inside the map
    cmp  eax, MAP_WIDTH
    jae  lgBad
    mov  eax, saveStats[4]
    cmp  eax, MAP_HEIGHT
    jae  lgBad

    mov  eax, fileHandle
    call CloseFile

    cld                         ; commit the map + fog
    mov  esi, OFFSET tmpMap
    mov  edi, OFFSET mapData
    mov  ecx, MAP_SIZE
    rep  movsb
    mov  esi, OFFSET tmpSeen
    mov  edi, OFFSET seenData
    mov  ecx, MAP_SIZE
    rep  movsb

    mov  eax, saveStats[0]      ; unpack the variables
    mov  playerX, eax
    mov  eax, saveStats[4]
    mov  playerY, eax
    mov  eax, saveStats[8]
    mov  playerHP, eax
    mov  eax, saveStats[12]
    mov  playerMaxHP, eax
    mov  eax, saveStats[16]
    mov  playerGold, eax
    mov  eax, saveStats[20]
    mov  playerPotions, eax
    mov  eax, saveStats[24]
    mov  enemyCount, eax
    mov  eax, saveStats[28]
    mov  kills, eax
    mov  eax, saveStats[32]
    mov  currentLevel, eax
    mov  eax, saveStats[36]
    mov  playerKeys, eax
    mov  eax, saveStats[40]
    mov  weaponBonus, eax
    mov  eax, saveStats[44]
    mov  armorBonus, eax
    mov  eax, saveStats[48]
    mov  hpLevel, eax
    mov  eax, saveStats[52]
    mov  atkLevel, eax
    mov  eax, saveStats[56]
    mov  resLevel, eax
    mov  gameState, 0
    mov  eax, 1
    ret

lgBad:
    mov  eax, fileHandle
    call CloseFile
lgFail:
    xor  eax, eax
    ret
LoadGame ENDP
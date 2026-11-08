; ============================================================
;  shop.asm The Shop (spend gold on upgrades)
;  Procs: ShopMenu, DrawShop, ShopLine, BuyUpgrade, GetLevel, IncLevel,
;         GetTotalAtk, GetTotalDef
;
;  Three upgrades, each from level 1 up to level 10:
;     Health      +10 max HP per level   (level 1 = 100, level 2 = 110, ...)
;     Attack      +2  damage per level   (added to weapon pickups)
;     Resistance  +1  damage blocked per level (added to armor pickups)
;  Cost of the next level = base + step * (current level - 1)
;  Open it any time with [B]; it also opens after every level you clear.
;  (included by main.asm - do NOT build this file on its own)
; =======================================================================
SHOP_MAX      EQU 10
HP_PER_LEVEL  EQU 10
ATK_PER_LEVEL EQU 2
RES_PER_LEVEL EQU 1

.data
costBase     DWORD 50, 60, 60   ; health, attack, resistance
costStep     DWORD 25, 30, 30

shopT0       DWORD 0
buyIdx       DWORD 0
buyLvl       DWORD 0
buyCost      DWORD 0
shopMsgPtr   DWORD 0

; one shop line is described by these (filled in by DrawShop)
slName       DWORD 0
slLevel      DWORD 0
slLabel      DWORD 0
slNow        DWORD 0
slNext       DWORD 0
slCost       DWORD 0

shopTitle    BYTE "=================  D U N G E O N   S H O P  =================",0
shopGoldTxt  BYTE "  Your gold: ",0
nameHealth   BYTE "  [1] Health      ",0
nameAttack   BYTE "  [2] Attack      ",0
nameResist   BYTE "  [3] Resistance  ",0
txtLv        BYTE "Lv ",0
txtOf        BYTE "/10   ",0
lblMaxHP     BYTE "Max HP ",0
lblAtkBonus  BYTE "Bonus damage +",0
lblResBonus  BYTE "Damage blocked ",0
txtArrow     BYTE " -> ",0
txtCost      BYTE "   Cost: ",0
txtGoldWord  BYTE " gold",0
txtMaxLevel  BYTE "   MAX LEVEL",0
shopHelp     BYTE "  Press 1, 2 or 3 to buy an upgrade.   [Q] leave the shop",0

shopMsgHint  BYTE "  Spend your gold wisely - upgrades are permanent!",0
shopMsgOK    BYTE "  Upgrade bought!",0
shopMsgPoor  BYTE "  Not enough gold.",0
shopMsgMax   BYTE "  That upgrade is already at its maximum level.",0

.code
; ------------------------------------------------------------
; GetLevel : EAX = 0 health / 1 attack / 2 resistance  ->  EAX = its level
; IncLevel : same input, adds one level
; ------------------------------------------------------------
GetLevel PROC
    cmp  eax, 0
    jne  glNotHP
    mov  eax, hpLevel
    ret
glNotHP:
    cmp  eax, 1
    jne  glNotAtk
    mov  eax, atkLevel
    ret
glNotAtk:
    mov  eax, resLevel
    ret
GetLevel ENDP

IncLevel PROC
    cmp  eax, 0
    jne  ilNotHP
    inc  hpLevel
    ret
ilNotHP:
    cmp  eax, 1
    jne  ilNotAtk
    inc  atkLevel
    ret
ilNotAtk:
    inc  resLevel
    ret
IncLevel ENDP

; ------------------------------------------------------------
; GetTotalAtk : EAX = weapon pickups + attack upgrades
; GetTotalDef : EAX = armor pickups  + resistance upgrades
; ------------------------------------------------------------
GetTotalAtk PROC
    mov  eax, atkLevel
    dec  eax
    imul eax, ATK_PER_LEVEL
    add  eax, weaponBonus
    ret
GetTotalAtk ENDP

GetTotalDef PROC
    mov  eax, resLevel
    dec  eax
    imul eax, RES_PER_LEVEL
    add  eax, armorBonus
    ret
GetTotalDef ENDP

; ------------------------------------------------------------
; ShopLine : prints one upgrade line from the sl* variables
; ------------------------------------------------------------
ShopLine PROC
    mov  eax, white
    call SetTextColor
    mov  edx, slName
    call WriteString
    mov  edx, OFFSET txtLv
    call WriteString
    mov  eax, slLevel
    call WriteDec
    mov  edx, OFFSET txtOf
    call WriteString
    mov  edx, slLabel
    call WriteString
    mov  eax, slNow
    call WriteDec
    cmp  slLevel, SHOP_MAX
    jae  slMax
    mov  edx, OFFSET txtArrow
    call WriteString
    mov  eax, slNext
    call WriteDec
    mov  edx, OFFSET txtCost
    call WriteString
    mov  eax, yellow
    call SetTextColor
    mov  eax, slCost
    call WriteDec
    mov  edx, OFFSET txtGoldWord
    call WriteString
    call Crlf
    ret
slMax:
    mov  eax, lightGreen
    call SetTextColor
    mov  edx, OFFSET txtMaxLevel
    call WriteString
    call Crlf
    ret
ShopLine ENDP

; ------------------------------------------------------------
; DrawShop : the whole shop screen
; ------------------------------------------------------------
DrawShop PROC
    call Clrscr
    mov  eax, lightCyan
    call SetTextColor
    call Crlf
    mov  edx, OFFSET shopTitle
    call WriteString
    call Crlf
    call Crlf
    mov  eax, yellow
    call SetTextColor
    mov  edx, OFFSET shopGoldTxt
    call WriteString
    mov  eax, playerGold
    call WriteDec
    call Crlf
    call Crlf

    ; ---- Health ----
    mov  slName, OFFSET nameHealth
    mov  slLabel, OFFSET lblMaxHP
    mov  eax, hpLevel
    mov  slLevel, eax
    mov  eax, playerMaxHP
    mov  slNow, eax
    add  eax, HP_PER_LEVEL
    mov  slNext, eax
    mov  eax, 0
    call UpgradeCost
    mov  slCost, eax
    call ShopLine
    call Crlf

    ; ---- Attack ----
    mov  slName, OFFSET nameAttack
    mov  slLabel, OFFSET lblAtkBonus
    mov  eax, atkLevel
    mov  slLevel, eax
    dec  eax
    imul eax, ATK_PER_LEVEL
    mov  slNow, eax
    add  eax, ATK_PER_LEVEL
    mov  slNext, eax
    mov  eax, 1
    call UpgradeCost
    mov  slCost, eax
    call ShopLine
    call Crlf

    ; ---- Resistance ----
    mov  slName, OFFSET nameResist
    mov  slLabel, OFFSET lblResBonus
    mov  eax, resLevel
    mov  slLevel, eax
    dec  eax
    imul eax, RES_PER_LEVEL
    mov  slNow, eax
    add  eax, RES_PER_LEVEL
    mov  slNext, eax
    mov  eax, 2
    call UpgradeCost
    mov  slCost, eax
    call ShopLine
    call Crlf

    mov  eax, gray
    call SetTextColor
    mov  edx, OFFSET shopHelp
    call WriteString
    call Crlf
    call Crlf
    mov  eax, white
    call SetTextColor
    mov  edx, shopMsgPtr
    call WriteString
    call Crlf
    ret
DrawShop ENDP

; ------------------------------------------------------------
; UpgradeCost : EAX = 0/1/2 (stat)  ->  EAX = gold needed for its next level
; ------------------------------------------------------------
UpgradeCost PROC
    push ecx
    push ebx
    mov  ecx, eax               ; stat index
    call GetLevel               ; EAX = its level
    mov  ebx, eax
    dec  ebx                    ; level - 1
    mov  eax, costStep[ecx*4]
    imul eax, ebx
    add  eax, costBase[ecx*4]
    pop  ebx
    pop  ecx
    ret
UpgradeCost ENDP

; ------------------------------------------------------------
; BuyUpgrade : EAX = 0/1/2 (stat) - buys the next level if possible
;   sets shopMsgPtr to the message to show
; ------------------------------------------------------------
BuyUpgrade PROC
    mov  buyIdx, eax
    call GetLevel
    cmp  eax, SHOP_MAX
    jae  buMax
    mov  eax, buyIdx
    call UpgradeCost
    mov  buyCost, eax
    cmp  playerGold, eax
    jb   buPoor
    sub  playerGold, eax        ; pay
    mov  eax, buyIdx
    call IncLevel
    cmp  buyIdx, 0
    jne  buDone
    add  playerMaxHP, HP_PER_LEVEL   ; health upgrade: bigger bar, and +10 HP now
    add  playerHP, HP_PER_LEVEL
buDone:
    call SndPickup
    mov  shopMsgPtr, OFFSET shopMsgOK
    ret
buPoor:
    mov  shopMsgPtr, OFFSET shopMsgPoor
    ret
buMax:
    mov  shopMsgPtr, OFFSET shopMsgMax
    ret
BuyUpgrade ENDP

; ------------------------------------------------------------
; ShopMenu : the shop loop. [1][2][3] buy, [Q]/[B]/Esc/Enter leave.
;   The level-10 shift timer is paused while you shop.
; ------------------------------------------------------------
ShopMenu PROC
    call GetMseconds
    mov  shopT0, eax
    mov  shopMsgPtr, OFFSET shopMsgHint
smLoop:
    call DrawShop
    call ReadChar
    cmp  al, 1Bh                ; Esc
    je   smDone
    cmp  al, 0Dh                ; Enter
    je   smDone
    or   al, 20h
    cmp  al, 'q'
    je   smDone
    cmp  al, 'b'
    je   smDone
    cmp  al, '1'
    jne  smNot1
    mov  eax, 0
    call BuyUpgrade
    jmp  smLoop
smNot1:
    cmp  al, '2'
    jne  smNot2
    mov  eax, 1
    call BuyUpgrade
    jmp  smLoop
smNot2:
    cmp  al, '3'
    jne  smLoop
    mov  eax, 2
    call BuyUpgrade
    jmp  smLoop
smDone:
    call GetMseconds
    sub  eax, shopT0
    jb   smNoFix
    add  nextShiftTime, eax     ; push the next maze shift back by the shopping time
smNoFix:
    call Clrscr
    ret
ShopMenu ENDP
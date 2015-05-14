#include "kernel.inc"
    .db "KEXC"
    .db KEXC_ENTRY_POINT
    .dw start
    .db KEXC_STACK_SIZE
    .dw 20
    .db KEXC_NAME
    .dw name
    .db KEXC_HEADER_END
name:
    .db "kiano", 0
start:
    ; This is an example program, replace it with your own!

    ; Get a lock on the devices we intend to use
    pcall(getLcdLock)
    pcall(getKeypadLock)

    ; Allocate and clear a buffer to store the contents of the screen
    pcall(allocScreenBuffer)
    pcall(clearBuffer)

    ; Draw `message` to 0, 0 (D, E = 0, 0)
    kld(hl, message)
    ld de, 0
    pcall(drawStr)

.loop:
    ; Copy the display buffer to the actual LCD
    pcall(fastCopy)

    ; flushKeys waits for all keys to be released
    pcall(flushKeys)
    ; waitKey waits for a key to be pressed, then returns the key code in A
    pcall(waitKey)

    cp kMODE
    jr nz, .loop

    ; Exit when the user presses "MODE"
    ret

message:
    .db "Hello, world!", 0

;************************************************************
;
; Piano83 v2.1
; ============
; for Ion on the TI-83/TI-83+
;
; by Badja
; 10 August 2001
;
; http://badja.calc.org
; badja@calc.org
;
; You may modify this source code for personal use only.
; You may NOT distribute the modified source or program file.
;
;************************************************************

.NOLIST
#include "ion.inc"
.LIST


tuning      .equ  saferam1

ch1count    .equ  saferam1+2
ch1freq     .equ  saferam1+4
ch1curr     .equ  saferam1+6

ch2count    .equ  saferam1+7
ch2freq     .equ  saferam1+9
ch2curr     .equ  saferam1+11

flags       .equ  asm_flag1
key         .equ  asm_flag1_0
chord       .equ  asm_flag1_1


#ifdef TI83P
      .org  progstart-2
      .db   $BB,$6D
#else
      .org  progstart
#endif
      xor   a
      jr    nc,start
      .db   "Piano83 2.1",0

start:
      ld    hl,54             ; initial tuning
      ld    (tuning),hl
      res   key,(iy+flags)    ; initial key
      res   chord,(iy+flags)  ; initial chord mode
      res   appAutoScroll,(iy+appflags)
      ld    hl,$0000          ; show instructions
      ld    (currow),hl
      ld    hl,instructions
      ld    b,6
putInstr:
      set   textInverse,(iy+textflags)
      bcall(_puts)
      res   textInverse,(iy+textflags)
      bcall(_puts)
      djnz  putInstr
      call  dispMaj
      call  dispTune
      call  dispUnison

mainLoop:
      ld    e,0         ; E = number of notes pressed
      ld    h,e         ; initialise channels to 0 (no note)
      ld    l,e
      ld    (ch1freq),hl
      ld    (ch2freq),hl

      ld    d,$bf       ; D = key column
      call  getKeyData
      ld    hl,0        ; true pitch octaves
      ld    bc,24
      cp    239
      jp    z,octave1
      cp    247
      jp    z,octave2
      cp    251
      jp    z,octave3
      cp    253
      jp    z,octave4

      bit   5,a         ; check if 2nd is pressed
      jr    nz,not2nd
      ld    bc,2
      push  af
      call  storeNote
      pop   af
not2nd:

      bit   key,(iy+flags)    ; determine major/minor
      jr    z,useMajKey
      ld    hl,keyMapMin      ; load minor keymap

      bit   6,a               ; if minor, check if MODE is pressed
      jr    nz,notMODE
      ld    bc,0
      push  af
      call  storeNote
      pop   af
notMODE:
      jr    useMinKey

useMajKey:
      ld    hl,keyMapMaj      ; load major keymap

useMinKey:
      bit   7,a               ; check if DEL is pressed
      jr    nz,notDEL
      ld    bc,26
      call  storeNote
notDEL:

nextCol:
      call  getKeyData
      ld    b,8         ; check all 8 keys in key column
checkCol:
      push  bc
      rla               ; get next bit from A
      jr    c,noPlay    ; if bit is 1, key is not pressed
      push  af
      ld    a,(hl)      ; get note from keymap
      cp    255         ; 255 in the key map means no sound
      jr    z,noSound
      ld    b,0         ; store/play the note
      ld    c,a
      call  storeNote
noSound:
      pop   af
noPlay:
      inc   hl
      pop   bc
      djnz  checkCol
      ld    a,d
      cp    $fd         ; continue until key column is $fd
      jr    nz,nextCol

      call  getKeyData
      cp    191         ; check if CLEAR is pressed
      jr    z,exit
      push  de
      cp    223
      call  z,changeChord
      cp    251
      call  z,downOct
      cp    253
      call  z,upOct
      pop   de

      call  getKeyData
      bit   1,a         ; check if left is pressed
      jr    nz,notLeft
      ld    bc,28
      call  storeNote
notLeft:
      bit   0,a
      push  af
      call  z,down
      pop   af
      bit   2,a
      push  af
      call  z,changeKey
      pop   af
      bit   3,a
      call  z,up

      in    a,(3)       ; check if ON is pressed
      bit   3,a
      jr    nz,notOn
      ld    bc,30
      call  storeNote
notOn:

      bit   chord,(iy+flags)  ; if in unison mode, play the two channels
      call  z,playNotes
      jp    mainLoop


exit:
      set   appAutoScroll,(iy+appflags)
      ret


storeNote:
      bit   1,e               ; maximum of two notes at a time in unison mode
      ret   nz
      push  hl
      ld    hl,pitches        ; address of the pitches table
      add   hl,bc             ; add the pitch
      ld    bc,(tuning)
      add   hl,bc             ; add the tuning
      ld    c,(hl)            ; get the period in BC
      inc   hl
      ld    b,(hl)
      bit   chord,(iy+flags)  ; jump if in arpeggio mode
      jr    nz,arpeggio
      bit   0,e               ; store note into next channel
      call  z,storeCh1
      call  nz,storeCh2
      inc   e                 ; move to next channel
      jr    doneNote
arpeggio:
      call  storeCh1          ; store into both channels
      call  storeCh2
      push  af
      call  playNotes         ; play note immediately
      pop   af
doneNote:
      pop   hl
      ret


storeCh1:
      ld    (ch1freq),bc
      ret

storeCh2:
      ld    (ch2freq),bc
      ret


octave4:
      add   hl,bc
octave3:
      add   hl,bc
octave2:
      add   hl,bc
octave1:
      bit   key,(iy+flags)
      jr    nz,isMinKey
      ld    bc,6
      add   hl,bc
isMinKey:
      ld    (tuning),hl
      call  dispTune
      call  delay
      jp    mainLoop


dispTune:
      ld    hl,$0b03
      ld    (currow),hl
      ld    hl,(tuning)
      sra   l
      bcall(_disphl)
      ld    bc,$0803
      ld    hl,txtTune
      jr    putString


dispMaj:
      ld    bc,$0b02
      ld    hl,txtMajor
      jr    putString

dispMin:
      ld    bc,$0b02
      ld    hl,txtMinor


putString:
      ld    (currow),bc
      bcall(_puts)
      ret


changeKey:
      bit   key,(iy+flags)
      jr    nz,toMajor
      set   key,(iy+flags)
      call  dispMin
      jr    delay
toMajor:
      res   key,(iy+flags)
      call  dispMaj
      jr    delay


changeChord:
      ld    a,(iy+flags)
      xor   %00000010
      ld    (iy+flags),a

dispChord:
      bit   chord,(iy+flags)
      jr    z,dispUnison

dispArpeggio:
      ld    bc,$0907
      ld    hl,txtArpeggio
      call  putString
      jr    delay

dispUnison:
      ld    bc,$0907
      ld    hl,txtUnison
      call  putString
      jr    delay


downOct:
      ld    a,(tuning)
      cp    24
      ret   c
      sub   24
      jr    doneTune

upOct:
      ld    a,(tuning)
      cp    62
      ret   nc
      add   a,24
      jr    doneTune

down:
      ld    a,(tuning)
      cp    84
      ret   z
      add   a,2
      jr    doneTune

up:
      ld    a,(tuning)
      cp    0
      ret   z
      sub   2
doneTune:
      ld    (tuning),a
      call  dispTune


delay:
      ld    bc,$8000
delayLoop:
      dec   bc
      ld    a,b
      or    c
      jr    nz,delayLoop
      ret


getKeyData:
      ld    a,$ff       ; reset keyport
      out   (1),a
      ld    a,d
      out   (1),a
      in    a,(1)
      sra   d           ; D = next key column
      ret


playNotes:
      ld    b,0         ; loop 256 times
playLoop:
      push  bc

      ld    hl,(ch1count)
      dec   h                 ; decrease MSB of count
      jr    nz,noEdge1a       ; jump if not zero (on edge of square wave when count reaches 0)
      ld    bc,(ch1freq)      ; BC = freq
      ld    a,b
      or    a
      jr    z,noEdge1b        ; skip if MSB is 0 (no note)
      add   hl,bc             ; otherwise add frequency to count
      ld    bc,ch1curr        ; and
      ld    a,(bc)            ; invert bit 0 of curr
      xor   1                 ; 0->1 or 1->0
      ld    (bc),a
      jr    noEdge1c

noEdge1a:                     ; makes the playNotes routine constant time ...
      res   7,(ix)      ; 23
      bit   7,(hl)      ; 12
                        ;=35
noEdge1b:                     ; ... for greater pitch accuracy
      res   7,(ix)      ; 23
      adc   a,(ix)      ; 19
      adc   a,(hl)      ;  7
                        ;=49
noEdge1c:
      ld    (ch1count),hl

      ld    hl,(ch2count)
      dec   h                 ; decrease MSB of count
      jr    nz,noEdge2a       ; jump if not zero (on edge of square wave when count reaches 0)
      ld    bc,(ch2freq)      ; BC = freq
      ld    a,b
      or    a
      jr    z,noEdge2b        ; skip if MSB is 0 (no note)
      add   hl,bc             ; otherwise add frequency to count
      ld    bc,ch2curr        ; and
      ld    a,(bc)            ; invert bit 0 of curr
      xor   1                 ; 0->1 or 1->0
      ld    (bc),a
      jr    noEdge2c

noEdge2a:                     ; makes the playNotes routine constant time ...
      res   7,(ix)      ; 23
      bit   7,(hl)      ; 12
                        ;=35
noEdge2b:                     ; ... for greater pitch accuracy
      res   7,(ix)      ; 23
      adc   a,(ix)      ; 19
      adc   a,(hl)      ;  7
                        ;=49
noEdge2c:
      ld    (ch2count),hl

      ld    a,(ch1curr)
      ld    b,a
      ld    a,(ch2curr)
      ld    c,a

      ld    a,%00110100
      srl   b                 ; rotate channel 1 bit into A
      rla
      srl   c                 ; rotate channel 2 bit into A
      rla
      out   (0),a             ; output the sample

      pop   bc
      djnz  playLoop

      ret


keyMapMaj:
      .db   6,10,12,16,20,24,26,255
      .db   4,8,255,14,18,22,255,28
      .db   30,34,36,40,44,48,50,54
      .db   255,32,255,38,42,46,255,52

keyMapMin:
      .db   6,8,12,16,18,22,26,255
      .db   4,255,10,14,255,20,24,28
      .db   30,32,36,40,42,46,50,54
      .db   255,255,34,38,255,44,48,52

pitches:
      ; lowest note: G# 1
      ; highest note: F 7
      .dw   $898C
      .dw   $81D4
      .dw   $7A8A
      .dw   $73AA
      .dw   $6D2C
      .dw   $670B
      .dw   $6143
      .dw   $5BCD
      .dw   $56A6
      .dw   $51C9
      .dw   $4D32
      .dw   $48DD
      .dw   $44C6
      .dw   $40EA
      .dw   $3D45
      .dw   $39D5
      .dw   $3696
      .dw   $3385
      .dw   $30A1
      .dw   $2DE6
      .dw   $2B53
      .dw   $28E4
      .dw   $2699
      .dw   $246E
      .dw   $2263
      .dw   $2075
      .dw   $1EA2
      .dw   $1CEA
      .dw   $1B4B
      .dw   $19C2
      .dw   $1850
      .dw   $16F3
      .dw   $15A9
      .dw   $1472
      .dw   $134C
      .dw   $1237
      .dw   $1131
      .dw   $103A
      .dw   $0F51
      .dw   $0E75
      .dw   $0DA5
      .dw   $0CE1
      .dw   $0C28
      .dw   $0B79
      .dw   $0AD4
      .dw   $0A39
      .dw   $09A6
      .dw   $091B
      .dw   $0898
      .dw   $081D
      .dw   $07A8
      .dw   $073A
      .dw   $06D2
      .dw   $0670
      .dw   $0614
      .dw   $05BC
      .dw   $056A
      .dw   $051C
      .dw   $04D3
      .dw   $048D
      .dw   $044C
      .dw   $040E
      .dw   $03D4
      .dw   $039D
      .dw   $0369
      .dw   $0338
      .dw   $030A
      .dw   $02DE
      .dw   $02B5
      .dw   $028E


instructions:
      .db   " Piano83 ",0,"http://"
      .db   "  badja.calc.org",0
      .db   "Right",0," Key:      ",0
      .db   "Up/Down",0,"         ",0
      .db   "+/-",0," Tune by 8ves",0
      .db   "Y/WIN/ZOOM/TRACE",0
      .db   " True-pitch 8ves",0
      .db   "^",0," Chord:",0

txtMajor:
      .db   "C Maj",0

txtMinor:
      .db   "A Min",0

txtTune:
      .db   "Tune:",0

txtUnison:
      .db   "Unison ",0

txtArpeggio:
      .db   "Arpegio",0

.end

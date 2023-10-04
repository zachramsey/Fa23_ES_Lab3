;====================================
; StopwatchLab2.asm
;
; Created: 9/12/2023 7:02:54 PM
; Authors: Trey Vokoun & Zach Ramsey
;====================================

.include "m328Pdef.inc" ; microcontroller-specific definitions

;>>>>>Begin Data Segment<<<<<
.dseg
.org 0x0100
Digit_Patterns: .byte 16	; Hex Digit Pattern Encoding

;>>>>>Begin Code Segment<<<<<
.cseg
.org 0

;==================| Configure I/O |=================
; Output to shiftreg SN74HC595
sbi DDRB,0	; Board Pin 8 O/P: PB0 -> ShiftReg I/P: SER
sbi DDRB,1	; Board Pin 9 O/P: PB1 -> ShiftReg I/P: RCLK
sbi DDRB,2	; Board Pin 10 O/P: PB2 -> ShiftReg I/P: SRCLK
sbi DDRB,3  ; Board Pin 11 O/P: PB3 -> Status LEDs

; Input from pushbuttons
cbi DDRD,7	; Board Pin 7 Pushbutton A -> Board I/P: PD7
cbi DDRD,6	; Board Pin 6 RPG A -> Board I/P: PD6
cbi DDRD,5  ; Board Pin 5 RPG B -> Board I/P: PD5


;========| Configure custom state register |=========
.def Disp_Queue = R16	; Data queue for next digit to be displayed
.def Disp_Decr = R17	; Count of remaining bits to be pushed from Disp_Queue; decrements from 8
.def Digit_Decr = R18	; Count of remaining digits; decrements from 16
.def Ctrl_Reg = R19		; Custom state register
.def Digit_Buff = R20	; Data buffer for loading to Digit_Patterns
.def Ten_Decr = R21		; Count of remaining calls to one_delay; decrements from 10
.def Temp = R22			; Temporary register used to assist with converting a display pattern to the same pattern but with the tens mode light on


; Custom state register masks
.equ A_State = 0b00000001		; bit 0: button A was pressed   (0:None    | 1:Pressed)
.equ A_RPG = 0b00000010			; bit 1: A_RPG Toggled          (0:Pressed?| 1:None)
.equ B_RPG = 0b00000100			; bit 2: B_RPG Toggled			(0:Pressed?| 1:None)
.equ Run_State = 0b00001000		; bit 3: incrementing state     (0:Stopped | 1:Running)
.equ Reset_State = 0b00010000	; bit 4: reset state            (0:None    | 1:Reset)
.equ Ovrflw = 0b00100000		; bit 5: overflow state         (0:None    | 1:Overflow)

;-----Usage-----
; Set State:
; sbr Ctrl_Reg, (state mask)

; Clear State:
; cbr Ctrl_Reg, (state mask)

; Skip next if bit is 0:
; sbrc Ctrl_Reg, (reg bit #)

; Skip next if bit is 1:
; sbrs Ctrl_Reg, (reg bit #)
;---------------

;=========| Load Values to Digit_Patterns |==========
ldi ZH, high(Digit_Patterns)	; Move pointer to front of Digit_Patterns
ldi ZL, low(Digit_Patterns)

ldi Digit_Buff, 0x3F	; "0" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x06	; "1" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x5B	; "2" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x4F	; "3" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x66	; "4" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x6D	; "5" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x7D	; "6" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x07	; "7" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x7F	; "8" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x67	; "9" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x77	; "A" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x7C	; "b" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x39	; "C" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x5E	; "d" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x79	; "E" Pattern
st Z+, Digit_Buff
ldi Digit_Buff, 0x71	; "F" Pattern
st Z+, Digit_Buff

;===================| Main Loop |====================
ldi Disp_Queue, 0x39 
rcall display

main:
	sbic PIND, 6		; Skip if bit in I/O for RPG-A cleared
	rcall CW			;

	sbic PIND, 5		;Skip if bit in I/O for RPG-B cleared
	rcall CCW			;

	sbis PIND, 7		;Skip if bit in I/O for buttonA set
	rcall AButton		; 

rjmp main

;===================| Functions |====================
CW:
	CWL1:
		sbic PIND, 5
	brne CWL1
	ldi Disp_Queue, 0x77
	rcall display
ret

CCW:
	CCWL1:
		sbic PIND, 6
	brne CWL1
	ldi Disp_Queue, 0x7C
	rcall display
ret

AButton:
	ABL1:
		sbic PIND, 7
		sbi PORTB, 3
	brne ABL1
	cbi PORTB, 3
	rcall display
ret


;============| Display Digit Subroutine |============
display:
	; backup used registers on stack
	push Disp_Queue			; Push Disp_Queue to stack
	push Disp_Decr			; Push Disp_Decr to stack
	in Disp_Decr, SREG		; Input from SREG -> Disp_Decr
	push Disp_Decr			; Push Disp_Decr to stack
	ldi Disp_Decr, 8		; loop -> test all 8 bits
loop:
	rol Disp_Queue			; rotate left through Carry
	BRCS set_ser			; branch if Carry is set
	cbi PORTB,0				; clear SER (SER -> 0)
rjmp end
set_ser:
	sbi PORTB,0				; set SER (SER -> 1)
end:
	; generate SRCLK pulse
	sbi PORTB,2				; SRCLK on
	nop						; pause to help circuit catch up
	cbi PORTB,2				; SRCLK off
	dec Disp_Decr
	brne loop
	
	; generate RCLK pulse
	sbi PORTB,1				; RCLK on
	nop						; pause to help circuit catch up
	cbi PORTB,1				; RCLK off

	; restore registers from stack
	pop Disp_Decr
	out SREG, Disp_Decr
	pop Disp_Decr
	pop Disp_Queue
	ret

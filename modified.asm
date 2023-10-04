;====================================
; StopwatchLab2.asm
;
; Created: 10/03/2023 7:02:54 PM
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
.def Digit_Count = R18	; Keeps track of which values are to be displayed
.def Ctrl_Reg = R19		; Custom state register
.def Temp = R22			; Temporary register used to assist with converting a display pattern to the same pattern but with the tens mode light on


; Custom state register masks
.equ PB_State = 0b00000001		; bit 0: button A was pressed   (0:None    | 1:Pressed)
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
rjmp start
patterns:
	.dw 0x4040	; --
	.dw 0x3F3F	; 00
	.dw 0x3F06	; 01
	.dw 0x3F5B	; 02
	.dw 0x3F4F	; 03
	.dw 0x3F66	; 04
	.dw 0x3F6D	; 05
	.dw 0x3F7D	; 06
	.dw 0x3F07	; 07
	.dw 0x3F7F	; 08
	.dw 0x3F67	; 09
	.dw 0x063F	; 10
	.dw 0x0606	; 11
	.dw 0x065B	; 12
	.dw 0x064F	; 13
	.dw 0x0666	; 14
	.dw 0x066D	; 15
	.dw 0x067D	; 16
	.dw 0x0607	; 17
	.dw 0x067F	; 18
	.dw 0x0667	; 19
	.dw 0x5B3F	; 20
	.dw 0x5B06	; 21
	.dw 0x5B5B	; 22
	.dw 0x5B4F	; 23
	.dw 0x5B66	; 24
	.dw 0x5B6D	; 25
	.dw 0x5B7D	; 26
	.dw 0x5B07	; 27
	.dw 0x5B7F	; 28
	.dw 0x5B67	; 29
	.dw 0x4F3F	; 30
	.dw 0x4F06	; 31
	.dw 0x4F5B	; 32
	.dw 0x4F4F	; 33
	.dw 0x4F66	; 34
	.dw 0x4F6D	; 35
	.dw 0x4F7D	; 36
	.dw 0x4F07	; 37
	.dw 0x4F7F	; 38
	.dw 0x4F67	; 39
	.dw 0x663F	; 40
	.dw 0x6606	; 41
	.dw 0x665B	; 42
	.dw 0x664F	; 43
	.dw 0x6666	; 44
	.dw 0x666D	; 45
	.dw 0x667D	; 46
	.dw 0x6607	; 47
	.dw 0x667F	; 48
	.dw 0x6667	; 49
	.dw 0x6D3F	; 50
	.dw 0x6D06	; 51
	.dw 0x6D5B	; 52
	.dw 0x6D4F	; 53
	.dw 0x6D66	; 54
	.dw 0x6D6D	; 55
	.dw 0x6D7D	; 56
	.dw 0x6D07	; 57
	.dw 0x6D7F	; 58
	.dw 0x6D67	; 59
	.dw 0x7D3F	; 60

;===================| Main Loop |====================
start:
	ldi ZH, high(Patterns)	; Move pointer to front of Digit_Patterns
	ldi ZL, low(Patterns)

	ldi Disp_Queue, 0x39 
	rcall display

main:
	sbrc Ctrl_Reg, 1	;
	rcall CW			;

	sbrc Ctrl_Reg, 2	;
	rcall CCW			;

	sbrs Ctrl_Reg, 0	;
	rcall Button		; 

rjmp main

;===================| Functions |====================
CW:
	CWL1:
		sbrc Ctrl_Reg, 2
	brne CWL1
	ldi Disp_Queue, 0x77
	rcall display
ret

CCW:
	CCWL1:
		sbrc Ctrl_Reg, 1
	brne CWL1
	ldi Disp_Queue, 0x7C
	rcall display
ret

Button:
	ABL1:
		sbrc Ctrl_Reg, 2
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

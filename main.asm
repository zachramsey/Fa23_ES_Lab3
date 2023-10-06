;====================================
; StopwatchLab2.asm
;
; Created: 9/12/2023 7:02:54 PM
; Authors: Trey Vokoun & Zach Ramsey
;====================================

.include "m328Pdef.inc" ; microcontroller-specific definitions
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
.def Disp_Queue_0 = R16		; Data queue for next digit to be displayed
.def Disp_Queue_1 = R17		; Data queue for next digit to be displayed
.def Disp_Decr = R18		; Count of remaining bits to be pushed from Disp_Queue; decrements from 8
.def Digit_Count = R19		; Keeps track of which values are to be displayed
.def Ctrl_Reg = R20			; Custom state register
.def RPG_Curr = R21			; Current RPG input state
.def RPG_Bckp = R22			; Backup current RPG input state
.def RPG_Prev = R23			; previous RPG input state

; Custom state register masks
.equ PB_State = 0b00000001		; bit 0: button A was pressed   (0:None     | 1:Pressed)
.equ RPG_A = 0b00000010			; [unused] bit 1: A_RPG activation		(0:Inactive | 1:Active)
.equ RPG_B = 0b00000100			; [unused] bit 2: B_RPG activation		(0:Inactive | 1:Active)
.equ Run_State = 0b00001000		; bit 3: incrementing state     (0:Stopped  | 1:Running)
.equ Reset_State = 0b00010000	; bit 4: reset state            (0:None     | 1:Reset)
.equ Ovrflw = 0b00100000		; bit 5: overflow state         (0:None     | 1:Overflow)

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

;===================| Main Loop |====================
init:
	ldi Ctrl_Reg, 0x00		; initialize Ctrl_Reg
	ldi Disp_Queue_0, 0x40	; initialize display
	rcall display
	rcall display

main:
	sbis PIND,7				; If PB is pressed -> Jump to Pressed
	rcall Pressed

	in RPG_Curr, PIND		; Load current input state
	andi RPG_Curr, 0x60		; Mask bits 6 and 5
	mov RPG_Bckp, RPG_Curr	; Backup current input state
	cp RPG_Curr, RPG_Prev	; Compare current input state to previous input state
	brne RPG_Change			; If input state has changed, jump to RPG_Change

	rjmp main

;===================| Functions |====================
Pressed:
	sbr Ctrl_Reg, PB_State
	sbis PIND, 7			; if PB released, skip
	rjmp Pressed
	ldi Disp_Queue_0, 0x7C	; <- replace w/ pushbutton functionality from here
	rcall display
	ldi Disp_Queue_0, 0x73
	rcall display			; <- to here
	ret
	
RPG_Change:
	lsr RPG_Curr			; shift right
	andi RPG_Curr, 0x20		; mask bit 5
	eor RPG_Prev, RPG_Curr	; XOR current input state with previous input state
	sbrc RPG_Prev, 5		; if current A and previous B are the same, skip
	rjmp CCW
CW:
	ldi Disp_Queue_0, 0x50
	rcall display
	ldi Disp_Queue_0, 0x00
	rcall display			; <- replace to here w/ CW functionality
	mov RPG_Prev, RPG_Bckp	; restore previous input state
	rjmp main
CCW:
	ldi Disp_Queue_0, 0x00
	rcall display
	ldi Disp_Queue_0, 0x38
	rcall display			; <- replace to here w/ CCW functionality
	mov RPG_Prev, RPG_Bckp	; restore previous input state
	rjmp main

;============| Display Digit Subroutine |============
display:
	; backup used registers on stack
	push Disp_Queue_0		; Push Disp_Queue to stack
	push Disp_Decr			; Push Disp_Decr to stack
	in Disp_Decr, SREG		; Input from SREG -> Disp_Decr
	push Disp_Decr			; Push Disp_Decr to stack
	ldi Disp_Decr, 8		; loop -> test all 8 bits
loop:
	rol Disp_Queue_0		; rotate left through Carry
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
	pop Disp_Queue_0
	ret

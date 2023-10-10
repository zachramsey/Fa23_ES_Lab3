;====================================
; RPG_Lab03.asm
;
; Created: 10/3/2023 7:02:54 PM
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


;==============| Configure Registers |===============
.def Disp_Queue = R16		; Data queue for next digit to be displayed
.def Disp_Decr = R17		; Count of remaining bits to be pushed from Disp_Queue; decrements from 8
.def RPG_Curr = R18			; Current RPG input state
.def RPG_Prev = R19			; previous RPG input state
.def Ptrn_Cnt = R20			; Pattern counter
.def Tmp_Reg = R21			; Temporary register
.def Tmp_Reg2 = R22			; Secondary Temporary Register
.def Tmr_Cnt = R23			; Timer counter
.def Ctrl_Reg = R24			; Custom state register

; Custom state register masks
.equ PB_State = 0x01		; bit 0: button A was pressed   (0:None     | 1:Pressed)
.equ Prev_RPG_A = 0x02		; bit 1: A_RPG activation		(0:Inactive | 1:Active)
.equ Prev_RPG_B = 0x04		; bit 2: B_RPG activation		(0:Inactive | 1:Active)
.equ Run_State = 0x08		; bit 3: incrementing state     (0:Stopped  | 1:Running)
.equ Reset_State = 0x10		; bit 4: reset state            (0:None     | 1:Reset)
.equ Ovrflw = 0x20			; bit 5: overflow state         (0:None     | 1:Overflow)

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


;=========| Load Digit Patterns |==========
rjmp Init	; don't execute data!
Ptrns:
	.dw 0x4040	; --
	.dw 0x3F3F, 0x3F06, 0x3F5B, 0x3F4F, 0x3F66, 0x3F6D, 0x3F7D, 0x3F07, 0x3F7F, 0x3F67	; 0s
	.dw 0x063F, 0x0606, 0x065B, 0x064F, 0x0666, 0x066D, 0x067D, 0x0607, 0x067F, 0x0667	; 10s
	.dw 0x5B3F, 0x5B06, 0x5B5B, 0x5B4F, 0x5B66, 0x5B6D, 0x5B7D, 0x5B07, 0x5B7F, 0x5B67	; 20s
	.dw 0x4F3F, 0x4F06, 0x4F5B, 0x4F4F, 0x4F66, 0x4F6D, 0x4F7D, 0x4F07, 0x4F7F, 0x4F67	; 30s
	.dw 0x663F, 0x6606, 0x665B, 0x664F, 0x6666, 0x666D, 0x667D, 0x6607, 0x667F, 0x6667	; 40s
	.dw 0x6D3F, 0x6D06, 0x6D5B, 0x6D4F, 0x6D66, 0x6D6D, 0x6D7D, 0x6D07, 0x6D7F, 0x6D67	; 50s
	.dw 0x7D3F	; 60


;===================| Main Loop |====================
Init:
	; initialize timer0; we want 1s intervals
	; |	Time = 2^bits / (clock/prescaler) * counter
	; |	Time = 2^8 / (16MHz/1024) * 61 = 0.999424s
	; |	%E = [(1s - 0.999424s) / 1s] * 100 = 0.0576%
	ldi Tmr_Cnt, 61		; load timer counter
	ldi Tmp_Reg, 0x05		; configure prescaler to 1024
	out TCCR0B, Tmp_Reg	; output configuration to TCCR0B

	; initialize Z pointer to Ptrns
	ldi R30, low(Ptrns<<1)	; Load low byte of Patterns address
	ldi R31, high(Ptrns<<1)	; Load high byte of Patterns address
	rcall Load_Pattern		; load initial pattern

	; clear registers
	clr Ctrl_Reg			; initialize Ctrl_Reg
	clr Ptrn_Cnt			; initialize pattern counter

Main:
	; check for button press
	sbis PIND,7				; If PB is pressed -> Jump to Pressed
	rjmp Pressed

	; check for rotation
	in RPG_Curr, PIND
	andi RPG_Curr, 0x60		; Mask bits 6 and 5
	cpi RPG_Curr, 0x60		; if both are set, jump to RPG_Detent
	breq RPG_Detent
	mov RPG_Prev, RPG_Curr	; otherwise update previous input state

	rjmp Main				; loop Main
	

;===================| Functions |====================
Running: 
	sbi PORTB, 3			; Turn on status LED. Not sure if this is the best spot. 
	RunL1:					; implemented to prevent repeatedly turning on the LED

	in Tmp_Reg, TIFR0		; load timer0 interrupt flag register
	sbrs Tmp_Reg, 0			; if overflow flag is not set, loop RunL1
	rjmp RunL1

	ldi Tmp_Reg, (1<<TOV0)	; clear overflow flag by setting logic 1?
	out TIFR0, Tmp_Reg		; store timer0 interrupt flag register
	dec Tmr_Cnt				; decrement timer counter
	brne RunL1				; if timer counter is not 0, jump to RunL1
	ldi Tmr_Cnt, 61			; otherwise, reload timer counter

	cpi Ptrn_Cnt, 0			; if pattern counter is at beginning of array, jump to main
	breq Main
	dec Ptrn_Cnt			; decrement pattern counter
	sbiw zh:zl, 3			; decrement Z pointer
	rcall Load_Pattern
	cpi Ptrn_Cnt, 1			; if pattern counter is at zero turn off status LEDs
	breq LEDoff				; breaks to LEDoff routine
	rjmp RunL1				; Jump to RunL1, again to avoid turning on the led repeatedly. 

	LEDoff:
		cbi PORTB, 3		; turn off status leds
	rjmp RunL1				; jump back to finish countdown to --


Pressed:
	;start a timer
	;How do you start it?

	PressedL1:				; 
		
		in Tmp_reg, TIFR0
		sbrs Tmp_Reg, TOV0	;Is the timer at zero? Yes = bit set, so run Tmr_Zero routine
		rjmp End_Tmr_Zero	;Jump over Tmr_Zero
			Tmr_Zero:
				;Stop timer 0
				in Tmp_Reg, TCCR0B			;save config
				ldi Tmp_Reg2, 0x00			;Stop timer 0				
				out TCCR0B, Tmp_Reg2

				;clear overflow flag
				in Tmp_Reg2, TIFR0			;tmp <- TIFR0
				sbr Tmp_Reg2, 1<<TOV0		;clear TOV0, write logic 1
				out TIFR0, Tmp_Reg2
				;reset timer
			End_Tmr_Zero:
		sbis PIND, 7		;Skip if button set AKA run if button released
			rjmp Running	;Jump to running 

		rjmp PressedL1		;Jump to Inner loop so we dont re-initialize the timer
	
	;Is button released?
		;No? has the timer reached zero?
			;Yes? reset
		;Yes Start countdown by jumping to running
	rjmp Main
	
RPG_Detent:
	cpi RPG_Prev, 0x20 		; if prev state was '01', jump to Incr
	breq Incr
	cpi RPG_Prev, 0x40 		; if prev state was '10', jump to Decr
	breq Decr
	rjmp Main				; otherwise, jump to Main
Incr:
	ldi RPG_Prev, 0x60		; set detent input state
	cpi Ptrn_Cnt, 61		; if pattern counter is at end of array, jump to main
	breq Main
	inc Ptrn_Cnt			; increment pattern counter
	adiw zh:zl, 1			; increment Z pointer
	rcall Load_Pattern
	rjmp Main
Decr:
	ldi RPG_Prev, 0x60		; set detent input state
	cpi Ptrn_Cnt, 0			; if pattern counter is at beginning of array, jump to main
	breq Main
	dec Ptrn_Cnt			; decrement pattern counter
	sbiw zh:zl, 3			; decrement Z pointer
	rcall Load_Pattern
	rjmp Main


;===============| Display Subroutines |===============
Load_Pattern:
	lpm Disp_Queue, Z+		; load first byte of word
	rcall display
	lpm Disp_Queue, Z		; load second byte of word
	rcall display
	ret

display:
	; backup used registers on stack
	push Disp_Queue		; Push Disp_Queue to stack
	push Disp_Decr			; Push Disp_Decr to stack
	in Disp_Decr, SREG		; Input from SREG -> Disp_Decr
	push Disp_Decr			; Push Disp_Decr to stack
	ldi Disp_Decr, 8		; loop -> test all 8 bits
loop:
	rol Disp_Queue		; rotate left through Carry
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

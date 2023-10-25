;====================================
;Lab4LCDDisplay.asm
;
; Created: 10/15/2023 7:02:54 PM
; Authors: Trey Vokoun & Zach Ramsey
;====================================

.include "m328Pdef.inc"		; microcontroller-specific definitions
.cseg
.cseg
.org 0x0000
jmp Start					; Skip to start

.org 0x0002					; INT0 vector
jmp INT0_ISR				; Jump to INT0 ISR

.org 0x000A					; PCINT2 vector
jmp PCINT2_ISR				; Jump to PCINT2 ISR

.org 0x0034					; Start of program memory
rjmp Start
msg:						; Create a static string in program memory.
	.DB "Hi John!  "
	.DW 0

Start:
;==================| Configure I/O |=================
; Inputs
cbi DDRD, 2					; uC PD7 (INT0)		 <- PBS (Pushbutton)
cbi DDRD, 4					; uC PD6 (PCINT[16]) <- RPG A
cbi DDRD, 5  				; uC PD5 (PCINT[17]) <- RPG B
; Outputs
sbi DDRB, 3  				; uC PB3 		-> LCD E (Enable)
sbi DDRB, 5					; uC PB5 		-> LCD RS (Register Select)
sbi DDRC, 0					; uC PC0 		-> LCD DB4
sbi DDRC, 1					; uC PC1 		-> LCD DB5
sbi DDRC, 2					; uC PC2 		-> LCD DB6
sbi DDRC, 3					; uC PC3 		-> LCD DB7
sbi DDRD, 3  				; uC PD3 (OC0B) -> Fan PWM

;==============| Configure Registers |===============
.def Tmp_Reg = R16			; Temporary register
.def Tmp_Data = R17			; Temporary data register
.def Tmr_Cnt = R18			; Timer counter
.def RPG_Curr = R19			; Current RPG input state
.def RPG_Prev = R20			; previous RPG input state
.def DC = R21				; Duty cycle counter


;==================| Initialize LCD |================
rcall Delay_100m			; wait to power up LCD

ldi Tmp_Data, 0x03			; Set 8-bit mode
rcall Send_Nibble
rcall Delay_5m

rcall Send_Nibble			; Set 8-bit mode
rcall Delay_200u

rcall Send_Nibble			; Set 8-bit mode
rcall Delay_200u

ldi Tmp_Data, 0x02			; Set 4-bit mode
rcall Send_Nibble
rcall Delay_5m

ldi Tmp_Data, 0x28			; Set interface
rcall Send_Instr
rcall Delay_100u

ldi Tmp_Data, 0x08			; dont shift display, hide cursor 
rcall Send_Instr
rcall Delay_100u

ldi Tmp_Data, 0x01			; Clear and home display
rcall Send_Instr
rcall Delay_5m

ldi Tmp_Data, 0x06			; move cursor right
rcall Send_Instr
rcall Delay_100u

ldi Tmp_Data, 0x0C			; turn on display
rcall Send_Instr
rcall Delay_100u

; display string on LCD for testing
rcall Send_String

;============| Initialize PWM on timer2 |============
ldi Tmp_Reg, 0				; clear timer0
sts TCNT2, Tmp_Reg

ldi Tmp_Reg, 200			; set timer0 TOP val to 200
sts OCR2A, Tmp_Reg

ldi Tmp_Reg, 0x23			; configure timer0 to Fast PWM (mode 7)
sts TCCR2A, Tmp_Reg
ldi Tmp_Reg, 0x09
sts TCCR2B, Tmp_Reg

ldi Tmp_Reg, 0				; set timer0 duty cycle to 0 (DC = OCR0B / 200)
sts OCR2B, Tmp_Reg

ldi DC, 0					; initialize duty cycle counter to 0

;=============| Initialize RPG Interupt |============
ldi Tmp_Reg, (1<<PCINT20) | (1<<PCINT21)	; enable PCINT20 and PCINT21
sts PCMSK2, Tmp_Reg
ldi Tmp_Reg, (1<<PCIE2)						; enable PCINT2
sts PCICR, Tmp_Reg

;=============| Initialize PBS Interupt |============
ldi Tmp_Reg, EICRA
sbr Tmp_Reg, (1<<ISC01) | (1<<ISC00)		; enable rising edge detection on INT0
sts EICRA, Tmp_Reg
sbi EIMSK, INT0								; enable INT0

;===================| Main Loop |====================
sei							; Enable interupts globally
Main:
	nop
	rjmp Main				; loop Main

;==============| PBS Interupt Handling |=============
INT0_ISR:
	lds Tmp_Reg, OCR2B		; load timer2 duty cycle into Tmp_Reg
	cpi Tmp_Reg, 5			; if timer2 duty cycle is DC, turn fan off
	brge Fan_Off
	sts OCR2B, DC			; otherwise, turn fan on
	rcall Delay_100u
	reti
Fan_Off:
	ldi Tmp_Reg, 0			; set timer2 duty cycle to 0
	sts OCR2B, Tmp_Reg
	rcall Delay_100u
	reti

;==============| RPG Interupt Handling |=============
PCINT2_ISR:
	in RPG_Curr, PIND
	andi RPG_Curr, 0x30		; Mask bits 5 and 4
	cpi RPG_Curr, 0x30		; if either is not set, return
	breq RPG_Detent
	mov RPG_Prev, RPG_Curr	; update RPG state
	reti
RPG_Detent:
	cpi RPG_Prev, 0x10 		; if prev state was '01', branch to Incr
	breq Incr
	cpi RPG_Prev, 0x20 		; if prev state was '10', branch to Decr
	breq Decr
	reti
Incr:
	ldi RPG_Prev, 0x30		; update RPG state to '11'
	cpi DC, 200				; if DC is at 100%, return
	breq PCINT2_Exit
	inc DC
	sts OCR2B, DC			; update timer0 duty cycle
	reti
Decr:
	ldi RPG_Prev, 0x30		; update RPG state to '11'
	cpi DC, 0				; if DC is at 0%, return
	breq PCINT2_Exit
	dec DC					; decrement DC counter
	sts OCR2B, DC			; update timer0 duty cycle
	reti
PCINT2_Exit:
	reti

;===============| LCD Communication |================
Send_String:
	ldi Tmp_Data, 0x80		; set DDRAM address to 0x00
	rcall Send_Instr
	sbi PORTB, 5			; set R/S | Data mode
	nop
	ldi r24, 10 			; r24 <-- length of the string
	ldi r30, LOW(2*msg) 	; Load Z register low
	ldi r31, HIGH(2*msg)	; Load Z register high
	Next_Char:
		lpm	Tmp_Data, Z+	; load byte from prog mem at Z in Tmp_Reg, post-increment Z
		sbi PORTB, 5		; set R/S | select data register
		cbi PORTB, 3		; clear Enable
		swap Tmp_Data		; swap nibbles
		rcall Send_Nibble	; send upper nibble
		swap Tmp_Data		; swap nibbles back
		rcall Send_Nibble	; send lower nibble
		dec r24				; Repeat until all characters are out
		brne Next_Char
		ret
Send_Instr:
	cbi PORTB, 5			; clear R/S | select instruction register
	cbi PORTB, 3			; clear Enable
	swap Tmp_Data			; swap nibbles
	rcall Send_Nibble		; send upper nibble
	swap Tmp_Data			; swap nibbles back
	rcall Send_Nibble		; send lower nibble
	ret
Send_Nibble:
	out PORTC, Tmp_Data		; send upper nibble
	nop
	sbi PORTB, 3			; drive E high (start strobe)
	nop						; 312 ns delay
	nop
	nop
	nop
	nop
	cbi PORTB, 3			; drive E low
	rcall Delay_100u		; give LCD time to process data
	ret

;==================| Time Delays |===================

Delay_100u:					; 112us delay
	ldi Tmr_Cnt,7			; set  timer overflow counter to 7
	ldi Tmp_Reg, 0x01		; set prescaler to none
	out TCCR0B, Tmp_Reg		; output prescaler configurationv
	rjmp Delay_loop			; begin delay
Delay_200u:					; 208us delay
	ldi Tmr_Cnt, 13			; set timer overflow counter to 13
	ldi Tmp_Reg, 0x01		; set prescaler to none
	out TCCR0B, Tmp_Reg		; output prescaler configuration
	rjmp Delay_loop			; begin delay
Delay_5m:					; 5.12ms delay
	ldi Tmr_Cnt, 40			; set timer overflow counter to 40
	ldi Tmp_Reg, 0x02		; set prescaler to 8
	out TCCR0B, Tmp_Reg		; output prescaler configuration
	rjmp Delay_loop			; begin delay
Delay_100m:					; 100.35ms delay
	ldi Tmr_Cnt, 98			; set timer overflow counter to 98
	ldi Tmp_Reg, 0x03		; set prescaler to 64
	out TCCR0B, Tmp_Reg		; output prescaler configuration
	rjmp Delay_loop			; begin delay
Delay_loop:
	in Tmp_Reg, TIFR0		; input timer2 interrupt flag register
	sbrs Tmp_Reg, 0			; if overflow flag is not set, loop
	rjmp Delay_loop

	ldi Tmp_Reg, (1<<TOV0)	; acknowledge overflow flag
	out TIFR0, Tmp_Reg		; output to timer0 interrupt flag register

	dec Tmr_Cnt				; Decrement Timer counter
	brne Delay_loop			; if Timer counter is zero, loop
	ret						; otherwise, return

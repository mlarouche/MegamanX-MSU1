arch snes.cpu

// MSU memory map I/O
constant MSU_STATUS($2000)
constant MSU_ID($2002)
constant MSU_AUDIO_TRACK_LO($2004)
constant MSU_AUDIO_TRACK_HI($2005)
constant MSU_AUDIO_VOLUME($2006)
constant MSU_AUDIO_CONTROL($2007)

// SPC communication ports
constant SPC_COMM_0($2140)

// MSU_STATUS possible values
constant MSU_STATUS_TRACK_MISSING($8)
constant MSU_STATUS_AUDIO_PLAYING(%00010000)
constant MSU_STATUS_AUDIO_REPEAT(%00100000)
constant MSU_STATUS_AUDIO_BUSY($40)
constant MSU_STATUS_DATA_BUSY(%10000000)

// Constants
if {defined EMULATOR_VOLUME} {
	constant FULL_VOLUME($50)
	constant DUCKED_VOLUME($20)
} else {
	constant FULL_VOLUME($FF)
	constant DUCKED_VOLUME($60)
}

constant FADE_DELTA(FULL_VOLUME/45)

// Variables
variable fadeState($180)
variable fadeVolume($181)

// FADE_STATE possibles values
constant FADE_STATE_IDLE($00)
constant FADE_STATE_FADEOUT($01)
constant FADE_STATE_FADEIN($02)

// **********
// * Macros *
// **********
// seek converts SNES LoROM address to physical address
macro seek(variable offset) {
  origin ((offset & $7F0000) >> 1) | (offset & $7FFF)
  base offset
}

macro CheckMSUPresence(labelToJump) {
	lda.w MSU_ID
	cmp.b #'S'
	bne {labelToJump}
}

// Fade-in/Fade-out hijack in NMI routine
seek($80817A)
	jsr MSU_FadeUpdate
	
// Add a hook to where the sound effects/special commands are played
seek($80885B)
	jsr MSU_SoundEffectsAndCommand

// At Capcom logo, init the required variables
seek($808613)
	jsr MSU_Init

// Play music from Options Screen, All music after level music, Password Screen, Stage Select
seek($8087AA)
	jsr MSU_Main

// Play Title Screen
seek($808D8F)
	jsr MSU_Main
	
// Play music at level load
seek($809A2D)
	jmp MSU_Main

// Play stage selected jingle
seek($809709)
	jsr MSU_Main
	
// Ending ??
seek($809CFA)
	jsr MSU_Main

// Got a weapon
seek($80ABD6)
	jsr MSU_Main

// A = Music to play + $10
seek($80FBD0)
scope MSU_Main: {
	php
// Backup A and Y in 16bit mode
	rep #$30
	pha
	phy
	
	sep #$30 // Set all registers to 8 bit mode
	tay
	
	// Check if MSU-1 is present
	CheckMSUPresence(MSUNotFound)
	
	// Set track
	tya
	sec
	sbc.b #$10
	tay
	sta.w MSU_AUDIO_TRACK_LO
	stz.w MSU_AUDIO_TRACK_HI

CheckAudioStatus:
	lda.w MSU_STATUS
	
	and.b #MSU_STATUS_AUDIO_BUSY
	bne CheckAudioStatus
	
	// Check if track is missing
	lda.w MSU_STATUS
	and.b #MSU_STATUS_TRACK_MISSING
	bne MSUNotFound
	
	// Play the song and add repeat if needed
	jsr TrackNeedLooping
	sta.w MSU_AUDIO_CONTROL
	
	// Set volume
	lda.b #FULL_VOLUME
	sta.w MSU_AUDIO_VOLUME
	
	// Reset the fade state machine
	lda.b #$00
	sta.w fadeState
	
	rep #$30
	ply
	pla
	plp
	rts
	
// Call original routine if MSU-1 is not found
MSUNotFound:
	rep #$30
	ply
	pla
	plp
	
	jsr $87B0
	rts
}

scope MSU_Init: {
	php
	sep #$30
	pha
	
	CheckMSUPresence(MSUNotFound)
	
	// Set volume
	lda.b #FULL_VOLUME
	sta.w MSU_AUDIO_VOLUME
	
	// Reset the fade state machine
	lda.b #$00
	sta.w fadeState

MSUNotFound:
	pla
	plp
	
	jsr $87B0
	
	rts
}

scope TrackNeedLooping: {
// Capcom Jingle
	cpy.b #$00
	beq NoLooping
// Title Screen
	cpy.b #$0F
	beq NoLooping
// Victory Jingle
	cpy.b #$11
	beq NoLooping
// Stage Selected Jingle
	cpy.b #$12
	beq NoLooping
// Got a Weapon
	cpy.b #$17
	beq NoLooping
// Boss Tension 1
	cpy.b #$1E
	beq NoLooping
	lda.b #$03
	rts
NoLooping:
	lda.b #$01
	rts
}
	
scope MSU_SoundEffectsAndCommand: {
	php
	
	sep #$30
	pha
	
	CheckMSUPresence(MSUNotFound)
	
	pla
	// $F5 is a command to resume music
	cmp.b #$F5
	beq .ResumeMusic
	// $F6 is a command to fade-out music
	cmp.b #$F6
	beq .StopMusic
	// $FE is a command to raise volume back to full volume coming from pause menu
	cmp.b #$FE
	beq .RaiseVolume
	// $FF is a command to drop volume when going to pause menu
	cmp.b #$FF
	beq .DropVolume
	// If not, play the sound as the game excepts to
	bra .PlaySound
	
.ResumeMusic:
	// Stop the SPC music if any
	lda.b #$F6
	sta.w SPC_COMM_0
	
	// Resume music then fade-in to full volume
	lda.b #$03
	sta.w MSU_AUDIO_CONTROL
	lda.b #FADE_STATE_FADEIN
	sta.w fadeState
	lda.b #$00
	sta.w fadeVolume
	bra .CleanupAndReturn

.StopMusic:
	sta.w SPC_COMM_0

	lda.w MSU_STATUS
	and.b #MSU_STATUS_AUDIO_PLAYING
	beq .CleanupAndReturn

	// Fade-out current music then stop it
	lda.b #FADE_STATE_FADEOUT
	sta.w fadeState
	lda.b #FULL_VOLUME
	sta.w fadeVolume
	bra .CleanupAndReturn

.RaiseVolume:
	sta.w SPC_COMM_0
	lda.b #FULL_VOLUME
	sta.w MSU_AUDIO_VOLUME
	bra .CleanupAndReturn
	
.DropVolume:
	sta.w SPC_COMM_0
	lda.b #DUCKED_VOLUME
	sta.w MSU_AUDIO_VOLUME
	bra .CleanupAndReturn
	
MSUNotFound:
	pla
.PlaySound:
	sta.w SPC_COMM_0
.CleanupAndReturn:
	plp
	rts
}

scope MSU_FadeUpdate: {
	// Original code I hijacked that increase the real frame counter
	inc $0B9E
	
	php
	sep #$30
	pha
	
	CheckMSUPresence(MSUNotFound)
	
	// Switch on fade state
	lda.w fadeState
	cmp.b #FADE_STATE_IDLE
	beq MSUNotFound
	cmp.b #FADE_STATE_FADEOUT
	beq .FadeOutUpdate
	cmp.b #FADE_STATE_FADEIN
	beq .FadeInUpdate
	bra MSUNotFound
	
.FadeOutUpdate:
	lda.w fadeVolume
	sec
	sbc.b #FADE_DELTA
	bcs +
	lda.b #$00
+;
	sta.w fadeVolume
	sta.w MSU_AUDIO_VOLUME
	beq .FadeOutCompleted
	bra MSUNotFound
	
.FadeInUpdate:
	lda.w fadeVolume
	clc
	adc.b #FADE_DELTA
	bcc +
	lda.b #FULL_VOLUME
+;
	sta.w fadeVolume
	sta.w MSU_AUDIO_VOLUME
	cmp.b #FULL_VOLUME
	beq .SetToIdle
	bra MSUNotFound

.FadeOutCompleted:
	lda.b #$00
	sta.w MSU_AUDIO_CONTROL
.SetToIdle:
	lda.b #FADE_STATE_IDLE
	sta.w fadeState

MSUNotFound:
	pla
	plp
	rts
}

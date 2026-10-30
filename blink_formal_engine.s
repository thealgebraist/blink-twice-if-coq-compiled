	.build_version macos, 27, 0	sdk_version 27, 0
	.section	__TEXT,__text,regular,pure_instructions
	.globl	_collapse_margins               ; -- Begin function collapse_margins
	.p2align	2
_collapse_margins:                      ; @collapse_margins
	.cfi_startproc
; %bb.0:
	cmp	x0, x1
	csel	x0, x0, x1, gt
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_resolve_percent_col_width      ; -- Begin function resolve_percent_col_width
	.p2align	2
_resolve_percent_col_width:             ; @resolve_percent_col_width
	.cfi_startproc
; %bb.0:
	mul	x8, x1, x0
	mov	x9, #55051                      ; =0xd70b
	movk	x9, #28835, lsl #16
	movk	x9, #2621, lsl #32
	movk	x9, #41943, lsl #48
	smulh	x9, x8, x9
	add	x8, x9, x8
	asr	x9, x8, #6
	add	x0, x9, x8, lsr #63
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_button_inline_size             ; -- Begin function button_inline_size
	.p2align	2
_button_inline_size:                    ; @button_inline_size
	.cfi_startproc
; %bb.0:
	add	x8, x2, x1
	add	x8, x0, x8, lsl #1
	cmp	x3, #0
	csel	x0, x3, x8, gt
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_button_block_size              ; -- Begin function button_block_size
	.p2align	2
_button_block_size:                     ; @button_block_size
	.cfi_startproc
; %bb.0:
	add	x8, x2, x1
	add	x8, x0, x8, lsl #1
	cmp	x3, #0
	csel	x0, x3, x8, gt
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_get_sample_interactive_page    ; -- Begin function get_sample_interactive_page
	.p2align	2
_get_sample_interactive_page:           ; @get_sample_interactive_page
	.cfi_startproc
; %bb.0:
Lloh0:
	adrp	x9, l___const.get_sample_interactive_page.page@PAGE
Lloh1:
	add	x9, x9, l___const.get_sample_interactive_page.page@PAGEOFF
	ldp	q0, q1, [x9, #128]
	stp	q0, q1, [x8, #128]
	ldp	q0, q1, [x9, #160]
	stp	q0, q1, [x8, #160]
	ldp	q0, q1, [x9, #64]
	stp	q0, q1, [x8, #64]
	ldp	q0, q1, [x9, #96]
	stp	q0, q1, [x8, #96]
	ldp	q0, q1, [x9]
	stp	q0, q1, [x8]
	ldp	q0, q1, [x9, #32]
	stp	q0, q1, [x8, #32]
	ret
	.loh AdrpAdd	Lloh0, Lloh1
	.cfi_endproc
                                        ; -- End function
	.globl	_layout_interactive_page_pipeline ; -- Begin function layout_interactive_page_pipeline
	.p2align	2
_layout_interactive_page_pipeline:      ; @layout_interactive_page_pipeline
	.cfi_startproc
; %bb.0:
	stp	x20, x19, [sp, #-16]!           ; 16-byte Folded Spill
	.cfi_def_cfa_offset 16
	.cfi_offset w19, -8
	.cfi_offset w20, -16
	ldp	x9, x10, [x2]
	add	x10, x10, #8
	ldp	x12, x11, [x2, #16]
	ldp	x13, x14, [x2, #32]
	cmp	x12, x13
	csel	x12, x12, x13, gt
	add	x13, x10, x9
	add	x12, x13, x12
	ldp	x13, x15, [x2, #64]
	cmp	x14, x13
	csel	x13, x14, x13, gt
	add	x13, x11, x13
	add	x13, x12, x13
	ldp	x14, x16, [x2, #48]
	mul	x14, x16, x14
	ldp	x17, x16, [x2, #96]
	cmp	x15, x16
	csel	x15, x15, x16, gt
	add	x15, x13, x15
	add	x15, x14, x15
	sub	x16, x0, #16
	ldp	x3, x4, [x2, #80]
	mul	x3, x3, x16
	mov	x5, #55051                      ; =0xd70b
	movk	x5, #28835, lsl #16
	movk	x5, #2621, lsl #32
	movk	x5, #41943, lsl #48
	smulh	x6, x3, x5
	add	x3, x6, x3
	asr	x6, x3, #6
	add	x3, x6, x3, lsr #63
	mul	x16, x4, x16
	smulh	x4, x16, x5
	add	x16, x4, x16
	asr	x4, x16, #6
	add	x16, x4, x16, lsr #63
	ldp	x4, x5, [x2, #112]
	ldp	x6, x7, [x2, #128]
	cmp	x4, x6
	csel	x4, x4, x6, gt
	add	x4, x17, x4
	add	x4, x15, x4
	ldp	x19, x6, [x2, #168]
	cmp	x7, x6
	csel	x6, x7, x6, gt
	add	x6, x5, x6
	add	x6, x4, x6
	ldr	x7, [x2, #160]
	add	x7, x19, x7
	lsl	x7, x7, #1
	stp	x0, x1, [x8]
	stp	x10, x9, [x8, #16]
	stp	x12, x11, [x8, #32]
	stp	x13, x14, [x8, #48]
	stp	x15, x17, [x8, #64]
	stp	x3, x16, [x8, #80]
	stp	x4, x5, [x8, #96]
	str	x6, [x8, #112]
	ldr	q0, [x2, #144]
	dup.2d	v1, x7
	add.2d	v0, v1, v0
	stur	q0, [x8, #120]
	ldp	x20, x19, [sp], #16             ; 16-byte Folded Reload
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_fb_create                      ; -- Begin function fb_create
	.p2align	2
_fb_create:                             ; @fb_create
	.cfi_startproc
; %bb.0:
	stp	x22, x21, [sp, #-48]!           ; 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             ; 16-byte Folded Spill
	stp	x29, x30, [sp, #32]             ; 16-byte Folded Spill
	add	x29, sp, #32
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_offset w21, -40
	.cfi_offset w22, -48
	mov	x19, x2
	mov	x20, x1
	mov	x21, x0
	mov	w0, #24                         ; =0x18
	bl	_malloc
	cbz	x0, LBB6_17
; %bb.1:
	stp	x21, x20, [x0]
	mul	x8, x21, x20
	lsl	x8, x8, #2
	mov	x22, x0
	mov	x0, x8
	bl	_malloc
	mov	x8, x0
	mov	x0, x22
	str	x8, [x22, #16]
	cbz	x8, LBB6_5
; %bb.2:
	mul	x9, x20, x21
	cmp	x9, #1
	b.lt	LBB6_17
; %bb.3:
	cmp	x9, #3
	b.hi	LBB6_6
; %bb.4:
	mov	x10, #0                         ; =0x0
	b	LBB6_15
LBB6_5:
	bl	_free
	mov	x0, #0                          ; =0x0
	ldp	x29, x30, [sp, #32]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp, #16]             ; 16-byte Folded Reload
	ldp	x22, x21, [sp], #48             ; 16-byte Folded Reload
	ret
LBB6_6:
	dup.4s	v0, w19
	cmp	x9, #16
	b.hs	LBB6_8
; %bb.7:
	mov	x10, #0                         ; =0x0
	b	LBB6_12
LBB6_8:
	and	x10, x9, #0x7ffffffffffffff0
	add	x11, x8, #32
	mov	x12, x10
LBB6_9:                                 ; =>This Inner Loop Header: Depth=1
	stp	q0, q0, [x11, #-32]
	stp	q0, q0, [x11], #64
	subs	x12, x12, #16
	b.ne	LBB6_9
; %bb.10:
	cmp	x9, x10
	b.eq	LBB6_17
; %bb.11:
	tst	x9, #0xc
	b.eq	LBB6_15
LBB6_12:
	mov	x12, x10
	and	x10, x9, #0x7ffffffffffffffc
	sub	x11, x12, x10
	add	x12, x8, x12, lsl #2
LBB6_13:                                ; =>This Inner Loop Header: Depth=1
	str	q0, [x12], #16
	adds	x11, x11, #4
	b.ne	LBB6_13
; %bb.14:
	cmp	x9, x10
	b.eq	LBB6_17
LBB6_15:
	sub	x9, x9, x10
	add	x8, x8, x10, lsl #2
LBB6_16:                                ; =>This Inner Loop Header: Depth=1
	str	w19, [x8], #4
	subs	x9, x9, #1
	b.ne	LBB6_16
LBB6_17:
	ldp	x29, x30, [sp, #32]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp, #16]             ; 16-byte Folded Reload
	ldp	x22, x21, [sp], #48             ; 16-byte Folded Reload
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_fb_destroy                     ; -- Begin function fb_destroy
	.p2align	2
_fb_destroy:                            ; @fb_destroy
	.cfi_startproc
; %bb.0:
	cbz	x0, LBB7_4
; %bb.1:
	ldr	x8, [x0, #16]
	cbz	x8, LBB7_3
; %bb.2:
	stp	x20, x19, [sp, #-32]!           ; 16-byte Folded Spill
	stp	x29, x30, [sp, #16]             ; 16-byte Folded Spill
	add	x29, sp, #16
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	mov	x19, x0
	mov	x0, x8
	bl	_free
	mov	x0, x19
	ldp	x29, x30, [sp, #16]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp], #32             ; 16-byte Folded Reload
LBB7_3:
	b	_free
LBB7_4:
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_fb_fill_rect                   ; -- Begin function fb_fill_rect
	.p2align	2
_fb_fill_rect:                          ; @fb_fill_rect
	.cfi_startproc
; %bb.0:
	cbz	x0, LBB8_7
; %bb.1:
	ldr	x8, [x0, #16]
	cbz	x8, LBB8_7
; %bb.2:
	bic	x8, x1, x1, asr #63
	bic	x9, x2, x2, asr #63
	ldp	x10, x11, [x0]
	add	x12, x3, x1
	cmp	x12, x10
	csel	x10, x12, x10, lt
	add	x12, x4, x2
	cmp	x12, x11
	csel	x11, x12, x11, lt
	cmp	x9, x11
	ccmp	x8, x10, #0, lt
	b.ge	LBB8_7
; %bb.3:
	lsl	x12, x9, #2
LBB8_4:                                 ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB8_5 Depth 2
	mov	x13, x8
LBB8_5:                                 ;   Parent Loop BB8_4 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x14, [x0, #16]
	ldr	x15, [x0]
	madd	x14, x12, x15, x14
	str	w5, [x14, x13, lsl #2]
	add	x13, x13, #1
	cmp	x10, x13
	b.ne	LBB8_5
; %bb.6:                                ;   in Loop: Header=BB8_4 Depth=1
	add	x9, x9, #1
	add	x12, x12, #4
	cmp	x9, x11
	b.ne	LBB8_4
LBB8_7:
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_fb_draw_border                 ; -- Begin function fb_draw_border
	.p2align	2
_fb_draw_border:                        ; @fb_draw_border
	.cfi_startproc
; %bb.0:
	cbz	x0, LBB9_28
; %bb.1:
	cmp	x5, #1
	b.lt	LBB9_28
; %bb.2:
	ldr	x8, [x0, #16]
	cbz	x8, LBB9_28
; %bb.3:
	bic	x9, x1, x1, asr #63
	bic	x11, x2, x2, asr #63
	ldp	x10, x13, [x0]
	add	x8, x3, x1
	cmp	x8, x10
	csel	x12, x8, x10, lt
	add	x10, x5, x2
	cmp	x10, x13
	csel	x13, x10, x13, lt
	cmp	x11, x13
	ccmp	x9, x12, #0, lt
	b.ge	LBB9_9
; %bb.4:
	lsl	x14, x11, #2
LBB9_5:                                 ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB9_6 Depth 2
	mov	x15, x9
LBB9_6:                                 ;   Parent Loop BB9_5 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x16, [x0, #16]
	ldr	x17, [x0]
	madd	x16, x14, x17, x16
	str	w6, [x16, x15, lsl #2]
	add	x15, x15, #1
	cmp	x12, x15
	b.ne	LBB9_6
; %bb.7:                                ;   in Loop: Header=BB9_5 Depth=1
	add	x11, x11, #1
	add	x14, x14, #4
	cmp	x11, x13
	b.ne	LBB9_5
; %bb.8:
	ldr	x11, [x0, #16]
	cbz	x11, LBB9_28
LBB9_9:
	add	x13, x4, x2
	sub	x11, x13, x5
	bic	x11, x11, x11, asr #63
	ldp	x12, x14, [x0]
	cmp	x8, x12
	csel	x12, x8, x12, lt
	cmp	x13, x14
	csel	x13, x13, x14, lt
	cmp	x11, x13
	b.ge	LBB9_16
; %bb.10:
	cmp	x9, x12
	b.ge	LBB9_16
; %bb.11:
	lsl	x14, x11, #2
LBB9_12:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB9_13 Depth 2
	mov	x15, x9
LBB9_13:                                ;   Parent Loop BB9_12 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x16, [x0, #16]
	ldr	x17, [x0]
	madd	x16, x14, x17, x16
	str	w6, [x16, x15, lsl #2]
	add	x15, x15, #1
	cmp	x12, x15
	b.ne	LBB9_13
; %bb.14:                               ;   in Loop: Header=BB9_12 Depth=1
	add	x11, x11, #1
	add	x14, x14, #4
	cmp	x11, x13
	b.ne	LBB9_12
; %bb.15:
	ldr	x11, [x0, #16]
	cbz	x11, LBB9_28
LBB9_16:
	sub	x13, x4, x5, lsl #1
	bic	x11, x10, x10, asr #63
	ldp	x12, x14, [x0]
	add	x15, x5, x1
	cmp	x15, x12
	csel	x12, x15, x12, lt
	add	x10, x13, x10
	cmp	x10, x14
	csel	x13, x10, x14, lt
	cmp	x11, x13
	b.ge	LBB9_23
; %bb.17:
	cmp	x9, x12
	b.ge	LBB9_23
; %bb.18:
	lsl	x14, x11, #2
	mov	x15, x11
LBB9_19:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB9_20 Depth 2
	mov	x16, x9
LBB9_20:                                ;   Parent Loop BB9_19 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x17, [x0, #16]
	ldr	x1, [x0]
	madd	x17, x14, x1, x17
	str	w6, [x17, x16, lsl #2]
	add	x16, x16, #1
	cmp	x12, x16
	b.ne	LBB9_20
; %bb.21:                               ;   in Loop: Header=BB9_19 Depth=1
	add	x15, x15, #1
	add	x14, x14, #4
	cmp	x15, x13
	b.ne	LBB9_19
; %bb.22:
	ldr	x9, [x0, #16]
	cbz	x9, LBB9_28
LBB9_23:
	sub	x9, x8, x5
	bic	x9, x9, x9, asr #63
	ldp	x12, x13, [x0]
	cmp	x8, x12
	csel	x8, x8, x12, lt
	cmp	x10, x13
	csel	x10, x10, x13, lt
	cmp	x11, x10
	ccmp	x9, x8, #0, lt
	b.ge	LBB9_28
; %bb.24:
	lsl	x12, x11, #2
LBB9_25:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB9_26 Depth 2
	mov	x13, x9
LBB9_26:                                ;   Parent Loop BB9_25 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x14, [x0, #16]
	ldr	x15, [x0]
	madd	x14, x12, x15, x14
	str	w6, [x14, x13, lsl #2]
	add	x13, x13, #1
	cmp	x8, x13
	b.ne	LBB9_26
; %bb.27:                               ;   in Loop: Header=BB9_25 Depth=1
	add	x11, x11, #1
	add	x12, x12, #4
	cmp	x11, x10
	b.ne	LBB9_25
LBB9_28:
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_fb_get_pixel                   ; -- Begin function fb_get_pixel
	.p2align	2
_fb_get_pixel:                          ; @fb_get_pixel
	.cfi_startproc
; %bb.0:
	cbz	x0, LBB10_8
; %bb.1:
	mov	x8, x0
	mov	w0, #0                          ; =0x0
	tbnz	x1, #63, LBB10_8
; %bb.2:
	ldr	x9, [x8, #16]
	cbz	x9, LBB10_8
; %bb.3:
	mov	w0, #0                          ; =0x0
	tbnz	x2, #63, LBB10_8
; %bb.4:
	ldr	x10, [x8]
	cmp	x1, x10
	b.ge	LBB10_8
; %bb.5:
	ldr	x8, [x8, #8]
	cmp	x2, x8
	b.ge	LBB10_7
; %bb.6:
	mul	x8, x10, x2
	add	x8, x9, x8, lsl #2
	ldr	w0, [x8, x1, lsl #2]
	ret
LBB10_7:
	mov	w0, #0                          ; =0x0
LBB10_8:
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_rasterize_interactive_page     ; -- Begin function rasterize_interactive_page
	.p2align	2
_rasterize_interactive_page:            ; @rasterize_interactive_page
	.cfi_startproc
; %bb.0:
	stp	x22, x21, [sp, #-48]!           ; 16-byte Folded Spill
	stp	x20, x19, [sp, #16]             ; 16-byte Folded Spill
	stp	x29, x30, [sp, #32]             ; 16-byte Folded Spill
	add	x29, sp, #32
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_offset w21, -40
	.cfi_offset w22, -48
	cbz	x0, LBB11_17
; %bb.1:
	mov	x19, x1
	cbz	x1, LBB11_17
; %bb.2:
	ldr	x21, [x19]
	ldr	x8, [x0, #16]
	cbz	x8, LBB11_18
; %bb.3:
	ldp	x12, x11, [x19, #16]
	bic	x9, x12, x12, asr #63
	sub	x8, x21, #8
	ldp	x10, x13, [x0]
	cmp	x8, x10
	csel	x10, x8, x10, lt
	add	x11, x12, x11
	cmp	x11, x13
	csel	x11, x11, x13, lt
	cmp	x9, x11
	ccmp	x10, #9, #8, lt
	b.lt	LBB11_9
; %bb.4:
	lsl	x12, x9, #2
	mov	w13, #8480                      ; =0x2120
	movk	w13, #65316, lsl #16
LBB11_5:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB11_6 Depth 2
	mov	w14, #8                         ; =0x8
LBB11_6:                                ;   Parent Loop BB11_5 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x15, [x0, #16]
	ldr	x16, [x0]
	madd	x15, x12, x16, x15
	str	w13, [x15, x14, lsl #2]
	add	x14, x14, #1
	cmp	x10, x14
	b.ne	LBB11_6
; %bb.7:                                ;   in Loop: Header=BB11_5 Depth=1
	add	x9, x9, #1
	add	x12, x12, #4
	cmp	x9, x11
	b.ne	LBB11_5
; %bb.8:
	ldr	x9, [x0, #16]
	cbz	x9, LBB11_18
LBB11_9:
	ldp	x12, x11, [x19, #32]
	bic	x9, x12, x12, asr #63
	ldp	x10, x13, [x0]
	cmp	x8, x10
	csel	x10, x8, x10, lt
	add	x11, x12, x11
	cmp	x11, x13
	csel	x11, x11, x13, lt
	cmp	x9, x11
	ccmp	x10, #9, #8, lt
	b.lt	LBB11_15
; %bb.10:
	lsl	x12, x9, #2
	mov	w13, #16444                     ; =0x403c
	movk	w13, #65347, lsl #16
LBB11_11:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB11_12 Depth 2
	mov	w14, #8                         ; =0x8
LBB11_12:                               ;   Parent Loop BB11_11 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x15, [x0, #16]
	ldr	x16, [x0]
	madd	x15, x12, x16, x15
	str	w13, [x15, x14, lsl #2]
	add	x14, x14, #1
	cmp	x10, x14
	b.ne	LBB11_12
; %bb.13:                               ;   in Loop: Header=BB11_11 Depth=1
	add	x9, x9, #1
	add	x12, x12, #4
	cmp	x9, x11
	b.ne	LBB11_11
; %bb.14:
	ldr	x9, [x0, #16]
	cbz	x9, LBB11_18
LBB11_15:
	ldp	x11, x10, [x19, #48]
	bic	x9, x11, x11, asr #63
	ldp	x12, x13, [x0]
	cmp	x8, x12
	csel	x8, x8, x12, lt
	add	x10, x11, x10
	cmp	x10, x13
	csel	x10, x10, x13, lt
	cmp	x9, x10
	ccmp	x8, #9, #8, lt
	b.ge	LBB11_44
; %bb.16:
	mov	x8, x19
	ldr	x2, [x8, #64]!
	mov	x9, x8
	ldr	x11, [x9, #16]!
	mov	x10, x8
	ldr	x4, [x10, #8]!
	b	LBB11_49
LBB11_17:
	ldp	x29, x30, [sp, #32]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp, #16]             ; 16-byte Folded Reload
	ldp	x22, x21, [sp], #48             ; 16-byte Folded Reload
	ret
LBB11_18:
	ldp	x4, x11, [x19, #72]
	ldr	x2, [x19, #64]
LBB11_19:
	ldr	x13, [x19, #88]
LBB11_20:
	add	x3, x13, x11
	mov	x20, x0
	mov	w1, #8                          ; =0x8
	mov	w5, #1                          ; =0x1
	mov	w6, #56538                      ; =0xdcda
	movk	w6, #65504, lsl #16
	bl	_fb_draw_border
	ldr	x8, [x20, #16]
	cbz	x8, LBB11_29
; %bb.21:
	ldp	x11, x10, [x19, #96]
	bic	x8, x11, x11, asr #63
	sub	x9, x21, #8
	ldp	x12, x13, [x20]
	cmp	x9, x12
	csel	x9, x9, x12, lt
	add	x10, x11, x10
	cmp	x10, x13
	csel	x10, x10, x13, lt
	cmp	x8, x10
	ccmp	x9, #9, #8, lt
	b.lt	LBB11_27
; %bb.22:
	mov	w11, #62449                     ; =0xf3f1
	movk	w11, #65524, lsl #16
	lsl	x12, x8, #2
LBB11_23:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB11_24 Depth 2
	mov	w13, #8                         ; =0x8
LBB11_24:                               ;   Parent Loop BB11_23 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x14, [x20, #16]
	ldr	x15, [x20]
	madd	x14, x12, x15, x14
	str	w11, [x14, x13, lsl #2]
	add	x13, x13, #1
	cmp	x9, x13
	b.ne	LBB11_24
; %bb.25:                               ;   in Loop: Header=BB11_23 Depth=1
	add	x8, x8, #1
	add	x12, x12, #4
	cmp	x8, x10
	b.ne	LBB11_23
; %bb.26:
	ldr	x8, [x20, #16]
	cbz	x8, LBB11_29
LBB11_27:
	ldr	x9, [x19, #96]
	cmn	x9, #4
	mov	x8, #-4                         ; =0xfffffffffffffffc
	csel	x8, x9, x8, gt
	add	x8, x8, #4
	add	x10, x9, #8
	ldp	x9, x11, [x20]
	cmp	x10, x11
	csel	x10, x10, x11, lt
	cmp	x8, x10
	ccmp	x9, #3, #8, lt
	b.ge	LBB11_30
; %bb.28:
	ldr	x2, [x19, #112]!
	mov	x8, x19
	ldr	x3, [x8, #8]!
	mov	x9, x19
	ldr	x4, [x9, #16]!
	b	LBB11_37
LBB11_29:
	ldp	x2, x3, [x19, #112]
	ldr	x4, [x19, #128]
	b	LBB11_43
LBB11_30:
	mov	w11, #-16777216                 ; =0xff000000
	b	LBB11_32
LBB11_31:                               ;   in Loop: Header=BB11_32 Depth=1
	add	x8, x8, #1
	cmp	x10, x8
	b.eq	LBB11_36
LBB11_32:                               ; =>This Inner Loop Header: Depth=1
	ldr	x12, [x20, #16]
	ldr	x13, [x20]
	mul	x13, x13, x8
	add	x12, x12, x13, lsl #2
	str	w11, [x12, #8]
	cmp	x9, #3
	b.eq	LBB11_31
; %bb.33:                               ;   in Loop: Header=BB11_32 Depth=1
	ldr	x12, [x20, #16]
	ldr	x13, [x20]
	mul	x13, x13, x8
	add	x12, x12, x13, lsl #2
	str	w11, [x12, #12]
	cmp	x9, #4
	b.eq	LBB11_31
; %bb.34:                               ;   in Loop: Header=BB11_32 Depth=1
	ldr	x12, [x20, #16]
	ldr	x13, [x20]
	mul	x13, x13, x8
	add	x12, x12, x13, lsl #2
	str	w11, [x12, #16]
	cmp	x9, #5
	b.eq	LBB11_31
; %bb.35:                               ;   in Loop: Header=BB11_32 Depth=1
	ldr	x12, [x20, #16]
	ldr	x13, [x20]
	mul	x13, x13, x8
	add	x12, x12, x13, lsl #2
	str	w11, [x12, #20]
	b	LBB11_31
LBB11_36:
	ldr	x10, [x20, #16]
	ldr	x2, [x19, #112]!
	mov	x8, x19
	ldr	x3, [x8, #8]!
	mov	x9, x19
	ldr	x4, [x9, #16]!
	cbz	x10, LBB11_43
LBB11_37:
	bic	x10, x2, x2, asr #63
	add	x11, x3, #8
	ldp	x12, x13, [x20]
	cmp	x11, x12
	csel	x11, x11, x12, lt
	add	x12, x2, x4
	cmp	x12, x13
	csel	x12, x12, x13, lt
	cmp	x10, x12
	ccmp	x11, #9, #8, lt
	b.lt	LBB11_43
; %bb.38:
	lsl	x13, x10, #2
	mov	w14, #29466                     ; =0x731a
	movk	w14, #65512, lsl #16
LBB11_39:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB11_40 Depth 2
	mov	w15, #8                         ; =0x8
LBB11_40:                               ;   Parent Loop BB11_39 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x16, [x20, #16]
	ldr	x17, [x20]
	madd	x16, x13, x17, x16
	str	w14, [x16, x15, lsl #2]
	add	x15, x15, #1
	cmp	x11, x15
	b.ne	LBB11_40
; %bb.41:                               ;   in Loop: Header=BB11_39 Depth=1
	add	x10, x10, #1
	add	x13, x13, #4
	cmp	x10, x12
	b.ne	LBB11_39
; %bb.42:
	ldr	x2, [x19]
	ldr	x3, [x8]
	ldr	x4, [x9]
LBB11_43:
	mov	x0, x20
	mov	w1, #8                          ; =0x8
	mov	w5, #2                          ; =0x2
	mov	w6, #8480                       ; =0x2120
	movk	w6, #65316, lsl #16
	ldp	x29, x30, [sp, #32]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp, #16]             ; 16-byte Folded Reload
	ldp	x22, x21, [sp], #48             ; 16-byte Folded Reload
	b	_fb_draw_border
LBB11_44:
	lsl	x11, x9, #2
	mov	w12, #61672                     ; =0xf0e8
	movk	w12, #65534, lsl #16
LBB11_45:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB11_46 Depth 2
	mov	w13, #8                         ; =0x8
LBB11_46:                               ;   Parent Loop BB11_45 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x14, [x0, #16]
	ldr	x15, [x0]
	madd	x14, x11, x15, x14
	str	w12, [x14, x13, lsl #2]
	add	x13, x13, #1
	cmp	x8, x13
	b.ne	LBB11_46
; %bb.47:                               ;   in Loop: Header=BB11_45 Depth=1
	add	x9, x9, #1
	add	x11, x11, #4
	cmp	x9, x10
	b.ne	LBB11_45
; %bb.48:
	ldr	x12, [x0, #16]
	mov	x8, x19
	ldr	x2, [x8, #64]!
	mov	x9, x8
	ldr	x11, [x9, #16]!
	mov	x10, x8
	ldr	x4, [x10, #8]!
	cbz	x12, LBB11_19
LBB11_49:
	bic	x12, x2, x2, asr #63
	add	x13, x11, #8
	ldp	x14, x15, [x0]
	cmp	x13, x14
	csel	x13, x13, x14, lt
	add	x14, x2, x4
	cmp	x14, x15
	csel	x14, x14, x15, lt
	cmp	x12, x14
	ccmp	x13, #9, #8, lt
	b.ge	LBB11_51
; %bb.50:
	mov	x12, x19
	ldr	x13, [x12, #88]!
	b	LBB11_56
LBB11_51:
	mov	w11, #62449                     ; =0xf3f1
	movk	w11, #65524, lsl #16
	lsl	x15, x12, #2
LBB11_52:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB11_53 Depth 2
	mov	w16, #8                         ; =0x8
LBB11_53:                               ;   Parent Loop BB11_52 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x17, [x0, #16]
	ldr	x1, [x0]
	madd	x17, x15, x1, x17
	str	w11, [x17, x16, lsl #2]
	add	x16, x16, #1
	cmp	x13, x16
	b.ne	LBB11_53
; %bb.54:                               ;   in Loop: Header=BB11_52 Depth=1
	add	x12, x12, #1
	add	x15, x15, #4
	cmp	x12, x14
	b.ne	LBB11_52
; %bb.55:
	ldr	x14, [x0, #16]
	mov	x12, x19
	ldr	x13, [x12, #88]!
	ldp	x4, x11, [x12, #-16]
	ldur	x2, [x12, #-24]
	cbz	x14, LBB11_20
LBB11_56:
	add	x16, x11, #8
	bic	x14, x16, x16, asr #63
	bic	x15, x2, x2, asr #63
	ldp	x17, x1, [x0]
	add	x16, x16, x13
	cmp	x16, x17
	csel	x16, x16, x17, lt
	add	x17, x2, x4
	cmp	x17, x1
	csel	x17, x17, x1, lt
	cmp	x15, x17
	ccmp	x14, x16, #0, lt
	b.ge	LBB11_20
; %bb.57:
	lsl	x11, x15, #2
	mov	w13, #-1                        ; =0xffffffff
LBB11_58:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB11_59 Depth 2
	mov	x1, x14
LBB11_59:                               ;   Parent Loop BB11_58 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	ldr	x2, [x0, #16]
	ldr	x3, [x0]
	madd	x2, x11, x3, x2
	str	w13, [x2, x1, lsl #2]
	add	x1, x1, #1
	cmp	x16, x1
	b.ne	LBB11_59
; %bb.60:                               ;   in Loop: Header=BB11_58 Depth=1
	add	x15, x15, #1
	add	x11, x11, #4
	cmp	x15, x17
	b.ne	LBB11_58
; %bb.61:
	ldr	x2, [x8]
	ldr	x11, [x9]
	ldr	x13, [x12]
	ldr	x4, [x10]
	b	LBB11_20
	.cfi_endproc
                                        ; -- End function
	.globl	_fb_write_ppm                   ; -- Begin function fb_write_ppm
	.p2align	2
_fb_write_ppm:                          ; @fb_write_ppm
	.cfi_startproc
; %bb.0:
	cbz	x0, LBB12_9
; %bb.1:
	sub	sp, sp, #64
	stp	x22, x21, [sp, #16]             ; 16-byte Folded Spill
	stp	x20, x19, [sp, #32]             ; 16-byte Folded Spill
	stp	x29, x30, [sp, #48]             ; 16-byte Folded Spill
	add	x29, sp, #48
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_offset w21, -40
	.cfi_offset w22, -48
	mov	x19, x0
	mov	w0, #0                          ; =0x0
	cbz	x1, LBB12_8
; %bb.2:
	ldr	x8, [x19, #16]
	cbz	x8, LBB12_8
; %bb.3:
Lloh2:
	adrp	x8, l_.str@PAGE
Lloh3:
	add	x8, x8, l_.str@PAGEOFF
	mov	x0, x1
	mov	x1, x8
	bl	_fopen
	cbz	x0, LBB12_8
; %bb.4:
	mov	x20, x0
	ldp	x8, x9, [x19]
	stp	x8, x9, [sp]
Lloh4:
	adrp	x1, l_.str.1@PAGE
Lloh5:
	add	x1, x1, l_.str.1@PAGEOFF
	bl	_fprintf
	ldp	x8, x9, [x19]
	mul	x8, x9, x8
	cmp	x8, #1
	b.lt	LBB12_7
; %bb.5:
	mov	x21, #0                         ; =0x0
	mov	x22, #0                         ; =0x0
LBB12_6:                                ; =>This Inner Loop Header: Depth=1
	ldr	x8, [x19, #16]
	ldrb	w0, [x8, x21]
	mov	x1, x20
	bl	_fputc
	ldr	x8, [x19, #16]
	add	x8, x8, x21
	ldrb	w0, [x8, #1]
	mov	x1, x20
	bl	_fputc
	ldr	x8, [x19, #16]
	add	x8, x8, x21
	ldrb	w0, [x8, #2]
	mov	x1, x20
	bl	_fputc
	add	x22, x22, #1
	ldp	x8, x9, [x19]
	mul	x8, x9, x8
	add	x21, x21, #4
	cmp	x22, x8
	b.lt	LBB12_6
LBB12_7:
	mov	x0, x20
	bl	_fclose
	mov	w0, #1                          ; =0x1
LBB12_8:
	ldp	x29, x30, [sp, #48]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp, #32]             ; 16-byte Folded Reload
	ldp	x22, x21, [sp, #16]             ; 16-byte Folded Reload
	add	sp, sp, #64
LBB12_9:
	ret
	.loh AdrpAdd	Lloh2, Lloh3
	.loh AdrpAdd	Lloh4, Lloh5
	.cfi_endproc
                                        ; -- End function
	.section	__TEXT,__const
	.p2align	3, 0x0                          ; @__const.get_sample_interactive_page.page
l___const.get_sample_interactive_page.page:
	.quad	38                              ; 0x26
	.quad	21                              ; 0x15
	.quad	21                              ; 0x15
	.quad	19                              ; 0x13
	.quad	16                              ; 0x10
	.quad	16                              ; 0x10
	.quad	2                               ; 0x2
	.quad	30                              ; 0x1e
	.quad	12                              ; 0xc
	.quad	12                              ; 0xc
	.quad	40                              ; 0x28
	.quad	60                              ; 0x3c
	.quad	25                              ; 0x19
	.quad	10                              ; 0xa
	.quad	10                              ; 0xa
	.quad	40                              ; 0x28
	.quad	16                              ; 0x10
	.quad	16                              ; 0x10
	.quad	60                              ; 0x3c
	.quad	16                              ; 0x10
	.quad	6                               ; 0x6
	.quad	2                               ; 0x2
	.quad	10                              ; 0xa
	.quad	10                              ; 0xa

	.section	__TEXT,__cstring,cstring_literals
l_.str:                                 ; @.str
	.asciz	"wb"

l_.str.1:                               ; @.str.1
	.asciz	"P6\n%lld %lld\n255\n"

.subsections_via_symbols

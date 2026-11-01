| CT2CART.PRG - make the cartridge (ROM) port user-accessible on a
| CENTurbo II in turbo mode (TOS 7.0x).
|
| TOS 7.0x maps $00F00000-$00FFFFFF with a single long-format root page
| descriptor that has the supervisor-only bit set. In turbo mode this is
| what makes user-mode accesses to the I/O registers end in a bus error,
| as on a stock Falcon, but it also catches the ROM port ($FA0000-$FBFFFF),
| which is readable in user mode on a stock Falcon. TOS drivers for ROM
| port hardware (e.g. the NetUSBee USB driver) rely on that.
|
| Following the method of WPMMUCT2.PRG (Didier Mequignon, 1999), the patch
| puts a level B table into the free space after the TOS 7.0x MMU tables:
| with address translation switched off, it looks for the first two zero
| longs after the root table, builds 128 long-format page descriptors
| there which keep the original attributes (cache inhibit, supervisor
| only) for every 8 KB page except the ROM port, and points root entry
| $00F at that table. The zero longs after the new table mark the end of
| the used space for the next program using the same method.
|
| The program does not stay resident. It must be loaded into ST-RAM (no
| TT-RAM flags) because it runs with address translation switched off.
| If WPMMUCT2.PRG is used, it must run before this program.

	.equ	CT2_TC,0x80D1B700	| TOS 7.0x: IS=1, TIA=11, TIB=7, 8 KB pages
	.equ	ROOT_ENTRIES,2048
	.equ	RP_FIRST,(0xFA0000-0xF00000)/0x2000	| first ROM port page
	.equ	RP_END,(0xFC0000-0xF00000)/0x2000	| first page after it

	.text
	.globl	_start
_start:
	pea	super(%pc)
	move.w	#38,-(%sp)		| Supexec
	trap	#14
	addq.l	#6,%sp

	move.l	msg,-(%sp)
	move.w	#9,-(%sp)		| Cconws
	trap	#1
	addq.l	#6,%sp

	move.w	status,-(%sp)
	move.w	#0x4c,-(%sp)		| Pterm
	trap	#1

| Supervisor part: checks, patch, sets msg and status.
super:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	moveq	#1,%d7

	lea	m_noct2,%a6
	move.l	#0x5f435432,%d0		| _CT2
	bsr	getcookie
	bne	1f
	move.l	#0x5f435055,%d0		| _CPU
	bsr	getcookie
	bne	1f
	moveq	#30,%d0
	cmp.l	%d1,%d0
	bne	1f

	lea	m_notos7,%a6
	pmove	%tc,tcval
	pmove	%crp,crpval
	cmp.l	#CT2_TC,tcval
	bne	1f
	move.l	crpval,%d0
	and.l	#0x7FFF0003,%d0
	cmp.l	#((ROOT_ENTRIES-1)<<16)+3,%d0	| upper limit $7FF, long descriptors
	bne	1f

	lea	m_ttram,%a6
	lea	_start(%pc),%a0
	cmp.l	#0x00E00000,%a0
	bhs	1f

	bsr	patch
	lea	msgtab,%a0
	move.l	%d0,%d7
	lsl.w	#2,%d0
	move.l	(%a0,%d0.w),%a6

1:	move.l	%a6,msg
	move.w	%d7,status
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts

| d0 = tag; returns Z set and d1 = value if found
getcookie:
	move.l	0x5a0,%d1
	beq	2f
	move.l	%d1,%a0
1:	move.l	(%a0)+,%d1
	beq	2f
	cmp.l	%d1,%d0
	beq	3f
	addq.l	#4,%a0
	bra	1b
2:	moveq	#-1,%d0
	rts
3:	move.l	(%a0),%d1
	moveq	#0,%d0
	rts

| Runs at IPL 7 with address translation and the data cache switched off;
| everything touched here must be identity mapped (ST-RAM).
| Returns d0: 0 patched, 1 already patched, 2 no free space, 3 bus error.
patch:
	movem.l	%d2-%d7/%a2-%a5,-(%sp)
	move.w	%sr,-(%sp)
	ori.w	#0x0700,%sr
	move.l	%sp,savessp
	move.l	0x8,saveberr
	move.l	#berr,0x8
	movec	%cacr,%d0
	move.l	%d0,savecacr
	bclr	#8,%d0			| data cache off
	bset	#11,%d0			| and cleared
	movec	%d0,%cacr
	move.l	tcval,%d0
	bclr	#31,%d0
	move.l	%d0,tmpval
	pmove	tmpval,%tc		| translation off
	pflusha

	move.l	crpval+4,%d0
	and.l	#~15,%d0
	move.l	%d0,%a1			| root table (physical)
	lea	0xF*8(%a1),%a2		| root entry $00F
	move.l	(%a2),%d3

	moveq	#1,%d7
	move.l	%d3,%d0
	and.l	#3,%d0
	cmp.l	#1,%d0			| page descriptor?
	bne	done
	btst	#8,%d3			| supervisor only?
	beq	done

	| first two zero longs after the root table, within its megabyte
	moveq	#2,%d7
	move.l	%a1,%d2
	and.l	#0xFFF00000,%d2
	add.l	#0x00100000,%d2		| end of the megabyte
	lea	ROOT_ENTRIES*8(%a1),%a0
1:	lea	8(%a0),%a3
	cmp.l	%d2,%a3
	bhi	done
	tst.l	(%a0)
	bne	2f
	tst.l	4(%a0)
	beq	3f
2:	addq.l	#4,%a0
	bra	1b
3:	move.l	%a0,%d0
	add.l	#15,%d0
	and.l	#~15,%d0
	move.l	%d0,%a3			| new table, 16-byte aligned
	lea	128*8+8(%a3),%a4	| table + end marker
	cmp.l	%d2,%a4
	bhi	done
	move.l	%a0,%a5
4:	tst.l	(%a5)+			| all of it must be free (zero)
	bne	done
	cmp.l	%a4,%a5
	blo	4b

	| 128 page descriptors, 8 KB each, attributes of the old entry
	move.l	4(%a2),%d4
	and.l	#0xFFF00000,%d4
	move.l	%a3,%a0
	moveq	#0,%d5
5:	move.l	%d3,%d1
	cmp.l	#RP_FIRST,%d5
	blo	6f
	cmp.l	#RP_END,%d5
	bhs	6f
	bclr	#8,%d1			| ROM port: user accessible
6:	move.l	%d1,(%a0)+
	move.l	%d4,(%a0)+
	add.l	#0x2000,%d4
	addq.l	#1,%d5
	cmp.l	#128,%d5
	blo	5b

	| root entry $00F: long table descriptor, limit $7F, S clear, used
	move.l	%d3,%d1
	and.l	#0x0000FE00,%d1
	or.l	#0x007F000B,%d1
	move.l	%a3,4(%a2)
	move.l	%d1,(%a2)
	moveq	#0,%d7

done:
	pmove	tcval,%tc		| translation back on
	pflusha
	move.l	savecacr,%d0
	bset	#11,%d0
	movec	%d0,%cacr
	move.l	saveberr,0x8
	move.l	%d7,%d0
	move.w	(%sp)+,%sr
	movem.l	(%sp)+,%d2-%d7/%a2-%a5
	rts

berr:
	move.l	savessp,%sp
	moveq	#3,%d7
	bra	done

	.data
msgtab:	.long	m_ok, m_already, m_nospace, m_berr

m_ok:		.asciz	"CT2CART: ROM port is user accessible\r\n"
m_already:	.asciz	"CT2CART: already installed\r\n"
m_nospace:	.asciz	"CT2CART: no free space after the MMU tables, not installed\r\n"
m_berr:		.asciz	"CT2CART: bus error, not installed\r\n"
m_noct2:	.asciz	"CT2CART: no CT2 or no 68030, not installed\r\n"
m_notos7:	.asciz	"CT2CART: MMU not set up by TOS 7.0x in turbo mode, not installed\r\n"
m_ttram:	.asciz	"CT2CART: not loaded into ST-RAM, not installed\r\n"

	.bss
	.even
tcval:		.ds.l	1
crpval:		.ds.l	2
tmpval:		.ds.l	1
savessp:	.ds.l	1
saveberr:	.ds.l	1
savecacr:	.ds.l	1
msg:		.ds.l	1
status:		.ds.w	1

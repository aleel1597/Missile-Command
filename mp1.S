
# mp1.S - missile-command version
# Good luck, and have fun!

.data

    # Constants for accessing the fields of a struct missile,
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:

    PUSHL %EBP
    MOVL %ESP, %EBP

    pushal

    pushal
		CALL update_missiles					#call update_missiles: 1st task
    popal

    pushal
		CALL redraw_cities					   #call redraw_cities
    popal

    pushal
		CALL redraw_crosshairs					#call redraw_cities
    popal

    popal
    LEAVE
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		MOVL 8(%ESP), %EAX 			#move cmd into EAX
		MOVL 4(%ESP), %EBX			#move arg into EBX
		CMPL $0, %EAX
		JL invalid_cmd
		CMPL $4, %EAX
		JG invalid_cmd
		JMP *jump_table_of_core_functions(,%EAX,4)
		JMP ioctl_done
invalid_cmd:
		MOVL $-1, %EAX
		JMP ioctl_done
ioctl_done:
    LEAVE
		ret

jump_table_of_core_functions:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

# ----------------- Functions private to this file -------------------

redraw_crosshairs:
		PUSHL %EBP
		MOVL %ESP, %EBP

		pushal

    MOVL $0, %EAX               #clear registers
    MOVL $0, %EBX
    MOVL $0, %ECX
    MOVL $0, %EDX
    MOVL $0, %ESI
    MOVL $0, %EDI

		MOVL crosshairs_y, %EDI			# put current x location into EDI
		IMULL $160, %EDI						# Row offset calculated from 24 * 80 characters per row * 2 bytes in EDI, this gets us to the last row
		MOVL crosshairs_x, %EDX			# put current y location into EDX
		IMULL $2, %EDX 							# Col offset calculated from X * 2 bytes in EDX
		MOVL %EDI, %EAX							# put row offset into EAX
		ADDL %EDX, %EAX							# add row offset and col offset and put into EAX to get to index of first city
		MOVB $43, %CL							  # put cross hair + character into CL

    pushal
		CALL mp1_poke					      #draw cross hair
    popal

		popal
		LEAVE
		ret



update_missiles:
#Step 1: Set up stack pointers
		PUSHL %EBP
		MOVL %ESP, %EBP
    pushal

    MOVL $0, %EAX               #clear registers
    MOVL $0, %EBX
    MOVL $0, %ECX
    MOVL $0, %EDX
    MOVL $0, %ESI
    MOVL $0, %EDI

#Step 2: start traversal of missile list and checking of missiles
    CMPL $0, mp1_missile_list     #check if initial list is null
    JE Done
    MOVL mp1_missile_list, %EDI		#otherwise, load head of mp1_missile_list into Register EAX
    PUSHL %EDI
traverse:
    POPL %EDI
    MOVL $0, %EAX               #clear registers but not EDI, that is our node pointer
    MOVL $0, %EBX
    MOVL $0, %ECX
    MOVL $0, %EDX
    MOVL $0, %ESI

		CMPL $0, %EDI
		JE Done												#see if the current node of mp1_missile_list is null
    MOVB $32, %CL                 #put blank char in CL
see_if_exploding:
		MOVL EXPLODED(%EDI), %ESI     #Check if missile is exploding
		CMPL $0, %ESI
		JNE go_to_missile_explode     #if so, then go to explode portion
    JMP Step_2A

Step_2A:  #checking if missile is off the screen, if so then remove the missile
		MOVL X(%EDI), %ESI						#put x value into  Register
		SHRL $16, %ESI								#Shift x value in  by 16 to get the upper x bits of coordinates
		CMPL $0, %ESI									#see if missile is below xcoord 0
		JB go_to_mp1_missile_remove
		CMPL $79, %ESI								#see if missile is above xcoord 79
		JA go_to_mp1_missile_remove
		MOVL Y(%EDI), %ESI						#put y value into  Register
		SHRL $16, %ESI								#Shift y value in  by 16 to get the upper y bits of coordinates
		CMPL $0, %ESI									#see if missile is below ycoord 0
		JB go_to_mp1_missile_remove
		CMPL $24, %ESI								#see if missile is above ycoord 24
		JA go_to_mp1_missile_remove
    JMP Step_2B

Step_2B:  #checking if missile reached its destination
		MOVL X(%EDI), %ESI						#put x value into  Register
		SHRL $16, %ESI								#Shift x value in  by 16 to get the upper x bits of coordinates
		CMPL DEST_X(%EDI), %ESI				#see if missile x location is at x destination
		JNE Step_2C									  #if it is not at x destination, move on to redrawing the missile
		MOVL Y(%EDI), %ESI						#put y value into  Register
		SHRL $16, %ESI								#Shift y value in  by 16 to get the upper y bits of coordinates
		CMPL DEST_Y(%EDI), %ESI				#see if missile y location is at y destination
		JNE Step_2C									  #if it is not at y destination, move on to redrawing the missile
		JMP go_to_missile_explode			#if the x and y are at xdest and ydest, go to the explode function

Step_2C:  #missile is valid and should have its path erased then drawn at its new location
		MOVL $1, %EBX							    #set flag as valid missile
		MOVB $32, %CL						      #put ASCII Code of space Character to write in CL
		JMP redraw_missile				    #erase trail of missile

valid_missile:
		MOVL VX(%EDI), %ESI
		MOVL VY(%EDI), %EDX
		ADDL %ESI, X(%EDI)		        #Update x location with vx
		ADDL %EDX, Y(%EDI)		        #Update y location with vy
		MOVB C(%EDI), %CL					    #put missile character into CL
		MOVL $0, %EBX							    #reset flag as valid missile
    JMP redraw_missile

redraw_missile:
		MOVL Y(%EDI), %ESI				  	#put current y location in
		SHRL $16, %ESI						  	#Shift y value  by 16 to get the upper y bits of coordinates
		IMULL $160, %ESI						  #Row offset calculated from Y * 80 characters per row * 2 bytes in
		MOVL X(%EDI), %EDX				  	#put current x location into EDX
		SHRL $16, %EDX						  	#Shift x value in by 16 to get the upper x bits of coordinates
		IMULL $2, %EDX 						   	# Col offset calculated from X * 2 bytes in EDX
		MOVL %ESI, %EAX							  # put row offset into eax
		ADDL %EDX, %EAX						   	# add row offset and col offset and put into EAX
		JMP go_to_mp1_poke				    # draw the missile

go_to_mp1_missile_remove:
    CMPL $0, %EDI
    JE Done
    MOVL $2, %EBX                 #set remove flag in EBX
		MOVB $32, %CL						      #put ASCII Code of space Character to write in CL
		JMP redraw_missile            #erase path of missile
ret_to_missile_remove:
    MOVL $0, %EBX                 #clear flag in EBX

    MOVL NEXT(%EDI), %EDX         #setup next pointer call because we are calling remove, we cant use normal increment
		PUSHL %EAX										#protect caller-saved registers
		PUSHL %EBX
		PUSHL %ECX
    PUSHL %EDX
    PUSHL %ESI
    PUSHL %EDI                    #give arg to mp1_missile remove
    CALL mp1_missile_remove
    POPL %EDI
    POPL %ESI
    POPL %EDX
    POPL %ECX
    POPL %EBX
		POPL %EAX
    MOVL %EDX, %EDI                #increment node to next node here, cant use normal increment
    PUSHL %EDI
		JMP traverse	                 #move to the next node mp1_missile_list

go_to_missile_explode:

    MOVL $0, VY(%EDI)            #halt missile y velocity
    MOVL $0, VX(%EDI)            #halt missile x velocity

    PUSHL %EAX
    PUSHL %EBX
    PUSHL %ECX
    PUSHL %EDX
    PUSHL %ESI
    PUSHL %EDI

    PUSHL %EDI										#push current node of missile onto stack
		CALL missile_explode
    POPL %EDI											#pop passed in arg of current node of missile onto stack

		POPL %ESI
		POPL %ESI
    POPL %EDX
    POPL %ECX
    POPL %EBX
    POPL %ESI                     #dont pop into EAX, need to see if game status changed, put into junk reg

    CMPL $0, %EAX									#checks if game status has changed
		JNE go_to_mp1_notify_user     #missile caused cities or other missiles to explode

post_explode:
		DECL EXPLODED(%EDI)				   #decrement exploded counter
		CMPL $0, EXPLODED(%EDI)				#check if exploded counter is zero
		JE go_to_mp1_missile_remove		#explosion is done, remove missile from list and screen
		MOVB $64, %CL			            #if not, put ASCII Code of explosion Character to write in CL
    MOVL $0, %EBX                 #reset flag as valid missile
    JMP redraw_missile            #draw the explosion char

go_to_mp1_notify_user:

    PUSHL %EAX
    PUSHL %EBX
    PUSHL %ECX
    PUSHL %EDX
    PUSHL %ESI
    PUSHL %EDI
    PUSHL %EAX                    #give notify user the arg of current node
		CALL mp1_notify_user					#missile hit a city or another missile
    POPL %EAX                     #pop notify user the arg of current node
    POPL %EDI
		POPL %ESI
		POPL %EDX
    POPL %ECX
    POPL %EBX
    POPL %EAX

    JMP post_explode

go_to_mp1_poke:  #To use mp1_poke, EAX needs offset from start of video memory, CL needs ASCII code of char to  be written

    MOVL $0, %EDX                 #clear edx before poking
    PUSHL %EAX
    PUSHL %EBX
    PUSHL %ECX
		PUSHL %EDX
		PUSHL %ESI
		PUSHL %EDI                    #saved current pointer to node in list in EDI
		CALL mp1_poke					        #Draw the character
		POPL %EDI
		POPL %ESI
		POPL %EDX
    POPL %ECX
    POPL %EBX
    POPL %EAX

    CMPL $1, %EBX									#check valid missile flag in EBX
		JE valid_missile
		CMPL $2, %EBX									#check if invalid missile_explode
		JE ret_to_missile_remove
		JMP incremement_Missile_Node	#move to the next node mp1_missile_list

incremement_Missile_Node:
    MOVL NEXT(%EDI), %EDX					#Move to the next node in mp1_missile_list
    CMPL $0, %EDX
    JE Done												#see if the current node of mp1_missile_list is null
    MOVL NEXT(%EDI), %EDI					#Move to the next node in mp1_missile_list
    PUSHL %EDI
		JMP traverse

Done:	#Step 5: tear down stack frame
    popal
		LEAVE
		ret



redraw_cities:

		PUSHL %EBP
		MOVL %ESP, %EBP
    pushal

    MOVL $0, %EAX               #clear registers
    MOVL $0, %EBX
    MOVL $0, %ECX
    MOVL $0, %EDX
    MOVL $0, %ESI
    MOVL $0, %EDI

		MOVL $0, %ESI 		#chooses which city is being drawn

make_city1:                     #get video mem offset
		MOVL $24, %ECX					    # put current y location into ECX
		IMULL $160, %ECX						# Row offset calculated from 24 * 80 characters per row * 2 bytes in EXC, this gets us to the last row
		MOVL $18, %EDX					    # put current x location into EDX
		IMULL $2, %EDX 							# Col offset calculated from X * 2 bytes in EDX
		MOVL %ECX, %EAX							# put row offset into EAX
		ADDL %EDX, %EAX							# add row offset and col offset and put into EAX to get to index of first city
		JMP see_if_base_alive

make_city2:                     #get video mem offset
		MOVL $24, %ECX					    # put current y location into ECX
		IMULL $160, %ECX						# Row offset calculated from 24 * 80 characters per row * 2 bytes in EXC, this gets us to the last row
		MOVL $38, %EDX					    # put current x location into EDX
		IMULL $2, %EDX 							# Col offset calculated from X * 2 bytes in EDX
		MOVL %ECX, %EAX							# put row offset into EAX
		ADDL %EDX, %EAX							# add row offset and col offset and put into EAX to get to index of first city
		JMP see_if_base_alive

make_city3:                     #get video mem offset
		MOVL $24, %ECX					    # put current y location into ECX
		IMULL $160, %ECX						# Row offset calculated from 24 * 80 characters per row * 2 bytes in EXC, this gets us to the last row
		MOVL $58, %EDX					    # put current x location into EDX
		IMULL $2, %EDX 							# Col offset calculated from X * 2 bytes in EDX
		MOVL %ECX, %EAX							# put row offset into EAX
		ADDL %EDX, %EAX							# add row offset and col offset and put into EAX to get to index of first city
		JMP see_if_base_alive

see_if_base_alive:
		MOVL base_alive, %EBX
		CMPL $0, %ESI 			        #see which base life we are checking for bases 1 through 3
		JE bitmask_city1
		CMPL $1, %ESI
		JE bitmask_city2
		CMPL $2, %ESI
		JE bitmask_city3

bitmask_city1:
		MOVL %EBX, %EDI							#move alive status in edi to check for current base index if its alive
		AND $0x000000FF, %EDI				#bitmask the base alive to get the alive status for base 1
		CMPL $0x000000FF, %EDI			# check if the base is still alive
		JE base_is_alive
		JMP base_is_dead

bitmask_city2:
		MOVL %EBX, %EDI							#move alive status in edi to check for current base index if its alive
		AND $0x0000FF00, %EDI				#bitmask the base alive to get the alive status for base 1
		CMPL $0x0000FF00, %EDI			# check if the base is still alive
		JE base_is_alive
		JMP base_is_dead

bitmask_city3:
		MOVL %EBX, %EDI							#move alive status in edi to check for current base index if its alive
		AND $0x00FF0000, %EDI				#bitmask the base alive to get the alive status for base 1
		CMPL $0x00FF0000, %EDI			# check if the base is still alive
		JE base_is_alive
		JMP base_is_dead

base_is_alive:
		MOVL $0, %EDI							  #create counter to iterate through 5 characters
draw_alive_base:
		MOVB base_pic(%EDI), %CL		#put the character from base alive to be drawn in CL										#protect caller-saved registers

    pushal
		CALL mp1_poke					      #draw the base
    popal

		ADDL $1, %EDI							  #increment counter to iterate through 5 characters then check if its 5
		CMPL $5, %EDI
		JE choose_which_make_city		#if equal to 5, start making next city
		ADDL $2, %EAX							  #otherwise get to next location in video screen memory to be drawn then loop
		JMP draw_alive_base

base_is_dead:
		MOVL $0, %EDI							#create counter to iterate through 5 characters
draw_dead_base:
		MOVB dead_base_pic(%EDI), %CL		#put the character from base alive to be drawn in CL

    pushal
		CALL mp1_poke					#draw to screen
    popal

		ADDL $1, %EDI							#increment counter to iterate through 5 characters then check if its 5
		CMPL $5, %EDI
		JE choose_which_make_city	#if equal to 5, start making next city
		ADDL $2, %EAX							#otherwise get to next location in video screen memory to be drawn then loop
		JMP draw_dead_base

choose_which_make_city:
		ADDL $1, %ESI			#increment the city index we are making
		CMPL $1, %ESI			#see if we should make city 2
		JE make_city2
		CMPL $2, %ESI			#see if we should make city 3
		JE make_city3
		JMP done_making_cities

done_making_cities: #last step: stack teardown
    popal
		LEAVE
		ret



mp1_ioctl_startgame:				      #initialize all variables

    PUSHL %EBP
    MOVL %ESP, %EBP
    pushal

    MOVL $0, %EAX               #clear registers
    MOVL $0, %EBX
    MOVL $0, %ECX
    MOVL $0, %EDX
    MOVL $0, %ESI
    MOVL $0, %EDI

		MOVL $0, mp1_missile_list
    MOVL $0x00FFFFFF, base_alive
		MOVL $0, mp1_score
		MOVL $40, crosshairs_x
		MOVL $12, crosshairs_y

    popal
    LEAVE
		ret



mp1_ioctl_addmissile:

#Step 1: Set up stack pointers
		PUSHL %EBP
		MOVL %ESP, %EBP
    pushal

    MOVL $0, %ECX                   #clear registers
    MOVL $0, %EDX
    MOVL $0, %ESI
    MOVL $0, %EDI

#Step 2: malloc kernel memory

    PUSHL %EAX
    PUSHL %EBX
    PUSHL %ECX
    PUSHL %EDX
    PUSHL %ESI
    PUSHL %EDI

		PUSHL $33 					            #push 33 bytes as argument for malloc
		CALL mp1_malloc 		            #malloc the object, EAX now contains the void pointer
    POPL %ECX                       #Clear input arg from stack into junk register

    POPL %EDI
    POPL %ESI
    POPL %EDX
    POPL %ECX
    POPL %EBX
    POPL %ECX                       #Clear stack EAX orig input, EAX is now void pointer
malloc_done:
		CMPL $0, %EAX 			            #check if return value void ptr from malloc is null
		JE unsuccessful_malloc
    JMP successful_malloc

unsuccessful_malloc:
    MOVL $-1, %EAX				          #unsuccessful_malloc, return value -1
    JMP add_missile_done

#Step 3: copy mem into malloced mem
successful_malloc:
		MOVL %EAX, %ESI 	              #Save the void pointer to new mem in ESI because it will get clobbered

    PUSHL %EAX
    PUSHL %EBX
    PUSHL %ECX
    PUSHL %EDX
    PUSHL %ESI
    PUSHL %EDI

		PUSHL $33			                 #33 is the size of the missile (n arg)
		PUSHL %EBX			               #EBX is the from argument (user missile)
		PUSHL %EAX			               #EAX is to argument (void ptr from malloc)

		CALL mp1_copy_from_user

		POPL %ECX					              #ECX is a junk register, we need to preserve EAX as it contains the retval of copy func
		POPL %EBX					              #EBX contains orig missile
		POPL %ECX					              #ECX is a junk register

    POPL %EDI
    POPL %ESI
    POPL %EDX
    POPL %ECX
    POPL %EBX
    POPL %ECX                       #Clear stack EAX orig input, EAX is now Bytes left uncopied
copy_done:
		CMPL $0, %EAX  			            #check if successful copy and that EAX is 0
  	JE successful_copy              #if the copy function retval is 0, then it was successful
		JMP unsuccessful_copy           #otherwise, if not 0 it was unsuccessful_copy

successful_copy:                    #add to missile list Head
    MOVL mp1_missile_list, %EDI     #Store old mp1 missile list temp var
    MOVL %EDI, NEXT(%ESI)           #set new node's next as old mp1_missile_list
    MOVL %ESI, mp1_missile_list     #set new mp1_missile_list head as new node
		MOVL $0, %EAX 				          #successful copy, return 0
		JMP add_missile_done

unsuccessful_copy:
    PUSHL %EAX
    PUSHL %EBX
    PUSHL %ECX
    PUSHL %EDX
    PUSHL %ESI
    PUSHL %EDI

		PUSHL %ESI 				              #push void pointer as arg to free mem function
		CALL mp1_free
		POPL %ESI					              #pop input arg of void ptr

    POPL %EDI
    POPL %ESI
    POPL %EDX
    POPL %ECX
    POPL %EBX
    POPL %EAX

    MOVL $-1, %EAX				          #unsuccessful_copy, return value -1

		JMP add_missile_done

add_missile_done:
    popal
    LEAVE
		ret



mp1_ioctl_movexhairs:
#step 1, save registers
    pushal

    MOVL $0, %EAX               #clear registers, save ebx as arg
    MOVL $0, %ECX
    MOVL $0, %EDX
    MOVL $0, %ESI
    MOVL $0, %EDI

#step 2, erase previous crosshair
    MOVL crosshairs_y, %EDI			# put current x location into EDI
		IMULL $160, %EDI						# Row offset calculated from 24 * 80 characters per row * 2 bytes in EDI, this gets us to the last row
		MOVL crosshairs_x, %EDX			# put current y location into EDX
		IMULL $2, %EDX 							# Col offset calculated from X * 2 bytes in EDX
		MOVL %EDI, %EAX							# put row offset into EAX
		ADDL %EDX, %EAX							# add row offset and col offset and put into EAX to get to index of first city
		MOVB $32, %CL							  # put space character into CL

    pushal
		CALL mp1_poke					      #erase prev cross hair
    popal

#step 3, find where to draw the updated crosshair
crosshair_y_op:
    MOVL %EBX, %EAX               #put 32 bit arg into register
    SHRL $16, %EAX                #shift to get crosshair delta y into register
    ADDW %AX, crosshairs_y       #add delta y to y coord

crosshair_x_op:
    MOVW %BX, %DX                #put crosshair delta x into register
    ADDW %DX, crosshairs_x       #add delta x to x coord

#step 4: see if it is in bounds, if not, bound it
    CMPW $0, crosshairs_x
    JL x_lower_bound
    CMPW $79, crosshairs_x
    JG x_upper_bound
    JMP calc_y_bound
x_lower_bound:
    MOVL $0, crosshairs_x
    JMP calc_y_bound

x_upper_bound:
    MOVL $79, crosshairs_x
    JMP calc_y_bound

calc_y_bound:
    CMPW $0, crosshairs_y
    JL y_lower_bound
    CMPW $24, crosshairs_y
    JG y_upper_bound
    JMP update_crosshair

y_lower_bound:
    MOVL $0, crosshairs_y
    JMP update_crosshair

y_upper_bound:
    MOVL $24, crosshairs_y
    JMP update_crosshair

#step 5: update crosshair
update_crosshair:

    MOVL crosshairs_y, %EDI			# put current x location into EDI
    IMULL $160, %EDI						# Row offset calculated from 24 * 80 characters per row * 2 bytes in EDI, this gets us to the last row
    MOVL crosshairs_x, %EDX			# put current y location into EDX
    IMULL $2, %EDX 							# Col offset calculated from X * 2 bytes in EDX
    MOVL %EDI, %EAX							# put row offset into EAX
    ADDL %EDX, %EAX							# add row offset and col offset and put into EAX to get to index of first city
    MOVB $43, %CL							  # put cross hair + character into CL

    pushal
    CALL mp1_poke					      #draw cross hair
    popal

    popal

    MOVL $0, %EAX                #setup return value of 0

    LEAVE
		ret



mp1_ioctl_getstatus:
    PUSHL %EBP                #save registers
    MOVL %ESP, %EBP

    pushal


#step 1 malloc the retval
    PUSHL %EAX                    #malloc setup
    PUSHL %EBX
    PUSHL %ECX
    PUSHL %EDX
    PUSHL %ESI
    PUSHL %EDI

		PUSHL $4 					            #push 4 bytes as argument for malloc (32 bits)
		CALL mp1_malloc 		            #malloc the object, EAX now contains the void pointer
    POPL %ECX                       #Clear input arg from stack into junk register

    POPL %EDI
    POPL %ESI
    POPL %EDX
    POPL %ECX
    POPL %EBX
    POPL %ECX                       #Clear stack EAX orig input, EAX is now void pointer
status_malloc_done:
		CMPL $0, %EAX 			            #check if return value void ptr from malloc is null
		JE unsuccessful_status_malloc
    JMP successful_status_malloc

unsuccessful_status_malloc:
    MOVL $-1, %EAX				          #unsuccessful_malloc, return value -1
    JMP get_status_done

successful_status_malloc:
#step 2 get base alive status
    MOVL base_alive, %EDX           #put alive status into reg

see_city1_alive:
    MOVL %EDX, %EDI							#move alive status in edi to check for current base index if its alive
    AND $0x000000FF, %EDI				#bitmask the base alive to get the alive status for base 1
    CMPL $0x000000FF, %EDI			# check if the base is still alive
    JE base1_is_alive
  	JMP base1_is_dead
base1_is_alive:
    MOVL $1, %ESI                   #ESI will be our retval
    JMP see_city2_alive
base1_is_dead:
    MOVL $0, %ESI
    JMP see_city2_alive

see_city2_alive:
  	MOVL %EDX, %EDI							#move alive status in edi to check for current base index if its alive
  	AND $0x0000FF00, %EDI				#bitmask the base alive to get the alive status for base 1
		CMPL $0x0000FF00, %EDI			# check if the base is still alive
		JE base2_is_alive
		JMP base2_is_dead
base2_is_alive:
    SHLL $1, %ESI               #set status for base 2 is alive
    ADDL $1, %ESI
    JMP see_city3_alive
base2_is_dead:
    SHLL $1, %ESI
    ADDL $0, %ESI
    JMP see_city3_alive

see_city3_alive:
    MOVL %EDX, %EDI							#move alive status in edi to check for current base index if its alive
    AND $0x00FF0000, %EDI				#bitmask the base alive to get the alive status for base 1
    CMPL $0x00FF0000, %EDI			# check if the base is still alive
    JE base3_is_alive
    JMP base3_is_dead
base3_is_alive:                  #set status for base 2 is alive
    SHLL $1, %ESI
    ADDL $1, %ESI
    JMP base_status_done
base3_is_dead:
    SHLL $1, %ESI
    ADDL $0, %ESI
    JMP base_status_done

base_status_done:
    SHLL $16, %ESI                #shift base status, then add base status to score
    ADDW mp1_score, %SI
    MOVL %ESI, (%EAX)               #put it into the void pointer of my mallocd mem
#step 3 start copy

#TODO SCORE NOT UPDATING, endgame not getting triggered, but check register and the correct values are getting loaded in
		PUSHL $4			                 #4 is the size of the missile (n arg)
		PUSHL %EAX			               #EAX is the from argument (void ptr from malloc)
		PUSHL %EBX			               #EBX is to argument (the user arg)

		CALL mp1_copy_to_user

		POPL %EBX					              #preserve orig arg input
		POPL %EDX					              #EDX contains void ptr
		POPL %ECX					              #ECX is a junk register

get_status_copy_done:
    CMPL $0, %EAX  			                      #check if successful copy and that EAX is 0
    JE get_status_successful_copy              #if the copy function retval is 0, then it was successful
    JMP get_status_unsuccessful_copy           #otherwise, if not 0 it was unsuccessful_copy

get_status_successful_copy:

    PUSHL %EDX 				              #push void pointer as arg to free mem function
    CALL mp1_free
    POPL %EDX					              #pop input arg of void ptr

    MOVL $0, %EAX 				          #successful copy, return 0
    JMP get_status_done

get_status_unsuccessful_copy:

    		PUSHL %EDX 				              #push void pointer as arg to free mem function
    		CALL mp1_free
    		POPL %EDX					              #pop input arg of void ptr

        MOVL $-1, %EAX				          #unsuccessful_copy, return value -1
    		JMP get_status_done

get_status_done:
#last step: stack teardown
    popal
		LEAVE
		ret



mp1_ioctl_endgame:
    PUSHL %EBP
    MOVL %ESP, %EBP
    pushal

    MOVL $0, %EAX               #clear registers
    MOVL $0, %EBX
    MOVL $0, %ECX
    MOVL $0, %EDX
    MOVL $0, %ESI
    MOVL $0, %EDI

    MOVL mp1_missile_list, %EDI             #put missile list in reg
removal_loop:
    CMPL $0, %EDI                           #check if list is empty
    JE endgame_done
    MOVL NEXT(%EDI), %EBX                   #setup current node to be freed

    PUSHL %EDI                              #give arg to mp1 missile remove
    CALL mp1_missile_remove
    POPL %EDI                               #Pop orig arg

    MOVL %EBX, %EDI                          #move current node ptr to next node
    JMP removal_loop

endgame_done:
    popal
    LEAVE
    ret



mp1_missile_remove:
#Step 1: create stack frame
		PUSHL %EBP
		MOVL %ESP, %EBP
		pushal

    MOVL $0, %EAX               #clear registers
    MOVL $0, %EBX
    MOVL $0, %ECX
    MOVL $0, %EDX
    MOVL $0, %ESI
    MOVL $0, %EDI

#see where in list to remove
		MOVL 8(%EBP), %EDI						 #Get current node in mp1_missile_list from old EDI on previous stack
		CMPL mp1_missile_list, %EDI 	 #see if current node is the Head
		JE	remove_head								 #go to remove head logic
		JMP remove_in_list						 #go to remove in list logic
remove_head:
		MOVL NEXT(%EDI), %EBX             #get node after current head
		MOVL %EBX, mp1_missile_list				#set new head to be next node after current head
    MOVL $0, NEXT(%EDI)

		PUSHL %EDI											  #push arg to give to mp1_free
		CALL mp1_free
		POPL %EDI								          #pop argument given as input

		JMP remove_done

remove_in_list:
		MOVL mp1_missile_list, %EBX	  	#put the iterator into EBX to loop up to node prev to current node
loop_thru_list:
		CMPL NEXT(%EBX), %EDI					  #see if EBX is the previous node yet
		JE remove_node_from_middle
		MOVL NEXT(%EBX), %EBX					  #if not, then increment the node
		JMP loop_thru_list						  #loop
remove_node_from_middle:
		MOVL NEXT(%EDI), %ECX					#get the next node from the current node
    MOVL $0, NEXT(%EDI)           #set current node's next null
    MOVL %ECX, NEXT(%EBX)					#set the previous node's next to the next next node

		PUSHL %EDI										#set current node as argument to be freed
		CALL mp1_free
		POPL %EDI											#pop argument given as input

		JMP remove_done

#Step 5: tear down stack frame
remove_done:
    popal
		LEAVE
		ret







#end

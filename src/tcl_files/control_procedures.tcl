#___INFO__MARK_BEGIN__
##########################################################################
#
#  The Contents of this file are made available subject to the terms of
#  the Sun Industry Standards Source License Version 1.2
#
#  Sun Microsystems Inc., March, 2001
#
#
#  Sun Industry Standards Source License Version 1.2
#  =================================================
#  The contents of this file are subject to the Sun Industry Standards
#  Source License Version 1.2 (the "License"); You may not use this file
#  except in compliance with the License. You may obtain a copy of the
#  License at http://gridengine.sunsource.net/Gridengine_SISSL_license.html
#
#  Software provided under this License is provided on an "AS IS" basis,
#  WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING,
#  WITHOUT LIMITATION, WARRANTIES THAT THE SOFTWARE IS FREE OF DEFECTS,
#  MERCHANTABLE, FIT FOR A PARTICULAR PURPOSE, OR NON-INFRINGING.
#  See the License for the specific provisions governing your rights and
#  obligations concerning the Software.
#
#  The Initial Developer of the Original Code is: Sun Microsystems, Inc.
#
#  Copyright: 2001 by Sun Microsystems, Inc.
#
#  All Rights Reserved.
#
#  Portions of this software are Copyright (c) 2023-2024 HPC-Gridware GmbH
#
##########################################################################
#___INFO__MARK_END__

global module_name
set module_name "control_procedures.tcl"

global local_hostname_cache
set local_hostname_cache ""
# update an array with values of a second array
proc update_change_array { target_array change_array } {
   upvar $target_array target
   upvar $change_array chgar

   if [info exists chgar] {
      foreach elem [array names chgar] {
         set value [set chgar($elem)]
         ts_log_finer "attribute \"$elem\" will be set to \"$value\""
         set target($elem) $value
      }
   }
}

###
# @brief dump an array to a temporary file, return filename
#
# Dumps the contents of the given array to a temporary file.
# Optionally the host on which the data will be needed (qconf calling a fast option)
# can be given. If the host is the testsuite host, then the file will be written locally.
# Otherwise it will be written remotely.
#
# @param change_array array to dump
# @param hostname the host the command working on the file (qconf) will be executed on
##
proc dump_array_to_tmpfile {change_array {hostname ""}} {
   upvar $change_array chgar
   global CHECK_USER

   if [info exists chgar] {
      set ignored 0
      # build a file data array, data(0) is the number of lines, data(n) are the lines
      set idx 0
      foreach elem [array names chgar] {
         if {$elem == ""} {
            ts_log_fine "ignore empty elem"
            continue
         }
         set value $chgar($elem)
         if {$value != ""} {
            ts_log_finer "set \"$elem\" to \"$value\""
            incr idx ; set data($idx) "$elem $value"
         } else {
            ts_log_finer "skip array name \"$elem\""
            incr ignored
         }
      }
      if {$ignored != 0} {
         ts_log_fine "ignored $ignored line(s) because value was empty"
      }
      set data(0) $idx

      if {$hostname != ""} {
         # write to a local tmp file (in the /tmp directory)
         set tmpfile [get_tmp_file_name $hostname "default" "tmp" 1]
         if {$hostname == [gethostname]} {
            # we'll execute qconf on the local host, write it locally
            #ts_log_fine "====> writing local file $tmpfile on host $hostname"
            save_file $tmpfile data
         } else {
            # we'll execute qconf on a remote host, write it remotely
            #ts_log_fine "====> writing remote file $tmpfile on host $hostname"
            write_remote_file $hostname $CHECK_USER $tmpfile data
         }
      } else {
         set tmpfile [get_tmp_file_name]
         #ts_log_fine "====> writing remote file $tmpfile in results directory, as we have no hostname"
         save_file $tmpfile data
      }
   }

   return $tmpfile
}

###
# @brief dump an array (RQS) to a temporary file, return filename
#
# Dumps the contents of the given array to a temporary file.
# Optionally the host on which the data will be needed (qconf calling a fast option)
# can be given. If the host is the testsuite host, then the file will be written locally.
# Otherwise it will be written remotely.
#
# @param change_array array to dump
# @param hostname the host the command working on the file (qconf) will be executed on
##
proc dump_rqs_array_to_tmpfile {change_array hostname} {
   global CHECK_USER
   upvar $change_array chgar
   set tmpfile ""

   # TODO: It would be nice to have a syntax validation of the change_array
   #       before writing the file !!!
   if [info exists chgar] {
      set old_name ""
      set first 1

      # build a file data array, data(0) is the number of lines, data(n) are the lines
      set idx 0
      foreach elem [lsort [array names chgar]] {
         set help [split $elem ","]
         set name [lindex $help 0]
         set field [lindex $help 1]
         set value $chgar($elem)

         if {$old_name != $name} {
            # new rqs
            set old_name $name
            if {$first} {
               set first 0
            } else {
               incr idx ; set data($idx) "\}"
            }
            incr idx ; set data($idx) "\{" 
            incr idx ; set data($idx) "   name $name"
         }
         if {$field == "limit"} {
            foreach limit $value {
               incr idx ; set data($idx) "   limit $limit"
            }
         } else {
            incr idx ; set data($idx) "   $field $value"
         }
      } 

      incr idx ; set data($idx) "\}"
      set data(0) $idx

      # write to a local tmp file (in the /tmp directory)
      set tmpfile [get_tmp_file_name $hostname "default" "tmp" 1]
      if {$hostname == [gethostname]} {
         # we'll execute qconf on the local host, write it locally
         #ts_log_finer "writing local file $tmpfile"
         save_file $tmpfile data
      } else {
         # we'll execute qconf on a remote host, write it remotely
         #ts_log_finer "writing remote file $tmpfile"
         write_remote_file $hostname $CHECK_USER $tmpfile data
      }
   } else {
      ts_log_fine "WARNING: got not charray!"
   }

   ts_log_fine "tmpfile: $tmpfile"
   return $tmpfile
}


#****** control_procedures/get_string_value_between() **************************
#  NAME
#     get_string_value_between() -- string parsing function
#
#  SYNOPSIS
#     get_string_value_between { start end line } 
#
#  FUNCTION
#     This function will return the content between the strings $start and
#     $end which must occur in $line.
#
#  INPUTS
#     start - first search parameter (first occurance)
#     end   - second search parameter 
#             if $start == $end: (last occurance)
#             if -1            : get content till end of $line 
#     line  - string to parse 
#
#  RESULT
#     string
#*******************************************************************************
proc get_string_value_between { start end line } {
   set pos1 [string first "$start" $line]
   incr pos1 [string length $start]

   if { $end != -1 } {
      if { $start == $end } {
         set pos2 [string last "$end"   $line]
      } else {
         set pos2 [string first "$end"   $line]
      }
      incr pos2 -1
      return [string trim [string range $line $pos1 $pos2]]
   } else {
 
      return [string trim [string range $line $pos1 end]]
   }
}

#****** control_procedures/check_correct_testsuite_setup_user() ****************
#  NAME
#     check_correct_testsuite_setup_user() -- check port setup of user
#
#  SYNOPSIS
#     check_correct_testsuite_setup_user { error_text } 
#
#  FUNCTION
#     Check all used ports for this testsuite configuration. This is done by
#     starting the binary "test_cl_commlib". This binary is binding the port
#     which is set in the environment variable CL_PORT and starting up a server
#     process. If the startup was successful it will only run CL_RUNS seconds.
#
#     This test is done on all configured hosts for all ports. This procedure
#     only makes sense when the testsuite system is NOT running, otherwise the
#     ports are bound and the procedure will return with errors.
#
#     This procedure needs root access.
#
#  INPUTS
#     error_text - name of variable to store error messages
#
#  RESULT
#     0 on success, 1 on error
#*******************************************************************************
proc check_correct_testsuite_setup_user { error_text } {
   global CHECK_DISPLAY_OUTPUT 
   global CHECK_USER
   global ts_user_config
   upvar $error_text errors
   
   get_current_cluster_config_array ts_config
   set errors ""

   if {[have_root_passwd] == -1} {
      append errors "Need root rights! No root password specified in testsuite!\n"
      return 1
   }

   if {$ts_config(source_dir) == "none"} {
      append errors "Source directory is set to \"none\" - cannot test!\n"
      return 1
   }

   set check_ports [get_all_reserved_ports] 
   foreach port [checktree_get_required_ports] {
      lappend check_ports $port
   }

   # remove 0 ports and double entries
   set test_port_list {}
   foreach port $check_ports {
      if {$port > 0 && [lsearch -exact $test_port_list $port] < 0} {
         lappend test_port_list $port
      }
   }

   ts_log_fine "This testsuite configuration is using the following ports: $test_port_list"

   # do the checks ...
   foreach host [get_all_hosts] {
      foreach port $test_port_list {
         ts_log_fine "testing port $port on host \"$host\" ..."
         set client_binary [get_test_or_source_path "test_cl_commlib" $host]
         set my_env_list(CL_RUNS) 0
         set my_env_list(CL_PORT) $port
         set output [start_remote_prog $host root $client_binary "0 TCP" prg_exit_state 60 0 "" my_env_list]
         if { $prg_exit_state != 0} {
            append errors "Cannot bind port $port on host \"$host\" as user root!\n"
            ts_log_fine $output
         }
      }
   }

   # prepare return value
   if {$errors != ""} {
      return 1
   }
   return 0
}



#****** control_procedures/build_vi_command() **********************************
#  NAME
#     build_vi_command() -- build a vi command to set new values
#
#  SYNOPSIS
#     build_vi_command { change_array 
#     {current_array no_current_array_has_been_passed} } 
#
#  FUNCTION
#     take a name/value array and build a vi command to set new values
#
#  INPUTS
#     change_array       - array with new values
#     {current_array ""} - array with current (old) values
#
#  RESULT
#     vi command sequence string
#
#  SEE ALSO
#     ???/???
#*******************************************************************************
proc build_vi_command { change_array {current_array ""}} {
   upvar $change_array chgar

   if {$current_array != ""} {
      upvar $current_array curar
   }

   if {![info exists chgar]} {
      return ""
   }

   set vi_commands "" 

   if {[info exists curar]} {
      # compare the new values to old ones
      foreach elem [array names chgar] {
        # this will quote any / to \/  (for vi - search and replace)
        set newVal $chgar($elem)
      
        if {[info exists curar($elem)]} {
           # if old and new config have the same value, create no vi command,
           # if they differ, add vi command to ...
           if { [string compare $curar($elem) $newVal] != 0 } {
              if {$newVal == ""} {
                 # ... delete config entry (replace by comment)
                 lappend vi_commands ":%s/^$elem .*$/#/\n"
              } else {
                 # ... change config entry
                 set newVal1 [split $newVal {/}]
                 set newVal [join $newVal1 {\/}]
                 lappend vi_commands ":%s/^$elem .*$/$elem  $newVal/\n"
              }
           }
        } else {
           # if the config entry didn't exist in old config: append a new line
           if {$newVal != ""} {
              lappend vi_commands "A\n$elem  $newVal[format "%c" 27]"
           }
        }
     }
   } else {
      # we have no current values - just create a replace statement for each attribute
      foreach elem [array names chgar] {
         # this will quote any / to \/  (for vi - search and replace)
         set newVal $chgar($elem)
         if {$newVal != ""} {
            set newVal1 [split $newVal {/}]
            set newVal [join $newVal1 {\/}]
            lappend vi_commands ":%s/^$elem .*$/$elem  $newVal/\n"
         }
      }
   }

   return $vi_commands
}

# take a rqs array and build vi comand to set new values
proc build_rqs_vi_array { change_array } {
   upvar $change_array chgar

   if {![info exists chgar]} {
      return ""
   }

   set vi_commands ""

   set old_name ""

   foreach elem [lsort [array names chgar]] {
      set help [split $elem ","]
      set name [lindex $help 0]
      set field [lindex $help 1]
      set newVal $chgar($elem)

      if { $old_name != $name } {
         # new rule set
         set old_name $name

         # go to the next ruleset and set the name
         lappend vi_commands "/name\n"
         lappend vi_commands ":s/name.*/name  $name\n"
      }
      if { $newVal != "" } {
         # this will quote any / to \/ (or vi - search and replace)
         set newVal1 [split $newVal {/}]
         set newVal [join $newVal1 {\/}]
         if { $field == "limit" } {
            # delete all rules in this rule set 
            lappend vi_commands "/limit\n"
            lappend vi_commands "d?\}?-1\n"

            set rules ""
            foreach limit $newVal {
               # build new rule set string
               set rules "$rules limit $limit\n"
            }
            # add new rule sets
            lappend vi_commands "I$rules\n[format "%c" 27]"
         } else {
            lappend vi_commands ":s/$elem.*$/$elem  $newVal/\n"
         }
      }
   }

   return $vi_commands
}

# procedures
#                                                             max. column:     |
#****** control_procedures/handle_vi_edit() ******
# 
#  NAME
#     handle_vi_edit -- sending vi commands to application 
#
#  SYNOPSIS
#     handle_vi_edit { prog_binary prog_args vi_command_sequence 
#     expected_result {additional_expected_result "___ABCDEFG___"} 
#     {additional_expected_result2 "___ABCDEFG___"} 
#     {additional_expected_result3 "___ABCDEFG___"}} 
#     {qconf_error_msg "___ABCDEFG___"}
#     {raise_error  1} }
#
#
#  FUNCTION
#     Start an application which and send special command strings to it. Wait
#     and parse the application output.
#
#  INPUTS
#     prog_binary                                   - application binary to start 
#                                                     (e.g. qconf) 
#     prog_args                                     - application arguments (e.g. 
#                                                     -mconf) 
#     vi_command_sequence                           - list of vi command sequences 
#                                                     (e.g. 
#                                                     {:%s/^$elem .*$/$elem 10/\n}) 
#     expected_result                               - program output in no error 
#                                                     case (e.g. modified) 
#     {additional_expected_result "___ABCDEFG___"}  - additional expected_result 
#     {additional_expected_result2 "___ABCDEFG___"} - additional expected_result 
#     {additional_expected_result3 "___ABCDEFG___"} - additional expected_result
#     {qconf_error_msg "___ABCDEFG___"}            - qconf error message 
#     {raise_error  1}                                - do ts_log_severe in case of errors
#
#
#  RESULT
#     0 when the output of the application contents the expected_result 
#    -1 on timeout or other error
#    -2 on additional_expected_result
#    -3 on additional_expected_result2 
#    -4 on additional_expected_result3
#    -9 on chekcpointing qconf_error_msg
#
#  EXAMPLE
#     ??? 
#
#  NOTES
#     @deprecated
#
#  BUGS
#     ??? 
#
#  SEE ALSO
#     ???/???
#*******************************
proc handle_vi_edit { prog_binary prog_args vi_command_sequence expected_result {additional_expected_result "___ABCDEFG___"} {additional_expected_result2 "___ABCDEFG___"} {additional_expected_result3 "___ABCDEFG___"} {additional_expected_result4 "___ABCDEFG___"} {additional_expected_result5 "___ABCDEFG___"} {qconf_error_msg "___ABCDEFG___"} {raise_error 1} {additional_expected_result6 "___ABCDEFG___"}} {
   global env CHECK_DEBUG_LEVEL CHECK_USER
   get_current_cluster_config_array ts_config

   set expected_result              [string trimright $expected_result "*"]
   set additional_expected_result   [string trimright $additional_expected_result "*"]
   set additional_expected_result2  [string trimright $additional_expected_result2 "*"]
   set additional_expected_result3  [string trimright $additional_expected_result3 "*"]
   set additional_expected_result4  [string trimright $additional_expected_result4 "*"]
   set additional_expected_result5  [string trimright $additional_expected_result5 "*"]
   set additional_expected_result6  [string trimright $additional_expected_result6 "*"]
   set qconf_error_msg  [string trimright $qconf_error_msg "*"]

   # we want to start a certain configured vi, and have no backslash continued lines
   set host_for_vi $ts_config(master_host)
   set vi_env(EDITOR) [get_binary_path $host_for_vi "vim"]
   set result -100

   ts_log_finer "using vi editor on host '$host_for_vi' in path '$vi_env(EDITOR)'"
   # start program (e.g. qconf)
   set id [open_remote_spawn_process $host_for_vi $CHECK_USER $prog_binary "$prog_args" 0 "" vi_env]
   set sp_id [ lindex $id 1 ] 
   if {$CHECK_DEBUG_LEVEL != 0} {
      log_user 1
      set send_speed .001
   } else {
      log_user 0 ;# set to 1 if you wanna see vi responding
      set send_speed .0005
   }
   set send_slow "1 $send_speed" 

   ts_log_finest "now waiting for vi start ..."
   set error 0

   set timeout 15
   expect {
      -i $sp_id full_buffer {
         ts_log_severe "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
         set error 1
      }

      -i $sp_id eof {
         set error 1
         ts_log_severe "unexpected end of file"
      }

      -i $sp_id timeout {  
         set error 1
         ts_log_warning "timeout - can't start vi (1)"
      }
      -i $sp_id  "_start_mark_*\n" {
         ts_log_finest "starting now!"
      }
   }

   set timeout 60
   expect {
      -i $sp_id full_buffer {
         set error 1
         ts_log_severe "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
      }

      -i $sp_id eof {
         set error 1
         ts_log_severe "unexpected end of file"
      }


      -i $sp_id -- "$qconf_error_msg" {
         set error $raise_error
         ts_log_severe "$qconf_error_msg" $raise_error
         set result -9
         close_spawn_process $id
         return -9
      }

      -i $sp_id timeout {  
         set error 1
         ts_log_warning "timeout - can't start vi (2)"
      }
      -i $sp_id -- {[A-Za-z]*} {
         ts_log_finest "vi should run now ..."
      }
   }

   set timeout 1
   # wait for vi to startup and go to last line
   send -s -i $sp_id -- "G"
   set timeout_count 0

   expect {
      -i $sp_id full_buffer {
         ts_log_severe "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
         set error 1
      }

      -i $sp_id eof {
         ts_log_severe "unexpected end of file"
         set error 1
      }

      -i $sp_id timeout {  
         send -s -i $sp_id -- "G"
         incr timeout_count 1
         if { $timeout_count > 60 } {
            ts_log_warning "timeout - vi doesn't respond"
            set error 1
         } else {
            exp_continue
         }
      }

      -i $sp_id  "100%" {
      }
      
      -i $sp_id  "o lines in buffer" {
      }
      
      -i $sp_id  "erminal too wide" {
         ts_log_warning "got terminal to wide vi error"
         set error 1
      }
   }

   # we had an error during vi startup - close connection and return with error
   if {$error} {
      # maybe vi is up and we can exit
      send -s -i $sp_id -- "[format "%c" 27]" ;# ESC
      send -s -i $sp_id -- ":q!\n"            ;# exit without saving
      set timeout 10
      expect {
         -i $sp_id full_buffer {
            ts_log_severe "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
         }

         -i $sp_id eof {
            ts_log_severe "unexpected end of file"
         }

         -i $sp_id "_exit_status*\n" {
            ts_log_finest "vi terminated! (1)"
            exp_continue
         }

      }


      # close the connection - hopefully vi and/or the called command will exit
      close_spawn_process $id

      return -1
   }

   # second waiting: Part I:
   # =======================
   # set start time (qconf must take at least one second, because he
   # does a file stat to find out if the file was changed, so the
   # file edit process must take at least 1 second

   set start_time [clock clicks -milliseconds]
   # send the vi commands
   set timeout 1
   set timeout_count 0
   set sent_vi_commands 0
   send -s -i $sp_id -- "1G"      ;# go to first line


   foreach elem $vi_command_sequence {
      incr sent_vi_commands 1
      set com_length [ string length $elem ]
      set com_sent 0
      send -s -i $sp_id -- "$elem"
      send -s -i $sp_id -- ""
      set timeout 10
      expect {
         -i $sp_id full_buffer {
            ts_log_severe "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
            set error 1
         }

         -i $sp_id eof {
            ts_log_severe "unexpected end of file"
            set error 1
         }
         -i $sp_id "*Hit return*" {
            send -s -i $sp_id -- "\n"
            ts_log_finest "found Hit return"
            exp_continue
         }
         -i $sp_id timeout {
            incr timeout_count 1
            if { $timeout_count > 15 } {
               set error 2
            } else {
               send -s -i $sp_id -- ""
               exp_continue
            }
         }

         -i $sp_id "%" {
         }
      }
      if { $error != 0 } {
         break
      }
   }

   if { $error == 0 } {
      
      # second waiting: Part II:
      # =======================
      # wait for file time older one second
      # we give an extra waiting time of 100 ms to be sure that
      # the vi takes at least 1 second
      set end_time [expr [clock clicks -milliseconds] + 1100 ]
      while { [clock clicks -milliseconds] < $end_time } { 
         after 100
      }
      set run_time [expr [clock clicks -milliseconds] - $start_time]

      # save and exit
      if { $CHECK_DEBUG_LEVEL != 0 } {
         after 3000
      }
      send -s -i $sp_id -- ":wq\n"
      set timeout 60

      # we just execute and don't wait for a certain result:
      # wait for exit status of command
      if { [string compare "" $expected_result ] == 0 } {
         expect {
            -i $sp_id full_buffer {
               ts_log_severe "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
               set result -1
            }
            -i $sp_id timeout {
               ts_log_severe "timeout error:$expect_out(buffer)"
               set result -1
            }
            -i $sp_id eof {
               ts_log_severe "eof error:$expect_out(buffer)"
               set result -1
            }
            -i $sp_id "_exit_status_" {
               ts_log_finest "vi terminated! (2) (rt=$run_time)"
               set result 0
               exp_continue
            }

        }
      } else {
         # we do expect certain result(s)
         # wait for result and/or exit status

         expect {
            -i $sp_id full_buffer {
               ts_log_severe "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
               set result -1
            }
            -i $sp_id timeout {
               set result -1
               ts_log_severe "timeout error:$expect_out(buffer)"
            }
            -i $sp_id eof {
               ts_log_severe "eof error:$expect_out(buffer)"
               set result -1
            }
            -i $sp_id -- "$expected_result" {
               set result 0
               exp_continue
            }
            -i $sp_id -- "$additional_expected_result" {
               set result -2
               exp_continue
            }
            -i $sp_id -- "$additional_expected_result2" {
               set result -3
               exp_continue
            }
            -i $sp_id -- "$additional_expected_result3" {
               set result -4
               exp_continue
            }
            -i $sp_id -- "$additional_expected_result4" {
               set result -5
               exp_continue
            }
            -i $sp_id -- "$additional_expected_result5" {
               set result -6
               exp_continue
            }
            -i $sp_id -- "$additional_expected_result6" {
               set result -7
               exp_continue
            }
            
            -i $sp_id "_exit_status_" {
               ts_log_finest "vi terminated! (3)  (rt=$run_time)"
               if { $result == -100 } {
                  set pos [string last "\n" $expect_out(buffer)]
                  incr pos -2
                  set buffer_message [string range $expect_out(buffer) 0 $pos ]
                  set pos [string last "\n" $buffer_message]
                  incr pos 1
                  set buffer_message [string range $buffer_message $pos end] 

                  set message_txt ""
                  append message_txt "expect_out(buffer)=\"$expect_out(buffer)\""
                  append message_txt "expect out buffer is:\n"
                  append message_txt "   \"$buffer_message\"\n"
                  append message_txt "this doesn't match any given expression:\n"
                  append message_txt "   \"$expected_result\"\n"
                  append message_txt "   \"$additional_expected_result\"\n"
                  append message_txt "   \"$additional_expected_result2\"\n"
                  append message_txt "   \"$additional_expected_result3\"\n"
                  append message_txt "   \"$additional_expected_result4\"\n"
                  append message_txt "   \"$additional_expected_result6\"\n"
                  ts_log_severe $message_txt
               }
            }
         }
      }
      ts_log_finest "sent_vi_commands = $sent_vi_commands"
      if { $sent_vi_commands == 0 } {
         ts_log_finest "INFO: there was NO vi command sent!"
      }
   } else {
      if { $error == 2 } {
         send -s -i $sp_id -- "[format "%c" 27]" ;# ESC
         send -s -i $sp_id -- "[format "%c" 27]" ;# ESC
         send -s -i $sp_id -- ":q!\n"            ;# exit without saving
         set timeout 10
         expect -i $sp_id "_exit_status_"
         ts_log_finest "vi terminated! (4)"
         close_spawn_process $id
         set error_text ""
         append error_text "got timeout while sending vi commands (1)\n"
         append error_text "please make sure that no single vi command sequence\n"
         append error_text "leaves the vi in \"insert mode\" !!!"
         ts_log_severe $error_text
         return -1
      }
   }

   close_spawn_process $id

   # output what we have just done
   log_user 1
   foreach elem $vi_command_sequence {
      ts_log_finest "sequence: $elem"
      if { [string first "A" $elem ] != 0 } {
         set index1 [ string first "." $elem ]
         incr index1 -2
         set var [ string range $elem 5 $index1 ] 
        

         # TODO: CR - the string last $var index1 position setting
         #            is buggy, because it assumes that the value 
         #            doesn't contain $var.
         #
         #       example: load_sensor /path/load_sensor_script.sh
         #         this would return "_script.sh" as value
         #
         #       Value is only used for printing the changes to the user,
         #       so this is not "really" a bug
         #       
         set index1 [ string last "$var" $elem ]
         incr index1 [ string length $var]
         incr index1 2
   
         set index2 [ string first "\n" $elem ]
         incr index2 -2
   
         set value [ string range $elem $index1 $index2 ]
         set value [ split $value "\\" ]
         set value [ join $value "" ]
         if { [ string compare $value "*$/" ] == 0 || [ string compare $value "*$/#" ] == 0 } {
            ts_log_finest "--> removing \"$var\" entry"
         } else {
            if { [ string compare $var "" ] != 0 && [ string compare $value "" ] != 0  } {         
               ts_log_finest "--> setting \"$var\" to \"${value}\""
            } else {
               if { [string compare $elem [format "%c" 27]] == 0 } {
                  ts_log_finest "--> vi command: \"ESC\""    
               } else {
                  set output [replace_string $elem "\n" "\\n"]
                  ts_log_finest "--> vi command: \"$output\"" 
               }
            }
         }
      } else {
         set add_output [ string range $elem 2 end ]
         ts_log_finest "--> adding [string trim $add_output "[format "%c" 27] ^"]"
      }
   }

   # debug output end
   if {$CHECK_DEBUG_LEVEL != 0} {
      log_user 1
   } else {
      log_user 0 
   }

   return $result
}

#****** control_procedures/start_vi_edit() *************************************
# 
#  NAME
#     start_vi_edit -- sending vi commands to application 
#
#  SYNOPSIS
#     start_vi_edit {prog_binary prog_args vi_command_sequence msg_var {host ""} 
#     {user ""}}
#
#  FUNCTION
#     Start the client which uses vi for editing and wait for the command output.
#
#  INPUTS
#     prog_binary          - client binary to start (e.g. qconf) 
#     prog_args            - client arguments (e.g. -mconf) 
#     vi_command_sequence  - list of vi command sequences 
#                            (e.g. {:%s/^$elem .*$/$elem 10/\n}) 
#     msg_var              - the array of expected messages
#     {host ""}            - host on which to execute command - default: any host
#     {user ""}            - user who shall call command
#
#  RESULT
#     Output of called command.
#
#  NOTE
#     this is overwritten procedure handle_vi_edit with a non fixed count of 
#     messages.
#*******************************************************************************
proc start_vi_edit {prog_binary prog_args vi_command_sequence msg_var {host ""} {user ""}} {
   #TODO: Should also return the exit_code of executed prog_binary and report it up
   global CHECK_USER CHECK_DEBUG_LEVEL env
   get_current_cluster_config_array ts_config
   upvar $msg_var messages

   if {$host == ""} {
      set host [host_conf_get_suited_hosts]
   }

   if {$user == ""} {
      set user $CHECK_USER
   }
   
   set arch [resolve_arch $host]
   set vi_env(EDITOR) [get_binary_path $host "vim"]
   set binary "$ts_config(product_root)/bin/$arch/$prog_binary"
   set result ""
   
   ts_log_finest "using EDITOR=$vi_env(EDITOR)"
   # start program (e.g. qconf)

   set id [open_remote_spawn_process $host $user $binary "$prog_args" 0 "" vi_env]

   set sp_id [ lindex $id 1 ] 
   if {$CHECK_DEBUG_LEVEL != 0} {
      log_user 1
      set send_speed .001
   } else {
      log_user 0 ;# set to 1 if you wanna see vi responding
      set send_speed .0005
   }
   set send_slow "1 $send_speed" 

   ts_log_finest "now waiting for vi start ..."
   set error 0
   
   set BUFF_OVERFLOW "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
   set EOF_MSG "unexpected end of file"
   set TMOUT_START "timeout - can't start vi (3)"

   set timeout 30
   expect {
      -i $sp_id full_buffer {
         set result $BUFF_OVERFLOW
         set error 1
      }

      -i $sp_id eof {
         set error 1
         set result $EOF_MSG
      }

      -i $sp_id timeout {  
         set error 1
         set result $TMOUT_START
      }
      -i $sp_id  "_start_mark_*\n" {
         ts_log_finest "starting now!"
      }
   }

   set timeout 30
   expect {
      -i $sp_id full_buffer {
         set error 1
         set result $BUFF_OVERFLOW
      }

      -i $sp_id eof {
         set error 1
         set result $EOF_MSG
      }

      -i $sp_id timeout {  
         set error 1
         set result $TMOUT_START
      }

      -i $sp_id -- {[A-Za-z]*} {
         foreach line [split $expect_out(buffer) "\n"] {
            set res_line [string trim "$line"]
            foreach errno $messages(index) {
               if {$errno != 0} {
                  if {[string match "*$messages($errno)*" $res_line] == 1} {
                     close_spawn_process $id
                     return $messages($errno)
                  }
               }   
            }            
         }
         ts_log_finest "vi should run now ..."
      }
   }

   set timeout 1
   # wait for vi to startup and go to last line
   send -s -i $sp_id -- "G"
   set timeout_count 0

   set TMOUT_RESP "timeout - vi doesn't respond"

   expect {
      -i $sp_id full_buffer {
         set result $BUFF_OVERFLOW
         set error 1
      }

      -i $sp_id eof {
         set result $EOF_MSG
         set error 1
      }

      -i $sp_id timeout {  
         send -s -i $sp_id -- "G"
         incr timeout_count 1
         if { $timeout_count > 60 } {
            set result $TMOUT_RESP
            set error 1
         } else {
            exp_continue
         }
      }

      -i $sp_id  "100%" {
      }
      
      -i $sp_id  "o lines in buffer" {
      }
      
      -i $sp_id  "erminal too wide" {
         set WIDE "got terminal to wide vi error"
         set result $WIDE
         set error 1
      }
   }

   # we had an error during vi startup - close connection and return with error
   if { $error != 0 } {
      add_message_to_container messages -1 $result
      # maybe vi is up and we can exit
      send -s -i $sp_id -- "[format "%c" 27]" ;# ESC
      send -s -i $sp_id -- ":q!\n"            ;# exit without saving
      set timeout 10
      expect {
         -i $sp_id full_buffer {
            ts_log_severe $BUFF_OVERFLOW
         }

         -i $sp_id eof {
            ts_log_severe $EOF_MSG
         }

         -i $sp_id "_exit_status*\n" {
            ts_log_finest "vi terminated! (1)"
            exp_continue
         }

      }

      # close the connection - hopefully vi and/or the called command will exit
      close_spawn_process $id

      return $result
   }

   # second waiting: Part I:
   # =======================
   # set start time (qconf must take at least one second, because he
   # does a file stat to find out if the file was changed, so the
   # file edit process must take at least 1 second

   set start_time [clock clicks -milliseconds]
   # send the vi commands
   set timeout 1
   set timeout_count 0
   set sent_vi_commands 0
   send -s -i $sp_id -- "1G"      ;# go to first line

   foreach elem $vi_command_sequence {
      incr sent_vi_commands 1
      set com_length [ string length $elem ]
      set com_sent 0
      send -s -i $sp_id -- "$elem"
      send -s -i $sp_id -- ""
      set timeout 10
      expect {
         -i $sp_id full_buffer {
            set result $BUFF_OVERFLOW
            set error 1
         }

         -i $sp_id eof {
            set result $EOF_MSG
            set error 1
         }
         -i $sp_id "*Hit return*" {
            send -s -i $sp_id -- "\n"
            ts_log_finest "found Hit return"
            exp_continue
         }
         -i $sp_id timeout {
            incr timeout_count 1
            if { $timeout_count > 15 } {
               set error_text ""
               append error_text "got timeout while sending vi commands (2)\n"
               append error_text "please make sure that no single vi command sequence\n"
               append error_text "leaves the vi in \"insert mode\" !!!"
               set result $error_text
               set error 1
            } else {
               send -s -i $sp_id -- ""
               exp_continue
            }
         }

         -i $sp_id "%" {
         }
      }
      if { $error != 0 } {
         break
      }
   }

   if { $error != 0 } {
      add_message_to_container messages -1 $result
      send -s -i $sp_id -- "[format "%c" 27]" ;# ESC
      send -s -i $sp_id -- ":q!\n"            ;# exit without saving
      set timeout 10
      expect -i $sp_id "_exit_status_"
      ts_log_finest "vi terminated! (4)"
      close_spawn_process $id
      return $result
   }

   # second waiting: Part II:
   # =======================
   # wait for file time older one second
   # we give an extra waiting time of 100 ms to be sure that
   # the vi takes at least 1 second
   set end_time [expr [clock clicks -milliseconds] + 1100 ]
   while { [clock clicks -milliseconds] < $end_time } { 
      after 100
   }
   set run_time [expr [clock clicks -milliseconds] - $start_time]

   # save and exit
   if { $CHECK_DEBUG_LEVEL != 0 } {
      after 3000
   }
   send -s -i $sp_id -- ":wq\n"
   set timeout 60

   # we just execute and don't wait for a certain result:
   # wait for exit status of command
   expect {
      -i $sp_id full_buffer {
         set result $BUFF_OVERFLOW
      }
      -i $sp_id timeout {
         set TMOUT_BUFFER "timeout error:$expect_out(buffer)"
         set result $TMOUT_BUFFER
      }
      -i $sp_id eof {
         set EOF_BUFFER "eof error:$expect_out(buffer)"
         set result $EOF_BUFFER
      }

      -i $sp_id "*_exit_status_*" {
         ts_log_finest "vi terminated! (2) (rt=$run_time)"
         foreach line [split $expect_out(buffer) "\n"] {
            set res_line [string trim $line]
            # skip empty lines
            if {$res_line != ""} {
               set found 0
               foreach errno $messages(index) {
                  if {[string match "*$messages($errno)*" $res_line] == 1} {
                     set result $messages($errno)
                     set found 1
                     break
                  }
               }
               # with multi line output, take the first matching line
               if {$found} {
                  break
               } else {
                  ts_log_finer "unexpected output: $res_line"
               }
            }
         }
      }
    }
   ts_log_finest "sent_vi_commands = $sent_vi_commands"
   if { $sent_vi_commands == 0 } {
      ts_log_finest "INFO: there was NO vi command sent!"
   }

   close_spawn_process $id

   # output what we have just done
   log_user 1
   foreach elem $vi_command_sequence {
      ts_log_finest "sequence: $elem"
      if { [string first "A" $elem ] != 0 } {
         set index1 [ string first "." $elem ]
         incr index1 -2
         set var [ string range $elem 5 $index1 ] 
        

         # TODO: CR - the string last $var index1 position setting
         #            is buggy, because it assumes that the value 
         #            doesn't contain $var.
         #
         #       example: load_sensor /path/load_sensor_script.sh
         #         this would return "_script.sh" as value
         #
         #       Value is only used for printing the changes to the user,
         #       so this is not "really" a bug
         #       
         set index1 [ string last "$var" $elem ]
         incr index1 [ string length $var]
         incr index1 2
   
         set index2 [ string first "\n" $elem ]
         incr index2 -2
   
         set value [ string range $elem $index1 $index2 ]
         set value [ split $value "\\" ]
         set value [ join $value "" ]
         if { [ string compare $value "*$/" ] == 0 || [ string compare $value "*$/#" ] == 0 } {
            ts_log_finest "--> removing \"$var\" entry"
         } else {
            if { [ string compare $var "" ] != 0 && [ string compare $value "" ] != 0  } {         
               ts_log_finest "--> setting \"$var\" to \"${value}\""
            } else {
               if { [string compare $elem [format "%c" 27]] == 0 } {
                  ts_log_finest "--> vi command: \"ESC\""    
               } else {
                  set output [replace_string $elem "\n" "\\n"]
                  ts_log_finest "--> vi command: \"$output\"" 
               }
            }
         }
      } else {
         set add_output [ string range $elem 2 end ]
         ts_log_finest "--> adding [string trim $add_output "[format "%c" 27] ^"]"
      }
   }

   # debug output end
   if {$CHECK_DEBUG_LEVEL != 0} {
      log_user 1
   } else {
      log_user 0 
   }

   return $result   
}

#****** control_procedures/get_uid() *******************************************
#  NAME
#     get_uid() -- get user id for user on host
#
#  SYNOPSIS
#     get_uid {user host}
#
#  FUNCTION
#     The function returns the user id of user $user on host $host
#
#  INPUTS
#     user - username
#     host - hostname 
#
#  RESULT
#     string containing user id
#
#  SEE ALSO
#     control_procedures/get_uid()
#     control_procedures/get_gid()
#*******************************************************************************
proc get_uid { user host } {
   set my_uid -1

   set output [start_remote_prog $host $user id ""]
   set output [string trim [split $output " =()"]]
   set found_uid 0
   foreach line $output {
      if { $found_uid == 1 } {
         set my_uid $line
         break
      }
      if { $line == "uid" } {
         set found_uid 1
      }
   }
   return $my_uid
}


#****** control_procedures/get_gid() *******************************************
#  NAME
#     get_gid() -- get group id for user on host
#
#  SYNOPSIS
#     get_gid { user host } 
#
#  FUNCTION
#     The function returns the group id of user $user on host $host
#
#  INPUTS
#     user - username 
#     host - hostname 
#
#  RESULT
#     string containing group id
#
#  SEE ALSO
#     control_procedures/get_uid()
#     control_procedures/get_gid()
#*******************************************************************************
proc get_gid { user host } {
   set my_gid -1

   set output [start_remote_prog $host $user id ""]
   set output [string trim [split $output " =()"]]
   set found_gid 0
   foreach line $output {
      if { $found_gid == 1 } {
         set my_gid $line
         break
      }
      if { $line == "gid" } {
         set found_gid 1
      }
   }
   return $my_gid
}



#                                                             max. column:     |
#****** control_procedures/ps_grep() ******
# 
#  NAME
#     ps_grep -- call get_ps_info and return only expected ps information 
#
#  SYNOPSIS
#     ps_grep { forwhat { host "local" } { variable ps_info } } 
#
#  FUNCTION
#     This procedure will call the get_ps_info procedure. It will parse the 
#     get_ps_info result for the given strings and return only those process 
#     ids which match. 
#
#  INPUTS
#     forwhat              - search string (e.g. binary name) 
#     { host "local" }     - host on which the ps command should be called 
#     { variable ps_info } - variable name to store the result (default ps_info) 
#
#  RESULT
#     returns a list of indexes where the search string matches the ps output. 
#
#  EXAMPLE
# 
#   set myprocs [ ps_grep "execd" "fangorn" ]
#
#   puts "execd's on fangorn index list: $myprocs"
#
#   foreach elem $myprocs {
#     puts $ps_info(string,$elem)
#   }
#
#   output of example:
# 
#   execd's on fangorn index list: 34 39 50 59 61
#   2530   140     1   259 S Sep12  1916 00:00:14 /sge_s/glinux/sge_execd
#   7700   142     1   339 S Sep13  2024 00:03:49 /vol2/bin/glinux/sge_execd
#   19159     0     1     0 S Sep14  1772 00:31:09 /vol/bin/glinux/sgeee_execd
#   24148     0     1     0 S Sep14  2088 00:06:23 bin/glinux/sge_execd
#   15085     0     1     0 S Sep14  1904 00:27:04 /vol2/glinux/sgeee_execd
#
#  NOTES
#   look at get_ps_info procedure for more information! 
#
#  BUGS
#     ??? 
#
#  SEE ALSO
#     control_procedures/get_ps_info
#*******************************
proc ps_grep {forwhat {host "local"} {variable ps_info}} {
   upvar $variable psinfo

   unset -nocomplain psinfo

   get_ps_info 0 $host psinfo

   set index_list ""

   for {set i 0} {$i < $psinfo(proc_count) } {incr i 1} {
      if {[string first $forwhat $psinfo(string,$i) ] >= 0} {
         lappend index_list $i
      }
   }
   return $index_list
} 



#                                                             max. column:     |
#****** control_procedures/get_ps_info() ******
# 
#  NAME
#     get_ps_info -- get ps output on remote or local host 
#
#  SYNOPSIS
#     get_ps_info { { pid 0 } { host "local"} { variable ps_info } 
#     {additional_run 0} } 
#
#  FUNCTION
#     This procedure will call ps on the host given and parse the output. All 
#     information is stored in a special array. If no variable parameter is 
#     given the array has the name ps_info 
#
#  INPUTS
#     { pid 0 }            - set pid for ps_info($pid,error) the 
#                            ps_info([given pid],error) array is always set when 
#                            the pid is given. You have always access to 
#                            ps_info($pid,error)
#     { host "master"}     - host on which the ps command should be started
#     { variable ps_info } - array name where the ps command output should be 
#                            stored the default for this value is "ps_info"
#     {additional_run 0}   - if it is neccessary to start more than one ps command
#                            to get the full information this number is used to be 
#                            able to differ the recursive subcalls. So this 
#                            parameter is only set when the procedure calls itself 
#                            again.
#
#
#  RESULT
#     The procedure returns an 2 dimensional array with following entries:
#
#     If the parameter pid was set to 12 then ps_info(12,error) exists after 
#     calling this procedure ps_info(12,error) is set to 0 when the pid 12 exists, 
#     otherwise it is set to -1 
#
#     when ps_info(12,error) exists the following indicies are available:
# 
#     ps_info(12,string)
#     ps_info(12,index_names)
#     ps_info(12,pgid)
#     ps_info(12,ppid)
#     ps_info(12,uid)
#     ps_info(12,state)
#     ps_info(12,stime)
#     ps_info(12,vsz)
#     ps_info(12,time)
#     ps_info(12,command)
#     ps_info(12,nice)
#
#     every output of the ps command is stored into these indicies: 
#     (I is the line number (or index) of the output)
#
#     ps_info(proc_count)   : number of processes (line count of ps command)
#     ps_info(pid,I)        : pid of process
#     ps_info(pgid,I)       : process group id
#     ps_info(ppid,I)       : parent pid
#     ps_info(uid,I)        : user id
#     ps_info(state,I)      : state
#     ps_info(stime,I)      : start time 
#     ps_info(vsz,I)        : virtual size
#     ps_info(time,I)       : cpu time 
#     ps_info(command,I)    : command arguments of process
#     ps_info(nice,I)       : nice level of the process
#     ps_info(string,I)     : complete line
#
#  EXAMPLE
#
#     get process group id of pid 3919:
# 
#     get_ps_info 3919 fangorn
#     if {$ps_info(3919,error) == 0} {
#        puts "process group id of pid 3919 is $ps_info(3919,pgid)"
#     } else {
#        puts "pid 3919 not found!"
#     }
#
#
#
#     print out all pids on local host:
#     
#     get_ps_info 
#     for {set i 0} {$i < $ps_info(proc_count) } {incr i 1} {
#        puts "ps_info(pid,$i)     = $ps_info(pid,$i)"
#     }
#
#  NOTES
#     o additional_run is for glinux at this time
#     o additionan_run is a number from 0 up to xxx at the end of the procedure 
#       it will start again a ps command with other information in order to mix 
#       up the information into one resulting list
#
#     o this procedure should run on following platforms:
#       solaris64, solaris
#
#  BUGS
#     ??? 
#
#  SEE ALSO
#     control_procedures/ps_grep
#*******************************
proc get_ps_info { { pid 0 } { host "master"} { info_array ps_info } {additional_run 0} } {
   global CHECK_USER ts_config
   upvar $info_array psinfo

   if { [string compare $host "master" ] == 0 } {
      set host $ts_config(master_host)
   } 

   if {[info exists psinfo]} {
      unset psinfo
   }

   set psinfo($pid,error) -1
   set psinfo(proc_count) 0
   set psinfo($pid,string) "not found"


   set host_arch [resolve_arch $host]
   
   #puts "arch on host $host is $host_arch"
   
   # ATTENTION: command_pos (args column) must be the last column !!!
   # Testsuite needs at least 61 chars from that column to detect the product root PATH
   # NOTE: On some archs the last column is not truncated, on some archs it is, so please be patient !

   switch -glob -- $host_arch {
      "sol*" -
      "usol-*" {
         set myenvironment(COLUMNS) "1000"
         set result [start_remote_prog "$host" "$CHECK_USER" "ps" "-e -o \"pid=_____pid\" -o \"pgid=_____pgid\" -o \"ppid=_____ppid\" -o \"uid=_____uid\" -o \"s=_____s\" -o \"stime=_____stime\" -o \"vsz=_____vsz\" -o \"time=_____time\" -o \"nice=_____nice\" -o \"args=_____args\"" prg_exit_state 60 0 "" myenvironment 1 0]
         set index_names "_____pid _____pgid _____ppid _____uid _____s _____stime _____vsz _____time _____nice _____args"
         set pid_pos     0
         set gid_pos     1
         set ppid_pos    2
         set uid_pos     3
         set state_pos   4
         set stime_pos   5
         set vsz_pos     6
         set time_pos    7
         set command_pos 9
         set nice_pos    8
      }
    
      "darwi*" {
         set myenvironment(COLUMNS) "1000"
         set result [start_remote_prog "$host" "$CHECK_USER" "ps" "-awwx -o \"pid=_____pid\" -o \"pgid=_____pgid\" -o \"ppid=_____ppid\" -o \"uid=_____uid\" -o \"state=_____s\" -o \"stime=_____stime\" -o \"vsz=_____vsz\" -o \"time=_____time\" -o \"nice=_____nice\" -o \"command=_____args\"" prg_exit_state 60 0 "" myenvironment 1 0]
         set index_names "_____pid _____pgid _____ppid _____uid _____s _____stime _____vsz _____time _____nice _____args"
         set pid_pos     0
         set gid_pos     1
         set ppid_pos    2
         set uid_pos     3
         set state_pos   4
         set stime_pos   5
         set vsz_pos     6
         set time_pos    7
         set command_pos 9
         set nice_pos    8
      }

      "fbsd*" {
         set myenvironment(COLUMNS) "1000"
         #set result [start_remote_prog "$host" "$CHECK_USER" "ps" "-eo \"pid pgid ppid uid state start vsz time args\"" prg_exit_state 60 0 "" myenvironment 1 0]
         #set index_names "  PID  PGID  PPID   UID STAT STARTED   VSZ      TIME COMMAND"
         set result [start_remote_prog "$host" "$CHECK_USER" "ps" "-axww -o \"pid=_____pid\" -o \"pgid=_____pgid\" -o \"ppid=_____ppid\" -o \"uid=_____uid\" -o \"state=_____s\" -o \"start=_____stime\" -o \"vsz=_____vsz\" -o \"time=________time\" -o \"args=_____args\"" prg_exit_state 60 0 "" myenvironment 1 0]
         set index_names "_____pid _____pgid _____ppid _____uid _____s _____stime _____vsz ________time _____args"
         set pid_pos     0
         set gid_pos     1
         set ppid_pos    2
         set uid_pos     3
         set state_pos   4
         set stime_pos   5
         set vsz_pos     6
         set time_pos    7
         set command_pos 8
         set nice_pos   -1
      }
 
      "lx2?-*" -
      "ulx24-*" -
      "lx-*" -
      "xlx-*" -
      "ulx-*" {
         set myenvironment(COLUMNS) "1000"
         set result [start_remote_prog "$host" "$CHECK_USER" "ps" "-weo \"pid pgid ppid uid=BIGGERUID s stime vsz time nice args=COMMANDCOMMANDCOMMANDCOMMANDCOMMAND\"" prg_exit_state 60 0 "" myenvironment 1 0]
         set index_names "  PID  PGID  PPID BIGGERUID S STIME   VSZ     TIME NI COMMANDCOMMANDCOMMANDCOMMANDCOMMAND"
         set pid_pos     0
         set gid_pos     1
         set ppid_pos    2
         set uid_pos     3
         set state_pos   4
         set stime_pos   5
         set vsz_pos     6
         set time_pos    7
         set nice_pos    8
         set command_pos 9
      }

      "lx22-alpha" -
      "lx24-alpha" {
         if { $additional_run == 0 } {
            # this is the first ps without any size position
            set myenvironment(COLUMNS) "1000"
            set result [start_remote_prog "$host" "$CHECK_USER" "ps" "xajw" prg_exit_state 60 0 "" myenvironment 1 0]
            #                   0     1    2      3   4    5      6   7     8     9
            set index_names " PPID   PID  PGID   SID TTY TPGID  STAT  UID   TIME COMMAND"
            set pid_pos     1
            set gid_pos     2
            set ppid_pos    0
            set uid_pos     7
            set state_pos   6
            set stime_pos   -1
            set vsz_pos     -1
            set time_pos    8
            set command_pos 9
            set nice_pos    -1
         } 
         if { $additional_run == 1 } {
            # this is the first ps without any size position
            set myenvironment(COLUMNS) "1000"
            set result [start_remote_prog "$host" "$CHECK_USER" "ps" "waux" prg_exit_state 60 0 "" myenvironment 1 0]
            #                   0       1    2    3     4      5   6   7    8       9   10
            set index_names "{USER    }   PID %CPU %MEM  SIZE   RSS TTY STAT START   TIME COMMAND"
            set pid_pos     1
            set gid_pos     -1
            set ppid_pos    -1
            set uid_pos     -1
            set state_pos   7
            set stime_pos   8
            set vsz_pos     4
            set time_pos    9
            set command_pos 10
            set nice_pos    -1
         } 
      }

      "nbsd-*" {
         set result [start_remote_prog "$host" "$CHECK_USER" "ps" "-axww -o \"pid=_____pid pgid=_____pgid ppid=_____ppid uid=_____uid state=_____s stime=_____stime vsz=_____vsz time=_____time args=_____args\"" prg_exit_state 60 0 "" myenvironment 1 0]
         set index_names "_____pid _____pgid _____ppid _____uid _____s _____stime _____vsz _____time _____args"
         set pid_pos     0
         set gid_pos     1
         set ppid_pos    2
         set uid_pos     3
         set state_pos   4
         set stime_pos   5
         set vsz_pos     6
         set time_pos    7
         set command_pos 8
         set nice_pos    -1
      }
	
      default {
         set result "unknown architecture"
         set prg_exit_state 1
         set index_names "  PID   GID  PPID   UID S    STIME  VSZ        TIME NICE COMMAND"
         set pid_pos     0
         set gid_pos     1
         set ppid_pos    2
         set uid_pos     3
         set state_pos   4
         set stime_pos   5
         set vsz_pos     6
         set time_pos    7
         set command_pos 9 
         set nice_pos    8
      }
   }

   if {$prg_exit_state != 0} {
      ts_log_severe "ps failed:\n$result"
      return
   }

   set help_list [split $result "\n"]

   # delete empty lines (occurs e.g. on alinux)
   set empty_index [lsearch -exact $help_list ""]
   while {$empty_index >= 0} {
      set help_list [lreplace $help_list $empty_index $empty_index]
      set empty_index [lsearch -exact $help_list ""]
   }

   # search ps header line
   set num_lines [llength $help_list]
   set compare_pattern [string range $index_names 1 5]
   for {set x 0} {$x < $num_lines} {incr x 1} {
      if {[string first $compare_pattern [lindex $help_list $x]] >= 0} {
         break
      }
         
   }

   # no header found?
   if { $x == $num_lines } {
      ts_log_severe "no usable data from ps command, host=$host, host_arch=$host_arch"
      return
   }
  
   set header [ lindex $help_list $x]
   
   # cut heading garbage and header line
   set ps_list [ lrange $help_list [expr $x + 1] [expr ([llength $help_list]-1)]]
   
#   ts_log_fine "index names: \n$index_names" 
#   ts_log_fine "          1         2         3         4         5         6         7         8         9"
#   ts_log_fine "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"
#   ts_log_fine "header:\n$header"
   
   set s_index 0
   set indexcount [llength $index_names]
   foreach index $index_names { 
      incr indexcount -1
      set position1 [string first $index $header]
#      ts_log_fine "\nstringlength of $index is [string length $index]"
#      ts_log_fine "position1 is $position1"
      set last_position [expr ($position1 + [string length $index] - 1)]
      if {$indexcount == 0 } {
         set last_position [expr $myenvironment(COLUMNS) - 1]
      }
      set first_position $s_index 
      set s_index [ expr ($last_position + 1 )]
      #ts_log_fine "position of \"$index\" is from $first_position to $last_position"
      set read_header ""
      for { set i 0} {$i< $s_index} {incr i 1} {
          set read_header "!$read_header"
      }
      set header "$read_header[string range $header $s_index [expr ([string length $header])]]"
      #puts "header is now:\n$header"

      set pos1_list($index) $first_position
      set pos2_list($index) $last_position
   }

   set process_count 0
   foreach elem $ps_list {
#   ts_log_fine $elem
#         set pid_pos     0
#         set gid_pos     1
#         set ppid_pos    2
#         set uid_pos     3
#         set state_pos   4
#         set stime_pos   5
#         set vsz_pos     6
#         set time_pos    7
#         set command_pos 8

      if {$pid_pos != -1} {
         set pid_index_name [lindex $index_names $pid_pos]
         set act_pid_string [string range $elem $pos1_list($pid_index_name)  $pos2_list($pid_index_name)]
         set act_pid [string trim $act_pid_string] 
      } else {
         set act_pid -1
      }
      #puts "$act_pid : \"$elem\""
      set psinfo($act_pid,error)  0
      set psinfo($act_pid,string) $elem
      set psinfo(string,$process_count) $elem
      set psinfo($act_pid,index_names) $index_names 
      set psinfo(pid,$process_count) $act_pid
      #puts "${variable}(pid,$process_count) = $act_pid"
    
#     PGID
      if {$gid_pos != -1} { 
         set name  [lindex $index_names $gid_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str] 
      set psinfo($act_pid,pgid) $value 
      set psinfo(pgid,$process_count) $value

#     PPID 
      if {$ppid_pos != -1} { 
         set name  [lindex $index_names $ppid_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str] 
      set psinfo($act_pid,ppid) $value 
      set psinfo(ppid,$process_count) $value

#     UID 
      if { $uid_pos != -1} {
         set name  [lindex $index_names $uid_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str] 
      set psinfo($act_pid,uid) $value
      set psinfo(uid,$process_count) $value
 
#     STATE 
      if { $state_pos != -1} {
         set name  [lindex $index_names $state_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str] 
      set psinfo($act_pid,state) $value 
      set psinfo(state,$process_count) $value

#     STIME 
      if { $stime_pos  != -1} {
         set name  [lindex $index_names $stime_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str] 
      set psinfo($act_pid,stime) $value 
      set psinfo(stime,$process_count) $value

#     VSZ
      if { $vsz_pos != -1} {  
         set name  [lindex $index_names $vsz_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str] 
      set psinfo($act_pid,vsz) $value 
      set psinfo(vsz,$process_count) $value

#     TIME
      if { $time_pos != -1} { 
         set name  [lindex $index_names $time_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str] 
      set psinfo($act_pid,time) $value 
      set psinfo(time,$process_count) $value

#     COMMAND
      if { $command_pos != -1} {
         set name  [lindex $index_names $command_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str]
      set psinfo($act_pid,command) $value
      set psinfo(command,$process_count) $value

      incr process_count 1
      set psinfo(proc_count) $process_count

#     NICE
      if { $nice_pos != -1} { 
         set name  [lindex $index_names $nice_pos]
         set value_str [string range $elem $pos1_list($name)  $pos2_list($name)]
      } else {
         set value_str "unknown"
      }
      set value [string trim $value_str] 
      set psinfo($act_pid,nice) $value 
      set psinfo(nice,$process_count) $value
   }

      
# PID  PGID  PPID   UID S    STIME  VSZ        TIME COMMAND NICE

   # here is the merge of more ps commands happening
   switch -- $host_arch {
      "alinux" {
         if { $additional_run == 0 } { 
            # calling second ps
            get_ps_info $pid $host ps_add_run 1
            #ts_log_fine "ps_add_run $pid is $ps_add_run($pid,string)"
            # now merge the relevant data
            for {set i 0} {$i < $psinfo(proc_count) } {incr i 1} {
               set act_pid $psinfo(pid,$i)
               #set act_pid $ps_add_run(pid,$i)
               if {[info exists ps_add_run($act_pid,vsz)]} {
                  #ts_log_fine "     copy got value vsz for pid $act_pid"
                  #ts_log_fine "       old value psinfo(vsz,$i) = $psinfo(vsz,$i)"
                  #ts_log_fine "       old value psinfo(stime,$i) = $psinfo(stime,$i)"
                  set psinfo(vsz,$i) $ps_add_run($act_pid,vsz)
                  set psinfo(stime,$i) $ps_add_run($act_pid,stime)
                  #ts_log_fine "       new value psinfo(vsz,$i) = $psinfo(vsz,$i)"
                  #ts_log_fine "       new value psinfo(stime,$i) = $psinfo(stime,$i)"
                  #ts_log_fine "        old value psinfo($act_pid,vsz) = $psinfo($act_pid,vsz)"
                  #ts_log_fine "        old value psinfo($act_pid,stime) = $psinfo($act_pid,stime)"
                  set psinfo($act_pid,vsz) $ps_add_run($act_pid,vsz)
                  set psinfo($act_pid,stime) $ps_add_run($act_pid,stime)
                  #ts_log_fine "        new value psinfo($act_pid,vsz) = $psinfo($act_pid,vsz)"
                  #ts_log_fine "        new value psinfo($act_pid,stime) = $psinfo($act_pid,stime)"
                  
               } else {
                  ts_log_fine "--> value vsz for pid $act_pid not found"
               }
            }
            return
         } 
         if { $additional_run == 1 } { 
            # second ps run
            return
         } 
      }
   }
}

#****** control_procedures/gethostname() ***************************************
#  NAME
#     gethostname() -- returns the name of the local host
#
#  SYNOPSIS
#     gethostname { { do_debug_puts 1} {source_dir_path ""} } 
#
#  FUNCTION
#     returns the name of the local machine (but not "localhost") and uses
#     the SGE gethostbyname binary call if possible. If $SGE_ROOT is not availabe
#     the hostname is catched via call to hostname or via environment variable
#     HOST.
#
#  INPUTS
#     { do_debug_puts 1}   - unused parameter
#     {source_dir_path ""} - used source dir path
#                            (if empty it is $ts_config(source_dir))
#
#  RESULT
#     local hostname ("unknown" if host is not resolvable)
#*******************************************************************************
proc gethostname { { do_debug_puts 1} {source_dir_path ""} } {
   global env local_hostname_cache ts_config
   if { $local_hostname_cache != "" } {
      return $local_hostname_cache
   }

   if { $source_dir_path != "" } {
      set my_source_dir $source_dir_path
   } else {
      if {$ts_config(source_dir) != "none"} {
         set my_source_dir $ts_config(source_dir)
      } else {
         set my_source_dir ""
      }
   }

   set my_product_root $ts_config(product_root)

   # we have a arch script and gethostname
   if { $my_product_root != "" || $my_source_dir != "" } {
      if {[file exists "$my_product_root/util/arch"]} {
         set arch_script "$my_product_root/util/arch"
      } else {
         set arch_script "$my_source_dir/dist/util/arch"
      }
      set prg_exit_state [ catch { exec $arch_script} result ]
      if { $prg_exit_state != 0 } {
         set arch "unknown"
      } else {
         set arch [parse_arch_output $result]
      }
      if { $my_product_root != "" } {
         set prg_exit_state [ catch { exec "$my_product_root/utilbin/$arch/gethostname" "-name"} result ]
         if { $prg_exit_state == 0 } {
            set result [split $result "."]
            set newname [lindex $result 0]
            if { $newname == "" } {
               ts_log_warning "proc gethostname - gethostname binary returned empty hostname"
               ts_log_warning "trying local hostname call ..."
            } else {
               # only use cache for GE gethostname binary!
               set local_hostname_cache $newname
               return $newname
            }
         } else {
            ts_log_finest "proc gethostname - gethostname error or binary not found"
            ts_log_finest "error: $result"
            ts_log_finest "error: $prg_exit_state"
            ts_log_finest "trying local hostname call ..."
         }
      }
   }

   #
   # here we try to find out the hostname without having gethostname binary ...
   #
   # we don't want to have this value in the hostname cache!!!
   set local_hostname_cache ""
   set prg_exit_state [ catch { exec "hostname" } result ]
   if { $prg_exit_state == 0 } {
      set result [split $result "."]
      set newname [lindex $result 0]
      ts_log_finest "got hostname: \"$newname\""
      return $newname
   } else {
      ts_log_finest "local hostname error or binary not found"
      ts_log_finest "error: $result"
      ts_log_finest "error: $prg_exit_state"
      ts_log_finest "trying local HOST environment variable ..."
      if { [ info exists env(HOST) ] } {
         set result [split $env(HOST) "."]
         set newname [lindex $result 0]
         if { [ string length $newname ] > 0 } {
            ts_log_finest "got hostname_ \"$newname\""
            return $newname
         } 
      }
   }
   return "unknown"
}



#                                                             max. column:     |
#****** control_procedures/resolve_arch() ******
# 
#  NAME
#     resolve_arch -- resolve architecture of host
#
#  SYNOPSIS
#     resolve_arch { {node "none"} {use_source_arch 0}} 
#
#  FUNCTION
#     Resolves the architecture of a given host.
#     Tries to call $SGE_ROOT/util/arch - if this script doesn't exist yet,
#     calls <source_dir>/dist/util/arch.
#
#     If the parameter use_source_arch is set, the function will always
#     call <source_dir>/dist/util/arch.
#     This is for example required when building new binaries:
#     The installed arch script might return a different architecture than
#     the source arch script, for example when a cluster was installed from
#     Cluster Scheduler (Grid Engine) packages <= 6.2u5, where we deliver lx-24-* packages also for
#     Linux kernel 2.6 machines (lx26-*).
#
#  INPUTS
#     {node "none"}     - return architecture of this host.
#                         If "none", resolve architecture of [gethostname].
#     {use_source_arch} - use <source_dir>/dist/util/arch script.
#
#  RESULT
#     Architecture string (e.g. "sol-amd64"), "unknown" in case of errors.
#
#  SEE ALSO
#     control_procedures/resolve_arch_clear_cache()
#*******************************
proc resolve_arch {{node "none"} {use_source_arch 0} {source_dir_value ""}} {
   global CHECK_USER
   global arch_cache
   global ts_config

   set host [node_get_host $node]
   set nr [get_current_cluster_config_nr]
   if {[info exists arch_cache($nr,$host,$use_source_arch,$source_dir_value)]} {
      return $arch_cache($nr,$host,$use_source_arch,$source_dir_value)
   }

   if { [ info exists CHECK_USER ] == 0 } {
      ts_log_severe "user not set, aborting"
      return "unknown"
   }
  
   set util_arch_dir ""
   set store_in_cache 1
   if {[file exists "$ts_config(product_root)/util/arch"] && ! $use_source_arch} {
      # use distinst arch script (product_root)
      set util_arch_dir $ts_config(product_root)
   } else {
      if {$source_dir_value == ""} {
         if {[info exists ts_config(source_dir)] == 0} {
            ts_log_severe "source directory not set, aborting"
            return "unknown"
         }
         if {$ts_config(source_dir) == "none"} {
            ts_log_severe "source directory is set to \"none\" - cannot get arch"
            return "unknown"
         }
         set util_arch_dir $ts_config(source_dir)/dist
      } else {
         set util_arch_dir $source_dir_value/dist
      }

      # use source arch script (use_source_arch != 0 || product root/util/arch not found)
      if {$use_source_arch == 0} {
         set store_in_cache 0
      }
   }

   set arch_script "$util_arch_dir/util/arch"

   if {$host == "none"} {
      set host [gethostname]
   }
   # try to retrieve architecture
   set result [start_remote_prog $host $CHECK_USER $arch_script "" prg_exit_state 60 0 "" "" 1 0 0]
   if {$prg_exit_state != 0} {
      # 2nd try after waiting for availability of arch_script on specified host:
      if {[file exists $arch_script]} {
         ts_log_fine "result of first arch script call on host \"$host\": $result"
         ts_log_fine "file exists on local host, wait for availability on remote host \"$host\" ..."
         wait_for_remote_file $host $CHECK_USER $arch_script
         set result [start_remote_prog $host $CHECK_USER $arch_script "" prg_exit_state 60 0 "" "" 1 0 0]
         ts_log_fine "result of second arch script call on host \"$host\": $result"
      }
      if {$prg_exit_state != 0} {
         return "unknown"
      }
   }
   set result [parse_arch_output $result]
   if { $result != "unknown" && $store_in_cache == 1 } {
      set arch_cache($nr,$host,$use_source_arch,$source_dir_value) [lindex $result 0]
      return $arch_cache($nr,$host,$use_source_arch,$source_dir_value)
   } else { 
      return [lindex $result 0]
   }
}


proc parse_arch_output { arch_output } {
   set result [string trim $arch_output]
   set result2 [split $result "\n"]
   if { [ llength $result2 ] > 1 } {
      ts_log_fine "util/arch script returns more than 1 line output ..."
      foreach elem $result2  {
         ts_log_fine "\"$elem\""
         if { [string first " " $elem ] < 0  } {
            set result $elem
            ts_log_fine "using \"$result\" as architecture"
            break
         }
      }
   }
   if { [ llength $result2 ] < 1 } {
       ts_log_fine "util/arch script returns no value ..."
       return "unknown"
   }
   if { [string first ":" $result] >= 0 } {
      ts_log_fine "architecture or file /dist/util/arch\" not found"
      return "unknown"
   }
   set result [lindex $result 0]
 
   if { [ string compare $result "" ] == 0 } {
      ts_log_fine "architecture or file /dist/util/arch\" not found"
      return "unknown"
   } 
 
   return $result
}



#****** control_procedures/resolve_arch_clear_cache() **************************
#  NAME
#     resolve_arch_clear_cache() -- clear cache of resolve_arch()
#
#  SYNOPSIS
#     resolve_arch_clear_cache { } 
#
#  FUNCTION
#     The function resolve_arch caches its results.
#     resolve_arch_clear_cache will clear this cache to force reresolving
#     the architecture strings.
#
#     This is for example done after compiling and installing binaries.
#     In this case the newly installed arch script might return other 
#     architecture names than the previously installed one.
#
#  SEE ALSO
#     control_procedures/resolve_arch()
#*******************************************************************************
proc resolve_arch_clear_cache {} {
   global arch_cache

   ts_log_fine "clearing architecture cache used by resolve_arch"
   if {[info exists arch_cache]} {
      unset arch_cache
   }
}

#                                                             max. column:     |
#****** control_procedures/resolve_build_arch() ******
# 
#  NAME
#     resolve_build_arch -- ??? 
#
#  SYNOPSIS
#     resolve_build_arch { host } 
#
#  FUNCTION
#     ??? 
#
#  INPUTS
#     host - ??? 
#
#  RESULT
#     ??? 
#
#  EXAMPLE
#     ??? 
#
#  NOTES
#     ??? 
#
#  BUGS
#     ??? 
#
#  SEE ALSO
#     ???/???
#*******************************
proc resolve_build_arch { host } {
  global build_arch_cache
  global CHECK_USER

  get_current_cluster_config_array ts_config

  if {$ts_config(source_dir) == "none"} {
     ts_log_severe "source directory is set to \"none\" - cannot run resolve build arch"
     return ""
  }

  set nr [get_current_cluster_config_nr]

  if { [info exists build_arch_cache($nr,$host) ] } {
     return $build_arch_cache($nr,$host)
  }

  set result [start_remote_prog $host $CHECK_USER "scripts/compilearch" "-b" prg_exit_state 60 0 $ts_config(source_dir) "" 1 0]
 
  set result [split $result "\n"]
  set result [join $result ""]
  set result [split $result "\r"]
  set result [join $result ""]

  if {$prg_exit_state != 0} {
     ts_log_severe "architecture not found in $ts_config(source_dir): $result"
     return ""
  }
  set build_arch_cache($nr,$host) $result
  ts_log_finer "build arch is \"$result\""

  return $build_arch_cache($nr,$host)
}

#                                                             max. column:     |
#****** control_procedures/resolve_lib_path_name() ******
# 
#  NAME
#     resolve_lib_path_name -- Returns the name of the shared library path name
#                              environment variable
#
#  SYNOPSIS
#     resolve_lib_path_name { host  {use_source_arch 0}} 
#
#  FUNCTION
#     This function resolves the name of the shared library path name
#     environment variable on the target host.  For example, is the target
#     host is a Solaris machine, this function will return "LD_LIBRARY_PATH".
#
#  INPUTS
#     host - the name of the target host
#     use_source_arch - forces the arch script from the source directory to be
#                       used.  Defaults to 0 (false).
#
#  RESULT
#     the name of the shared library path name environment variable
#
#*******************************
proc resolve_lib_path_name { host {use_source_arch 0}} {
   global libpath_cache
   global CHECK_USER
   get_current_cluster_config_array ts_config

   if { [info exists libpath_cache($host) ] } {
      return $libpath_cache($host)
   }

   # if $SGE_ROOT/util/arch is available, use this one,
   # otherwise use the one from the distribution
   if {[file exists "$ts_config(product_root)/util/arch"] && ! $use_source_arch} {
      set arch_script "$ts_config(product_root)/util/arch"
   } else {
      if {$ts_config(source_dir) == "none"} {
         ts_log_severe "source directory is set to \"none\" - cannot run source arch script"
         return "unknown"
      }
      set arch_script "$ts_config(source_dir)/dist/util/arch"
   }

   # try to retrieve architecture
   set result [start_remote_prog $host $CHECK_USER $arch_script "-lib" prg_exit_state 60 0 "" "" 1 0 0]
 
   if {$prg_exit_state != 0} {
      return "unknown"
   }

   set result [lindex $result 0]  ;# remove CR
   set libpath_cache($host) $result
   ts_log_fine "shared lib path name variable is \"$result\""

   return $libpath_cache($host)
}

#****** control_procedures/resolve_build_arch_installed_libs() *****************
#  NAME
#     resolve_build_arch_installed_libs() -- get build arch for libraries
#
#  SYNOPSIS
#     resolve_build_arch_installed_libs { host {raise_error 1} } 
#
#  FUNCTION
#     Some architectures are using different lib path. This procedure returns
#     the host specific library search path.
#
#  INPUTS
#     host            - name of host for which the lib path sould be returned
#     {raise_error 1} - report errors
#
#  RESULT
#     build arch string
#
#*******************************************************************************
global resolve_build_arch_installed_libs_cache
if {[info exists resolve_build_arch_installed_libs_cache]} {
   unset resolve_build_arch_installed_libs_cache
}
proc resolve_build_arch_installed_libs {host {raise_error 1}} {
   global CHECK_USER
   global resolve_build_arch_installed_libs_cache

   # if entry already exists in cache return value
   if {[info exists resolve_build_arch_installed_libs_cache($host)]} {
      ts_log_finer "returning cached build arch value \"$resolve_build_arch_installed_libs_cache($host)\" for host \"$host\""
      return $resolve_build_arch_installed_libs_cache($host)
   }

   get_current_cluster_config_array ts_config

   if {$ts_config(source_dir) == "none"} {
      ts_log_severe "source directory is set to \"none\" - cannot resolve build arch"
      return ""
   }

   set build_arch [resolve_build_arch $host]

   

   # we need special handling for some architectures
   switch $build_arch {
      "LINUXAMD64_26" {
         set arch [resolve_arch $host]
         if {$arch == "lx24-amd64" && [is_remote_path $host $CHECK_USER $ts_config(source_dir)/LINUXAMD64_24]} {
            ts_log_info "We are on lx26-amd64 platform (build platform LINUXAMD64_26) with lx24-amd64 binaries installed.\nUsing lx24-amd64 (build platform LINUXAMD64_24) test binaries" $raise_error
            set build_arch "LINUXAMD64_24"
         }
      }
      "LINUX86_26" {
         set arch [resolve_arch $host]
         if {$arch == "lx24-x86" && [is_remote_path $host $CHECK_USER $ts_config(source_dir)/LINUX86_24]} {
            ts_log_info "We are on lx26-x86 platform (build platform LINUX86_26) with lx24-x86 binaries installed.\nUsing lx24-x86 (build platform LINUX86_24) test binaries" $raise_error
            set build_arch "LINUX86_24"
         }
      }
   }

   if { [is_remote_path $host $CHECK_USER $ts_config(source_dir)/$build_arch] == 0 } {
      ts_log_severe "can't find build directory: $ts_config(source_dir)/$build_arch" $raise_error
   } 

   # update cache
   set resolve_build_arch_installed_libs_cache($host) $build_arch
   return $build_arch
}

#                                                             max. column:     |
#****** control_procedures/resolve_host() ******
# 
#  NAME
#     resolve_host -- ??? 
#
#  SYNOPSIS
#     resolve_host { name { long 0 } } 
#
#  FUNCTION
#     ??? 
#
#  INPUTS
#     name       - ??? 
#     { long 0 } - ??? 
#
#  RESULT
#     ??? 
#
#  EXAMPLE
#     ??? 
#
#  NOTES
#     ??? 
#
#  BUGS
#     ??? 
#
#  SEE ALSO
#     ???/???
#*******************************
proc resolve_host {name {long 0}} {
   global resolve_host_cache CHECK_USER

   get_current_cluster_config_array ts_config

   set name [string trim $name]
   # we cannot resolve hostgroups.
   if {[string range $name 0 0] == "@"} {
      ts_log_fine "hostgroups ($name) cannot be resolved"
      return $name
   }

   if {$long != 0} {
      if {[info exists resolve_host_cache($name,long)]} {
         return $resolve_host_cache($name,long)
      }
   } else {
      if {[info exists resolve_host_cache($name,short)]} {
         return $resolve_host_cache($name,short)
      }
   }

   set result [start_sge_utilbin "gethostbyname" "-aname $name" $ts_config(master_host) $CHECK_USER]

   if {$prg_exit_state != 0} {
      ts_log_fine "proc resolve_host - gethostbyname failed: \n$result"
      return $name
   }

   set newname [string trim $result]
   if {$long == 0} {
      set split_name [split $newname "."]
      set newname [lindex $split_name 0]
   }

   # cache result
   if {$long != 0} {
      set resolve_host_cache($name,long) $newname
      ts_log_finer "long resolve_host: \"$name\" resolved to \"$newname\""
   } else {
      set resolve_host_cache($name,short) $newname
      ts_log_finer "short resolve_host: \"$name\" resolved to \"$newname\""
   }

   return $newname
}

###
# @brief resolve a list of hosts
#
# @param hosts list of hosts
# @param long 0 for short name, 1 for long name
# @return list of resolved hosts
##
proc resolve_host_list {hosts {long 0}} {
   set new_hosts {}
   foreach host $hosts {
      lappend new_hosts [resolve_host $host $long]
   }
   return $new_hosts
}

#****** control_procedures/resolve_queue() *************************************
#  NAME
#     resolve_queue() -- resolve queue instance name
#
#  SYNOPSIS
#     resolve_queue { queue } 
#
#  FUNCTION
#     This function resolves the hostname of the queue instance and returns 
#     the corresponding name
#
#  INPUTS
#     queue - queue name e.g. "queue1@testhost"
#
#*******************************************************************************
proc resolve_queue {queue {raise_queue_too_long_error 1}} { 
   set at_sign [string first "@" $queue]
   set new_queue_name $queue
   if { $at_sign >= 0 } {
      incr at_sign 1
      set host_name  [string range $queue $at_sign end]
      incr at_sign -2
      set queue_name [string range $queue 0 $at_sign]
      ts_log_finest "queue name:          \"$queue_name\""
      ts_log_finest "host name:           \"$host_name\""
      set resolved_name [resolve_host $host_name 1]
      if { $resolved_name != "unknown" } {
         set resolved_host_name $resolved_name
         ts_log_finest "resolved host name:  \"$resolved_host_name\""
         set new_queue_name "$queue_name@$resolved_host_name"
      } else {
         ts_log_fine "can't resolve host \"$host_name\""
      }
   }
   ts_log_finest "queue \"$queue\" resolved to \"$new_queue_name\""

   if {[string length $new_queue_name] > 30 } {
      ts_log_config "The length of the queue name \"$new_queue_name\" will exceed qstat queue name output" $raise_queue_too_long_error
   }

   return $new_queue_name 
}

proc get_schedd_pid {} {
   global ts_config

   set qmaster_spool_dir [ get_qmaster_spool_dir ]

   set pid_file "$qmaster_spool_dir/schedd/schedd.pid"

   return [get_pid_from_file $ts_config(master_host) $pid_file]
}

proc parse_cpu_time {s_cpu} {
   # TODO: handling, if cpu > 1 day
   set split_s_cpu [split $s_cpu "."]
   if {[llength $split_s_cpu] > 1} {
      set fractional [lindex $split_s_cpu 1]
   } else {
      set fractional 0
   }
   set s_cpu [lindex $split_s_cpu 0]
   set l_cpu [split $s_cpu ":"]
   set cpu 0

   while {[llength $l_cpu] > 0} {
      scan [lindex $l_cpu 0] "%02d" part
      
      switch [llength $l_cpu] {
         1 {
            incr cpu $part
         }
         2 {
            incr cpu [expr $part * 60]
         }
         3 {
            incr cpu [expr $part * 3600]
         }
         default {
            ts_log_severe "cannot parse cpu time $s_cpu"
         }
      }

      set l_cpu [lreplace $l_cpu 0 0]
   }

   return "$cpu.$fractional"
}

#****** control_procedures/operational_lock() **********************************
#  NAME
#     operational_lock() -- sychronizes an operation using file-based locks
#
#  SYNOPSIS
#     operational_lock { operation_name lock_location }
#
#  FUNCTION
#     This function uses a file lock in the lock_location directory to prevent
#     multiple instances of a test suite operation from occuring simultaneously.
#     No two test suite instances maybe be within a proetcted section of code
#     on the same machine with the same operation_name and the same
#     lock_location.  If the lock_location is not specified, it defaults to
#     /tmp.
#     This algorithm is based on "ls -crt | head -1" returning the oldest lock
#     file.  In this way, clients receive the lock on a first come, first served
#     basis.
#
#  INPUTS
#     operation_name - the name of the lock
#     host           - the name of the host to lock. Defaults to [gethostname]
#     lock_location  - where to store the locks.  Defaults to /tmp.
#
#  RESULTS
#     -1   - error
#      0   - success
#
#  SEE ALSO
#     control_procedures/operational_lock()
#
#*******************************************************************************
proc operational_lock {operation_name {host ""} {lock_location "/tmp"}} {
   global CHECK_USER

   set local_host [gethostname]
   if {$host == ""} {
      set host $local_host
   }

   set pid [pid]
   set lock "$lock_location/lock.$operation_name.$pid"
   set all_locks "$lock_location/lock.$operation_name.*"

   set output [start_remote_prog $local_host $CHECK_USER "touch" $lock result]

   if {$result != 0} {
      ts_log_severe "Could not update lock: $output"
      return -1
   }

   # ls -crt behaves approximately the same on all platforms.
   set output [start_remote_prog $local_host $CHECK_USER "ls" "-crt $all_locks | head -1" result]

   if {$result != 0} {
      ts_log_severe "Could not read locks: $output"
      return -1
   }

   while {[string trim $output] != $lock} {
      ts_log_fine "Waiting for lock"
      after 1000

      set output [start_remote_prog $local_host $CHECK_USER "ls" "-crt $all_locks | head -1" result]

      if {$result != 0} {
         ts_log_severe "Could not read locks: $output"
         return -1
      }
   }

   return 0
}

#****** control_procedures/operational_unlock() ********************************
#  NAME
#     operational_unlock() -- sychronizes an operation using file-based locks
#
#  SYNOPSIS
#     operational_unlock { operation_name lock_location }
#
#  FUNCTION
#     This function removes the file lock in the lock_location directory
#     allowing other processes access to the specified operation.  If the
#     lock_location is not specified, it defaults to /tmp.
#
#  INPUTS
#     operation_name - the name of the lock
#     host           - the name of the host to lock. Defaults to [gethostname]
#     lock_location  - where to store the locks.  Defaults to /tmp.
#
#  RESULTS
#     -1   - error
#      0   - success
#
#  SEE ALSO
#     control_procedures/operational_lock()
#
#*******************************************************************************
proc operational_unlock {operation_name {host ""} {lock_location "/tmp"}} {
   global CHECK_USER

   set local_host [gethostname]
   if {$host == ""} {
      set host $local_host
   }

   set pid [pid]
   set lock "$lock_location/lock.$operation_name.$pid"

   set output [start_remote_prog $local_host $CHECK_USER "rm" $lock result]

   if {$result != 0} {
      ts_log_severe "Could not release lock: $output"
      return -1
   }

   return 0
}


#****** control_procedures/scale_timeout() *************************************
#  NAME
#     scale_timeout() -- scale timeout values
#
#  SYNOPSIS
#     scale_timeout { timeout {does_computation 1} {does_spooling 1} 
#     {process_invocations 1} } 
#
#  FUNCTION
#     Scales a given timeout value depending on setup.
#     The given timeout is increased, when
#        o we use classic spooling
#        o we spool on a NFS filesystem
#        o we run with code coverage
#
#  INPUTS
#     timeout                 - base timeout
#     {does_computation 1}    - is the tested
#     {does_spooling 1}       - ??? 
#     {process_invocations 1} - ??? 
#
#  RESULT
#     ??? 
#
#  EXAMPLE
#     ??? 
#
#  NOTES
#     ??? 
#
#  BUGS
#     ??? 
#
#  SEE ALSO
#     ???/???
#*******************************************************************************
proc scale_timeout {timeout {does_computation 1} {does_spooling 1} {process_invocations 1}} {
   get_current_cluster_config_array ts_config
   global CHECK_VALGRIND

   set ret $timeout

   # respect spooling influence
   if {$does_spooling} {
      # classic spooling is slower than BDB, assume 100% slower spooling
      if {$ts_config(spooling_method) == "classic"} {
         set ret [expr $ret * 2.0]
         set spool_dir [get_qmaster_spool_dir]
      } else {
         set spool_dir [get_bdb_spooldir]
      }

      # spooling on NFS mounted filesystem, assume 50% slower spooling
      set fstype [fs_config_get_filesystem_type $spool_dir $ts_config(master_host) 0]
      if {[string match "nfs*" $fstype]} {
         set ret [expr $ret * 1.5]
      }
   }

   # respect code coverage influence
   # we assume that the process will run slightly slower
   if {[coverage_enabled]} {
      # computation will be slower - add 10% overhead
      if {$does_computation} {
         set ret [expr $ret * 1.10]
      }

      # coverage profiles are written per process invocation
      # add 1 second overhead per process invocation
      set ret [expr $ret + $process_invocations * 1]
   }

   if {$CHECK_VALGRIND == "master"} {
      # valgrind sometimes makes sge_qmaster really slow
      set ret [expr $ret * 2.0]
   }

   return [format "%.0f" [expr ceil($ret)]]
}


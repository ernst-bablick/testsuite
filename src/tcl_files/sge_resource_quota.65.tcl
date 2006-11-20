#!/vol2/TCL_TK/glinux/bin/expect
# expect script 
# test SGE/SGEEE System
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
##########################################################################
#___INFO__MARK_END__

#****** sge_resource_quota.65/get_rqs() ******************************************
#  NAME
#     get_rqs() -- get resource quota set config
#
#  SYNOPSIS
#     get_rqs { output_var {rqs ""} {on_host ""} {as_user ""} {raise_error 1} 
#     } 
#
#  FUNCTION
#     Execute 'qconf -srqs (name)' to get one or more resource quota sets
#
#  INPUTS
#     output_var      - result
#     {rqs ""}       - resource quota set name(s)
#     {on_host ""}    - execute qconf on this host, default is master host
#     {as_user ""}    - execute qconf as this user, default is $CHECK_USER
#     {raise_error 1} - do add_proc_error in case of errors
#
#  RESULT
#     0 on success, an error code on error
#*******************************************************************************
proc get_rqs {output_var {rqs ""} {on_host ""} {as_user ""} {raise_error 1}} {
   global ts_config
   upvar $output_var out

   # clear output variable
   if {[info exists out]} {
      unset out
   }

   set ret 0
   set result [start_sge_bin "qconf" "-srqs $rqs" $on_host $as_user]

   # parse output or raise error
   if {$prg_exit_state == 0} {
      parse_rqs_record result out
   } else {
      set ret [get_rqs_error $result $rqs $raise_error]
   }

   return $ret
}

#****** sge_resource_quota.65/get_rqs_list() *************************************
#  NAME
#     get_rqs_list() -- get a list of all configured resource quota sets
#
#  SYNOPSIS
#     get_rqs_list { {output_var result} {on_host ""} {as_user ""} 
#     {raise_error 1} } 
#
#  FUNCTION
#     Executes 'qconf -srqsl' to get a list of all resource quota sets
#
#  INPUTS
#     {output_var result} - result output
#     {on_host ""}        - execute qconf on this host, default is master host
#     {as_user ""}        - execute qconf as this user, default is $CHECK_USER
#     {raise_error 1}       - do add_proc_error in case of errors
#
#  RESULT
#     0 on success, the error or qconf on failure
#*******************************************************************************
proc get_rqs_list {{output_var result} {on_host ""} {as_user ""} {raise_error 1}} {
   upvar $output_var out

   return [get_qconf_list "get_rqs_list" "-srqsl" out $on_host $as_user $raise_error]
}

#****** sge_resource_quota.65/get_rqs_error() ************************************
#  NAME
#     get_rqs_error() -- error handling for get_rqs
#
#  SYNOPSIS
#     get_rqs_error { result rqs raise_error } 
#
#  FUNCTION
#     Does the error handling for get_rqs.
#     Translate possible error massages of qconf -srqs, builds the datastructure
#     required for the handle_sge_error function call.
#
#  INPUTS
#     result      - qconf output
#     rqs        - name for which qconf -srqs has been called
#     raise_error - do add_proc_error in case of errors
#
#  RESULT
#     Returncode for the get_rqs function:
#
#*******************************************************************************
proc get_rqs_error {result rqs raise_error} {

   # recognize certain error messages and return special return code
   set messages(index) "-1"
   set messages(-1) [translate_macro MSG_NOLIRSFOUND]

   # now evaluate return code and raise errors
   set ret [handle_sge_errors "get_rqs" "qconf -srqs $rqs" $result messages $raise_error]

   return $ret
}

#****** sge_resource_quota.65/add_rqs() ******************************************
#  NAME
#     add_rqs() -- Add resource quota set(s)
#
#  SYNOPSIS
#     add_rqs { change_array {fast_add 1} {on_host ""} {as_user ""} 
#     {raise_error 1} } 
#
#  FUNCTION
#     Calls qconf -arqs/-Arqs to add a new resource quota set
#
#  INPUTS
#     change_array    - array that contains new resource quota set(s)
#     {fast_add 1}    - add fast with -Arqs or slow from CLI with -arqs
#     {on_host ""}    - execute qconf on this host, default is master host
#     {as_user ""}    - execute qconf as this user, default is $CHECK_USER
#     {raise_error 1} - do add_proc_error in case of errors
#
#  RESULT
#     0 on success, an error code on error.
#*******************************************************************************
proc add_rqs {change_array {fast_add 1} {on_host ""} {as_user ""} {raise_error 1}} {
   global ts_config CHECK_OUTPUT CHECK_USER
   global env CHECK_ARCH
   global CHECK_CORE_MASTER

   upvar $change_array chgar

   set rqs_names ""
   set old_name ""

   foreach elem [lsort [array names chgar]] {
      set help [split $elem ","]
      set name [lindex $help 0]
      if { $old_name != $name } {
         set old_name "$name"
         if { $rqs_names == "" } {
            set rqs_names "$name"
         } else {
            set rqs_names "$rqs_names,$name"
         }
      }
   }

   # Add rqs from file?
   if { $fast_add } {
      set tmpfile [dump_rqs_array_to_tmpfile chgar]
      set result [start_sge_bin "qconf" "-Arqs $tmpfile" $on_host $as_user ]

      set messages(index) "-1 0"
      set messages(-1) [translate_macro MSG_SGETEXT_ALREADYEXISTS_SS "resource quota set" "*"]
      set messages(0)  [translate_macro MSG_SGETEXT_ADDEDTOLIST_SSSS $CHECK_USER "*" "*" "resource quota set"]

      set result [handle_sge_errors "add_rqs" "qconf -Arqs $tmpfile" $result messages $raise_error]
   } else {
   # Use vi
      # localize messages
      # JG: TODO: object name is taken from c_gdi object structure - not I18Ned!!
      set ADDED [translate $ts_config(master_host) 1 0 0 [sge_macro MSG_SGETEXT_ADDEDTOLIST_SSSS] $CHECK_USER "*" "*" "resource quota set"]
      set ALREADY_EXISTS [ translate $ts_config(master_host) 1 0 0 [sge_macro MSG_SGETEXT_ALREADYEXISTS_SS] "resource quota set" "*"]

      set vi_commands [build_rqs_vi_array chgar]

      set result [handle_vi_edit "$ts_config(product_root)/bin/$CHECK_ARCH/qconf" "-arqs $rqs_names" $vi_commands $ADDED $ALREADY_EXISTS]
      if { $result != 0 } {
         add_proc_error "add_rqs" -1 "could not add resource quota set (error: $result)" $raise_error
      }
   }
  return $result
}

#****** sge_resource_quota.65/mod_rqs() ******************************************
#  NAME
#     mod_rqs() -- Modify resource quota set(s)
#
#  SYNOPSIS
#     mod_rqs { change_array {name ""} {fast_add 1} {on_host ""} {as_user ""} 
#     {raise_error 1} } 
#
#  FUNCTION
#     Calls qconf -Mrqs $file to modify resource quota sets, or -mrqs
#
#  INPUTS
#     change_array    - array that contains resource quota set(s) to be modified
#     {name ""}       - names of the resource quota sets that should be modified
#     {fast_add 1}    - add fast with -Mrqs or slow from CLI with -mrqs
#     {on_host ""}    - execute qconf on this host, default is master host
#     {as_user ""}    - execute qconf as this user, default is $CHECK_USER
#     {raise_error 1} - do add_proc_error in case of errors
#
#  RESULT
#     0 on success, an error code on error.
#*******************************************************************************
proc mod_rqs {change_array {name ""} {fast_add 1} {on_host ""} {as_user ""} {raise_error 1}} {
   global ts_config CHECK_OUTPUT CHECK_USER
   global env CHECK_ARCH
   global CHECK_CORE_MASTER
   
   upvar $change_array chgar

   # Modify rqs from file?
   if { $fast_add } {
      set tmpfile [dump_rqs_array_to_tmpfile chgar]
      set result [start_sge_bin "qconf" "-Mrqs $tmpfile $name" $on_host $as_user]

      set messages(index) "-1 0 1"
      set messages(-1) [translate_macro MSG_FILE_NOTCHANGED]
      set messages(0) [translate_macro MSG_SGETEXT_MODIFIEDINLIST_SSSS $CHECK_USER "*" "*" "resource quota set"]
      set messages(1) [translate_macro MSG_SGETEXT_ADDEDTOLIST_SSSS $CHECK_USER "*" "*" "resource quota set"]

      set ret [handle_sge_errors "mod_rqs" "qconf -Mrqs $tmpfile $name" $result messages $raise_error]
   } else {
      # Use vi
      set MODIFIED [translate $ts_config(master_host) 1 0 0 [sge_macro MSG_SGETEXT_MODIFIEDINLIST_SSSS] $CHECK_USER "*" "*" "resource quota set"]
      set ADDED [translate $ts_config(master_host) 1 0 0 [sge_macro MSG_SGETEXT_ADDEDTOLIST_SSSS] $CHECK_USER "*" "*" "resource quota set"]
      set NOT_MODIFIED [translate_macro MSG_FILE_NOTCHANGED ]

      set vi_commands [build_rqs_vi_array chgar]

      if { $name != "" } {
         set ret [handle_vi_edit "$ts_config(product_root)/bin/$CHECK_ARCH/qconf" "-mrqs $name" $vi_commands $MODIFIED $ADDED $NOT_MODIFIED]
      } else {
         set ret [handle_vi_edit "$ts_config(product_root)/bin/$CHECK_ARCH/qconf" "-mrqs $name" $vi_commands $ADDED $MODIFIED $NOT_MODIFIED]
      }
      if { $ret != 0 } {
         add_proc_error "mod_rqs" -1 "could not modify resource quota set (error: $result)" $raise_error
      }
   }

   return $ret
}

#****** sge_resource_quota.65/del_rqs() ******************************************
#  NAME
#     del_rqs() -- Deletes resource quota set(s)
#
#  SYNOPSIS
#     del_rqs { rqs_name {on_host ""} {as_user ""} {raise_error 1} } 
#
#  FUNCTION
#     Deletes the given resource quota sets
#
#  INPUTS
#     rqs_name       - name of the resource quota set
#     {on_host ""}    - execute qconf on this host, default is master host
#     {as_user ""}    - execute qconf as this user, default is $CHECK_USER
#     {raise_error 1} - do add_proc_error in case of errors
#
#  RESULT
#     0 on success, an error code on error.
#*******************************************************************************
proc del_rqs {rqs_name {on_host ""} {as_user ""} {raise_error 1}} {
   global ts_config CHECK_USER
   
   set messages(index) "0"
   set messages(0) [translate_macro MSG_SGETEXT_REMOVEDFROMLIST_SSSS $CHECK_USER "*" $rqs_name "*"]

   set output [start_sge_bin "qconf" "-drqs $rqs_name" $on_host $as_user ]

   set ret [handle_sge_errors "del_rqs" "qconf -drqs $rqs_name" $output messages $raise_error]
   return $ret
}

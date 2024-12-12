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
#  Portions of this software are Copyright (c) 2011 Univa Corporation
#
#  Portions of this software are Copyright (c) 2023-2024 HPC-Gridware GmbH
#
##########################################################################
#___INFO__MARK_END__

#****** compile/compile_check_compile_hosts() **********************************
#  NAME
#     compile_check_compile_hosts() -- check for suited compile host
#
#  SYNOPSIS
#     compile_check_compile_hosts { host_list } 
#
#  FUNCTION
#     Goes through the given host list and for every host checks,
#     if a compile host for the architecture of the host is defined
#     in the testsuite host configuration.
#
#  INPUTS
#     host_list - list of hosts to check
#
#  RESULT
#     0 - OK, compile hosts for all given hosts exist
#    -1 - at least for one host, no compile host is configured
#*******************************************************************************
proc compile_check_compile_hosts {host_list} {
   global ts_host_config ts_config


   # remember already resolved compile archs
   set compile_archs {}

   # check each host in host_list
   foreach host $host_list {
      if {![host_conf_is_supported_host $host]} {
         ts_log_severe "host $host is not contained in testsuite host configuration or not supported host!"
      } else {
         # host's architecture
         set arch [host_conf_get_arch $host]

         # do we already have a compile host for this arch?
         # if not, search it.
         if {[lsearch $compile_archs $arch] < 0} {
            if {[compile_search_compile_host $arch] != "none"} {
               lappend compile_archs $arch
            } else {
               return -1
            }
         }
      }
   }

   return 0
}


#****** compile/compile_host_list() ********************************************
#  NAME
#     compile_host_list() -- build compile host list
#
#  SYNOPSIS
#     compile_host_list { } 
#
#  FUNCTION
#     Builds a list of compile host for all the architectures that are 
#     required to install the configured test cluster.
#
#     Takes into account the
#     - master host
#     - execd hosts
#     - shadowd hosts
#     - submit only hosts
#     - berkeley db rpc server host
#     - additional config configurations
#
#  RESULT
#     list of compile hosts
#     in case of errors, an empty list is returned
#
#  SEE ALSO
#     compile/compile_search_compile_host()
#*******************************************************************************
proc compile_host_list {{binaries_only 0}} {
   global ts_host_config
   global ts_config
  
   set other_hosts {}
   if {$ts_config(submit_only_hosts) != "none"} {
      set other_hosts [concat $other_hosts $ts_config(submit_only_hosts)]
   }
   if {$ts_config(admin_only_hosts) != "none"} {
      set other_hosts [concat $other_hosts $ts_config(admin_only_hosts)]
   }
   if {$ts_config(non_cluster_hosts) != "none"} {
      set other_hosts [concat $other_hosts $ts_config(non_cluster_hosts)]
   }
   
   # build host list according to cluster requirements
   set host_list [concat $ts_config(master_host) $ts_config(execd_hosts) \
                         $ts_config(shadowd_hosts) $other_hosts \
                         [checktree_get_required_hosts]]

   # for additional configurations, we might have different architectures
   if {$ts_config(additional_config) != "none"} {
      foreach filename $ts_config(additional_config) {
         set cl_type [get_additional_cluster_type $filename add_config]

         if { $cl_type == "" } {
            continue
         }

         # check whether it is cell cluster or independed cluster
         if { $cl_type == "cell" } {
            ts_log_fine "adding hosts from additional cluster configuration file"
            ts_log_fine "$filename"
            ts_log_fine "to compile host list. This cluster will be installed as GE Cell!"
            foreach param "master_host execd_hosts shadowd_hosts submit_only_hosts admin_only_hosts non_cluster_hosts" {
               if {$add_config($param) != "none"} {
                  append host_list " $add_config($param)"
                  ts_log_fine "appending $param host \"$add_config($param)\""
               }
            }
         }
      }
   }

   # For SGE 6.0 we build the drmaa.jar on the java build host.
   # Beginning with SGE 6.1 we build java code on all platforms.
   # Add the java build host to the host list.
   set jc_host [host_conf_get_java_compile_host]
   if {$jc_host != ""} {
      lappend host_list $jc_host
   }

   # remove duplicates from host_list
   set host_list [compile_unify_host_list $host_list]

   # find the compile hosts by architecture
   foreach host $host_list {
      set arch [host_conf_get_arch $host]
      if {$arch == ""} {
         ts_log_severe "Cannot determine the architecture of host $host"
         return {}
      }
      if {![info exists compile_host($arch)]} {
         set c_host [compile_search_compile_host $arch]
         if {$c_host == "none"} {
            ts_log_severe "Cannot determine a compile host for architecture $arch" 
            return {}
         } else {
            set compile_host($arch) $c_host
            lappend compile_host(list) $c_host
         }
      }
   }

   # The java compile host may not duplicate the build host for it's architecture, 
   # it must be also a c build host,
   # so it must be contained in the build host list.
   # With OCS/GCS >= 9.0.0 we separated core product and extensions like the drmaa-java,
   # so there is no longer then need to build java and c++ code on the same host.
   if {[is_version_in_range "" "9.0.0"] && $jc_host != ""} {
      set jc_arch [host_conf_get_arch $jc_host]

      if {$compile_host($jc_arch) != $jc_host} {
         ts_log_severe "the java compile host ($jc_host) has architecture $jc_arch\nbut compile host for architecture $jc_arch is $compile_host($jc_arch).\nJava and C compile must be done on the same host"
         return {}
      }
   }

   # Beginning with Cluster Scheduler 9.0.0 we build documentation (man pages and manuals) from markdown
   # Add the doc compile host to the host list
   # It can be one of the c/c++ compile hosts but can also be a separate host
   if {!$binaries_only} {
      set doc_host [host_conf_get_doc_compile_host]
      if {$doc_host != "" && [lsearch -exact $compile_host(list) $doc_host] < 0} {
         lappend compile_host(list) $doc_host
      }
   }

   return [lsort -dictionary $compile_host(list)]
}


#****** compile/get_compile_options_string() ***********************************
#  NAME
#     get_compile_options_string() -- return current compile option string
#
#  SYNOPSIS
#     get_compile_options_string { } 
#
#  FUNCTION
#     This function returns a string containing the current set aimk compile
#     options
#
#  RESULT
#     string containing compile options
#*******************************************************************************
proc get_compile_options_string { } {
   global ts_config

   set options $ts_config(compile_options)

   if {$options == "none"} {
      set options ""
   }

   if {$options != ""} {
      ts_log_fine "compile options are: \"$options\""
   }

   return $options
}

#****** compile/compile_unify_host_list() **************************************
#  NAME
#     compile_unify_host_list() -- remove duplicates and "none" from list
#
#  SYNOPSIS
#     compile_unify_host_list { host_list } 
#
#  FUNCTION
#     Takes a hostlist and removes all duplicate entries as well as 
#     "none" entries from it.
#     The resulting list is sorted.
#
#  INPUTS
#     host_list - list containing duplicates
#
#  RESULT
#     unified and sorted list
#*******************************************************************************
proc compile_unify_host_list {host_list} {
   set new_host_list {}

   # go over input host list
   foreach host $host_list {
      # filter out "none" entries (coming from empty lists)
      if {$host != "none"} {
         # if we don't have this host in output list, append it
         if {[lsearch $new_host_list $host] < 0} {
            lappend new_host_list $host
         }
      }
   }

   # return sorted list
   return [lsort -dictionary $new_host_list]
}

#****** compile/compile_search_compile_host() **********************************
#  NAME
#     compile_search_compile_host() -- search compile host by architecture
#
#  SYNOPSIS
#     compile_search_compile_host { arch } 
#
#  FUNCTION
#     Search the testsuite host configuration for a compile host for a 
#     certain architecture.
#
#  INPUTS
#     arch - required architecture
#
#  RESULT
#     name of the compile host
#     "none", if no compile host for the given architecture is defined
#*******************************************************************************
proc compile_search_compile_host {arch} {
   global ts_host_config
   
   if {$arch != "none"} {
      foreach host $ts_host_config(hostlist) {
         if {[host_conf_get_arch $host] == $arch && [host_conf_is_compile_host $host]} {
            return $host
         }
      }

      # no compile host found for this arch
      ts_log_warning "no compile host found for architecture $arch"
   }
   return "none"
}


proc compile_rebuild_arch_cache { compile_hosts {al "arch_list"} } {
   upvar $al arch_list
   if { [info exists arch_list] } {
      unset arch_list
   }
   resolve_arch_clear_cache
   set arch_list {}
   set compiled_mail_architectures ""
   foreach elem $compile_hosts {
      set output [resolve_arch $elem 1]
      lappend arch_list $output 
      append compiled_mail_architectures "\n$elem ($output)"
   }
   ts_log_fine "architectures: $arch_list"
   return $compiled_mail_architectures
}

#****** compile/compile_depend() **************************************************
#  NAME
#    compile_depend() -- ???
#
#  SYNOPSIS
#    compile_depend { } 
#
#  FUNCTION
#     Executes scripts/zero-depend, aimk --only-depend and aimk depend
#     on a preferred compile host
#
#  INPUTS
#    compile_hosts -- list of compile hosts
#    a_html_body   -- html body buffer for reporting
#
#  RESULT
#     0  -  on success
#     -1 -  on failure
#
#  EXAMPLE
#
#  NOTES
#
#  BUGS
#
#  SEE ALSO
#*******************************************************************************
proc compile_depend { compile_hosts a_report do_clean } {
   global ts_host_config ts_config
   global CHECK_USER
   
   upvar $a_report report
 
   ts_log_fine "building dependencies ..."
 
   # we prefer building the dependencies on a sol-sparc64 host
   # to avoid automounter issues like having a heading /tmp_mnt in paths
   set depend_host_name [lindex $compile_hosts 0] 
   foreach help_host $compile_hosts {
      set help_arch [host_conf_get_arch $help_host]
      if { [ string compare $help_arch "solaris64"] == 0 || 
           [ string compare $help_arch "sol-sparc64"] == 0 } {
         ts_log_fine "using host $help_host to create dependencies"
         set depend_host_name $help_host
      }
   }

   set task_nr [report_create_task report "zerodepend" $depend_host_name]

   if {$ts_config(source_dir) == "none"} {
      report_task_add_message report $task_nr "source directory is set to \"none\" - cannot depend"
      report_finish_task report $task_nr -1
      return -1
   }
   
   # clean dependency files (zerodepend)
   
   report_task_add_message report $task_nr "------------------------------------------"
   report_task_add_message report $task_nr "-> starting scripts/zerodepend on host $depend_host_name ..."
   set output [start_remote_prog $depend_host_name $CHECK_USER "scripts/zerodepend" "" prg_exit_state 60 0 $ts_config(source_dir) "" 1 0]
   report_task_add_message report $task_nr "------------------------------------------"
   report_task_add_message report $task_nr "return state: $prg_exit_state"
   report_task_add_message report $task_nr "------------------------------------------"
   report_task_add_message report $task_nr "output:\n$output"
   report_task_add_message report $task_nr "------------------------------------------"
   
   report_finish_task report $task_nr $prg_exit_state
   if { $prg_exit_state != 0 } {
      report_add_message report "------------------------------------------"
      report_add_message report "Error: scripts/zerodepend (exit code $prg_exit_state)"
      report_add_message report "------------------------------------------"
      return -1
   }
   
   # clean dependency files (zerodepend) for Univa extensions

   if {$ts_config(ext_source_dir) != "none"} {
   
      set task_nr [report_create_task report "zerodepend_uge_extensions" $depend_host_name]

      report_task_add_message report $task_nr "------------------------------------------"
      report_task_add_message report $task_nr "-> starting scripts/zerodepend on host $depend_host_name for Univa extensions..."
      set output [start_remote_prog $depend_host_name $CHECK_USER "scripts/zerodepend" "" prg_exit_state 60 0 $ts_config(ext_source_dir) "" 1 0]
      report_task_add_message report $task_nr "------------------------------------------"
      report_task_add_message report $task_nr "return state: $prg_exit_state"
      report_task_add_message report $task_nr "------------------------------------------"
      report_task_add_message report $task_nr "output:\n$output"
      report_task_add_message report $task_nr "------------------------------------------"
      
      report_finish_task report $task_nr $prg_exit_state
      if { $prg_exit_state != 0 } {
         report_add_message report "------------------------------------------"
         report_add_message report "Error: scripts/zerodepend for Univa extensions (exit code $prg_exit_state)"
         report_add_message report "------------------------------------------"
         return -1
      }
   }

   if {$do_clean} {
      set task_nr [report_create_task report "only_depend_clean" $depend_host_name]
      # clean the depencency building program
      set my_compile_options [get_compile_options_string]
      set aimk_options "$my_compile_options -only-depend clean"
      report_task_add_message report $task_nr "-> starting aimk $aimk_options on host $depend_host_name ..."

      set output [start_remote_prog $depend_host_name $CHECK_USER "./aimk" $aimk_options prg_exit_state 60 0 $ts_config(source_dir) "" 1 0]
      report_task_add_message report $task_nr "------------------------------------------"
      report_task_add_message report $task_nr "return state: $prg_exit_state"
      report_task_add_message report $task_nr "------------------------------------------"
      report_task_add_message report $task_nr "output:\n$output"
      report_task_add_message report $task_nr "------------------------------------------"
      report_finish_task report $task_nr $prg_exit_state
      if {$prg_exit_state != 0} {
         report_add_message report "------------------------------------------"
         report_add_message report "Error: aimk $aimk_options failed (exit code $prg_exit_state)"
         report_add_message report "------------------------------------------"
         return -1
      }
   }


   set task_nr [report_create_task report "only_depend" $depend_host_name]
   # build the depencency building program
   set my_compile_options [get_compile_options_string]
   set aimk_options "$my_compile_options -only-depend"
   report_task_add_message report $task_nr "-> starting aimk $aimk_options on host $depend_host_name ..."

   set output [start_remote_prog $depend_host_name $CHECK_USER "./aimk" $aimk_options prg_exit_state 60 0 $ts_config(source_dir) "" 1 0 ]
   report_task_add_message report $task_nr "------------------------------------------"
   report_task_add_message report $task_nr "return state: $prg_exit_state"
   report_task_add_message report $task_nr "------------------------------------------"
   report_task_add_message report $task_nr "output:\n$output"
   report_task_add_message report $task_nr "------------------------------------------"
   report_finish_task report $task_nr $prg_exit_state
   if {$prg_exit_state != 0} {
      report_add_message report "------------------------------------------"
      report_add_message report "Error: aimk $aimk_options failed (exit code $prg_exit_state)"
      report_add_message report "------------------------------------------"
      return -1
   }

   # build the dependencies
   set task_nr [report_create_task report "depend" $depend_host_name]
   report_task_add_message report $task_nr "------------------------------------------"
   report_task_add_message report $task_nr "-> starting aimk $my_compile_options depend on host $depend_host_name ..."
   set output [start_remote_prog $depend_host_name $CHECK_USER "./aimk" "$my_compile_options depend" prg_exit_state 60 0 $ts_config(source_dir) "" 1 0]
   report_task_add_message report $task_nr "------------------------------------------"
   report_task_add_message report $task_nr "return state: $prg_exit_state"
   report_task_add_message report $task_nr "------------------------------------------"
   report_task_add_message report $task_nr "output:\n$output"
   report_task_add_message report $task_nr "------------------------------------------"

   report_finish_task report $task_nr $prg_exit_state
   if { $prg_exit_state != 0 } {
      report_add_message report "------------------------------------------"
      report_add_message report "Error: aimk depend failed (exit code $prg_exit_state)"
      report_add_message report "------------------------------------------"
      return -1
   }

   return 0
}

#****** compile/wait_for_NFS_after_compile_clean() *****************************
#  NAME
#     wait_for_NFS_after_compile_clean() -- check compile arch dir after clean
#
#  SYNOPSIS
#     wait_for_NFS_after_compile_clean { host_list a_report } 
#
#  FUNCTION
#     This function checks if the compile arch directory is empty after a 
#     aimk clean. It also checks that the arch is empty on all used specified 
#     hosts.
#
#  INPUTS
#     host_list - list of compile hosts
#     a_report  - a report array
#
#  RESULT
#     1 on success, 0 on error
#*******************************************************************************
proc wait_for_NFS_after_compile_clean { host_list a_report } {
   global CHECK_USER
   upvar $a_report report
   get_current_cluster_config_array ts_config

   if {$ts_config(source_dir) == "none"} {
      ts_log_config "source directory is set to \"none\" - cannot check build dirs"
      return 0
   }

   ts_log_fine "verify compile_clean call ($host_list)..."

   set result 1
   foreach host $host_list {
      set task_nr [report_create_task report "verify compile clean" $host]
      set build_dir_name [resolve_build_arch $host]
      set wait_path  "$ts_config(source_dir)/$build_dir_name"
 
      ts_log_fine "wait path: $ts_config(source_dir)/$build_dir_name"
      set my_timeout [timestamp]
      incr my_timeout 65
      set was_error 1
      while { [timestamp] < $my_timeout } {
         analyze_directory_structure $host $CHECK_USER $wait_path "" files ""
         report_task_add_message report $task_nr "waiting for empty directory: $wait_path"
         if {[llength $files] == 0} {
            set was_error 0
            report_task_add_message report $task_nr "directory $wait_path contains no files! Good!"
            break
         }
         after 1000
         ts_log_washing_machine
      }
      if {$was_error == 1} {
         set error_text "Timout while waiting for build dir \"$wait_path\" containing no files.\n"
         foreach filen $files {
            append error_text "   found file: $filen\n"
         }
         ts_log_severe $error_text
         set result 0
         report_task_add_message report $task_nr $error_text
      }
      report_finish_task report $task_nr $was_error
   }
   return $result
}

#****** compile/compile_source() ***********************************************
#  NAME
#     compile_source() -- compile source code
#
#  SYNOPSIS
#     compile_source { { do_only_hooks 0} } 
#
#  FUNCTION
#     compile all source code
#
#  INPUTS
#     { do_only_hooks 0} - if set, only compile and distinst hooks
#     { compile_only 0}  - do not remove SGE_ROOT, just replace the binaries
#
#  SEE ALSO
#     ???/???
#*******************************************************************************
proc compile_source { { do_only_hooks 0} {compile_only 0} } {
   global ts_host_config ts_config
   global CHECK_PRODUCT_TYPE
   global CHECK_COMPILE_TOOL
   global CHECK_HTML_DIRECTORY
   global CHECK_DEFAULTS_FILE check_name
   global CHECK_JOB_OUTPUT_DIR
   global CHECK_PROTOCOL_DIR CHECK_USER
   global CMAKE_COMPILE_INSTALL_SEPARATELY

   # settings for mail
   set check_name "compile_source"
   set CHECK_CUR_PROC_NAME $check_name
   array set report {}
   report_create "Compiling source" report
   report_write_html report

   if {$ts_config(source_dir) == "none"} {
      report_add_message report "source directory is set to \"none\" - cannot compile"
      report_finish report -1
      return -1
   }

   set error_count 0

   # for additional configurations, we might want to start remote operation
   # (for independed clusters)
   if { $do_only_hooks == 0 } {
      if {$ts_config(additional_config) != "none"} {
         foreach filename $ts_config(additional_config) {
            set cl_type [get_additional_cluster_type $filename add_config]
            if { $cl_type == "" } {
               continue
            }
            if { $cl_type == "independent" } {
               ts_log_fine "Found $cl_type additional cluster, starting remote compile ..."
               set task_nr [report_create_task report "build_additional_${cl_type}_cluster" $add_config(master_host) "$add_config(master_host)/index.html"]
               report_task_add_message report $task_nr "------------------------------------------"
               report_task_add_message report $task_nr "-> starting remote build of additional configuration $filename ..."
               report_task_add_message report $task_nr "-> see report in $CHECK_HTML_DIRECTORY/$add_config(master_host)/index.html"
               set error [operate_add_cluster $filename "compile" 3600]
               report_finish_task report $task_nr $error
               if { $error != 0 } {
                  incr error_count 1
               }
            }
         }
         if { $error_count != 0 } {
            report_add_message report "skip compilation because of errors!\n"
            report_finish report -1
            return -1
         }
      }
   }

   # if we configured to install precompiled packages - stop
   if { $ts_config(package_directory) != "none" &&
       ($ts_config(package_type)      == "tar" || $ts_config(package_type) == "zip") } {
      report_add_message report "will not compile but use precompiled packages\n"
      report_add_message report "set package_directory to \"none\" or set package_type to \"create_tar\"\n"
      report_add_message report "if compilation (and package creation) should be done"
      report_finish report -1
      return -1
   }

   # compile hosts required for master, exec, shadow, submit_only hosts
   set compile_hosts [compile_host_list $compile_only]

   # add compile hosts for additional compile archs
   if {$ts_config(add_compile_archs) != "none"} {
      foreach arch $ts_config(add_compile_archs) {
         lappend compile_hosts [compile_search_compile_host $arch]
      }
   }

   # eliminate duplicates
   set compile_hosts [compile_unify_host_list $compile_hosts]

   # check source directory
   if {[string compare $ts_config(source_dir) "unknown"] == 0 || [string compare $ts_config(source_dir) ""] == 0} {
      report_add_message report "source directory unknown - check defaults file"
      report_finish report -1
      return -1
   }

   # check compile hosts
   if {[string compare $compile_hosts "unknown"] == 0 || [string compare $compile_hosts ""] == 0} {
      report_add_message report "host list to compile for unknown - check defaults file"
      report_finish report -1
      return -1
   }

   # do we have a unknown host ?
   if {[string match "*unknown*" $compile_hosts]} {
      report_add_message report "compile host list contains unknown host: $compile_hosts"
      report_finish report -1
   }

   # If we still have no compile hosts - report error
   if {[llength $compile_hosts] == 0} {
      report_add_message report "host list to compile has zero length"
      report_finish report -1
      return -1
   }

   # figure out the compile archs
   set compile_arch_list {}
   foreach chost $compile_hosts {
      ts_log_fine "\n-> checking architecture for host $chost ..."
      set output [resolve_build_arch $chost]
      if {$output == ""} {
         report_add_message report "error resolving build architecture for host $chost"
         report_finish report -1
         return -1
      }
      lappend compile_arch_list $output
   }

   # check if compile hosts are unique per arch
   # this can be the case in the cmake build where c/c++ build host can have the same architecture
   # as an additional doc build host - this is handled in the cmake build
   # do the check for uniqueness only for the aimk build (for old SGE/UGE versions)
   if {$CHECK_COMPILE_TOOL == "aimk"} {
      foreach elem $compile_arch_list {
         set found 0
         set hostarch ""
         foreach host $compile_arch_list {
            if {[string compare $host $elem] == 0}  {
               incr found 1
               set hostarch $host
            }
         }
         if {$found > 1} {
            report_add_message report "two compile hosts have the same architecture $elem -> error"
            report_finish report -1
            return -1
         }
      }
   }

   # create protocol directory
   if {[file isdirectory "$CHECK_PROTOCOL_DIR"] != 1} {
      set catch_return [catch {file mkdir "$CHECK_PROTOCOL_DIR"}]
      if {$catch_return != 0} {
        report_add_message report "could not create directory \"$CHECK_PROTOCOL_DIR\""
        report_finish report -1
        return -1
      }
   }

   # shutdown possibly running system (and additional config clusters)
   shutdown_core_system $do_only_hooks 1
   valgrind_analyse_copy_files

   if {$CHECK_COMPILE_TOOL == "aimk"} {
      incr error_count [compile_source_aimk $do_only_hooks $compile_hosts report $compile_only]
   } else {
      incr error_count [compile_source_cmake $do_only_hooks $compile_hosts report $compile_only]
   }

   if {$error_count == 0} {
      # new all registered compile_hooks of the checktree
      set res [exec_compile_hooks $compile_hosts report]
      if {$res < 0} {
         ts_log_fine "exec_compile_hooks returned fatal error\n"
         incr error_count 1
      } elseif {$res > 0} {
         ts_log_fine "$res compile hooks failed\n"
         incr error_count 1
      } else {
         ts_log_fine "All compile hooks successfully executed\n"
      }
   }

   # install
   if {$error_count == 0} {
      # We need to evaluate the architectures to install.
      # We might have cached architecture strings from an old
      # $SGE_ROOT/util/arch. Clear the cache and resolve
      # architecture names using dist/util/arch script.
      set compiled_mail_architectures [compile_rebuild_arch_cache $compile_hosts arch_list]

      # new all registered compile_hooks of the checktree
      set res [exec_install_binaries_hooks $arch_list report]
      if {$res < 0} {
         report_add_message report "exec_install_binaries_hooks returned fatal error\n"
         incr error_count 1
      } elseif {$res > 0} {
         report_add_message report "$res install_binaries hooks failed\n"
         incr error_count 1
      } else {
         report_add_message report "All install_binaries hooks successfully executed\n"
      }
   } else {
      report_add_message report "Skip installation due to previous error\n"
   }

   if {$error_count > 0} {
      report_add_message report "Error occured during compilation or pre-installation of binaries"
      report_finish report -1
      return -1
   }

   report_add_message report "Successfully compiled and pre-installed following architectures:"
   report_add_message report "${compiled_mail_architectures}\n"

   if {!$compile_only} {
      report_add_message report "init_core_system check will install the $CHECK_PRODUCT_TYPE execd at:"
      foreach elem $ts_config(execd_hosts) {
         set host_arch [ resolve_arch $elem ]
         report_add_message report "$elem ($host_arch)"
      }

      # if required, build distribution
      if {$ts_config(package_type) == "create_tar"} {
         if {![build_distribution $arch_list report]} {
            report_add_message report "building distribution packages failed"
            report_finish report -1
            return -1
         }
      }
   }

   # finish the HTML report
   report_finish report 0

   if {$compile_only} {
      startup_core_system 0 1
   }

   return 0
}

# @todo compile_only 1 is not implemented
proc compile_source_aimk {do_only_hooks compile_hosts report_var {compile_only 0}} {
   global ts_host_config ts_config
   global check_do_clean_compile

   upvar $report_var report
   
   set error_count 0

   if {$check_do_clean_compile} {
      set do_aimk_depend_clean 1
   } else {
      set do_aimk_depend_clean 0
   }

   # do clean (if not already done)
   if {$error_count == 0 && $check_do_clean_compile == 1} {
      if {$do_only_hooks == 0} {
         if {[compile_with_aimk $compile_hosts report "compile_clean" "clean"] != 0} {
            incr error_count 1
         }

         if {$error_count == 0} {
            if {![wait_for_NFS_after_compile_clean $compile_hosts report]} {
               incr error_count 1
            }
         }
      } else {
         ts_log_fine "Skip aimk compile, I am on do_only_hooks mode"
      }

      # execute all registered compile_hooks of the checktree
      set res [exec_compile_clean_hooks $compile_hosts report]
      if {$res < 0} {
         report_add_message report "exec_compile_clean_hooks returned fatal error"
         incr error_count 1
      } elseif {$res > 0} {
         report_add_message report "$res compile_clean hooks failed\n"
         incr error_count 1
      } else {
         report_add_message report "All compile_clean hooks successfully executed\n"
      }
   }

   if {$error_count > 0} {
      ts_log_fine "Skip compile due to previous errors"
   } else {
      if {$do_only_hooks == 0} {
         if {[compile_depend $compile_hosts report $do_aimk_depend_clean] != 0} {
            incr error_count 1
         }
      } else {
         ts_log_fine "Skip aimk compile, I am on do_only_hooks mode"
      }

      if {$error_count == 0} {
         # start build process
         if {$do_only_hooks == 0} {
            # build the man pages on the java build host
            set man_build_host [get_preferred_build_host $compile_hosts]
            if {[lsearch $compile_hosts $man_build_host] >= 0} {
               if {[compile_with_aimk $man_build_host report "man_pages" "-man -catman -univaman"] != 0} {
                  incr error_count 1
               }
            }

            set java_doc_build_host [host_conf_get_java_compile_host]
            # skip this step if there is no java build host configured or if
            # "-no-java" is specified in the aimk options
            set options $ts_config(compile_options)
            if {[lsearch $compile_hosts $java_doc_build_host] >= 0 &&
                [string first "-no-java" $options] == -1} {
               if {[compile_with_aimk $java_doc_build_host report "java_doc" "-javadoc"] != 0} {
                  incr error_count 1
               }
            }
            if {[compile_with_aimk $compile_hosts report "compile"] != 0} {
               incr error_count 1
            }
            if {$error_count == 0} {
               # we have to install the GE system here because other compile
               # hooks might need it
               report_add_message report "Installing GE binaries ...."
               report_write_html report
               # We need to evaluate the architectures to install.
               # We might have cached architecture strings from an old
               # $SGE_ROOT/util/arch. Clear the cache and resolve
               # architecture names using dist/util/arch script.
               set compiled_mail_architectures [compile_rebuild_arch_cache $compile_hosts arch_list]

               if {[install_binaries $arch_list report] != 0} {
                  report_add_message report "install_binaries failed\n"
                  incr error_count 1
               }
            }
         } else {
            ts_log_fine "Skip aimk compile, I am on do_only_hooks mode"
         }
         report_write_html report
      }
   }

   # we installed new binaries and scripts, version information might have changed
   clear_version_info

   return $error_count
}

proc compile_source_cmake_get_build_dir {host} {
   global ts_host_config ts_config

   # fetch a local build directory
   set build_dir [get_local_spool_dir $host "build" 0 1]
   ts_log_fine "build directory on host $host is $build_dir"

   return $build_dir
}

proc compile_source_cmake_clean {compile_hosts report_var} {
   global CHECK_USER
   global check_do_3rdparty_build

   upvar $report_var report

   set error_count 0

   # clear the build dir on every host
   foreach host $compile_hosts {
      set task_nr [report_create_task report "compile clean" $host]

      set build_dir [compile_source_cmake_get_build_dir $host]
      if {$build_dir == ""} {
         incr error_count ;# ts_log_severe has already been done
         report_task_add_message report $task_nr "no local build directory on host $host"
         break
      }
    
      # delete the existing build directory
      if {[remote_file_isdirectory $host $build_dir]} {
         if {$check_do_3rdparty_build} {
            # to trigger the 3rdparty build remove the build directory
            if {[remote_delete_directory $host $build_dir] != 0} {
               incr error_count
               report_task_add_message report $task_nr "cannot delete $build_dir on host $host"
               break
            } else {
               report_task_add_message report $task_nr "deleted $build_dir on host $host"
            }
         } else {
            # to do a clean build just remove *the contents of* the build directory
            set cmd "rm"
            set args "-rf *"
            set output [start_remote_prog $host $CHECK_USER $cmd $args prg_exit_state 60 0 $build_dir]
            if {$prg_exit_state != 0} {
               incr error_count
               report_task_add_message report $task_nr "cannot delete $build_dir contents on host $host"
               break
            } else {
               report_task_add_message report $task_nr "deleted contents of $build_dir on host $host"
            }
         }
      }
   }

   report_write_html report

   return $error_count
}

proc compile_source_cmake_make_build_dir {compile_hosts report_var {build_3rdparty_hosts_var ""}} {
   upvar $report_var report

   # these are the hosts where 3rdparty code needs to be built
   if {$build_3rdparty_hosts_var != ""} {
      upvar $build_3rdparty_hosts_var build_3rdparty_hosts
   }

   set error_count 0

   # clear the build dir on every host
   foreach host $compile_hosts {
      set task_nr [report_create_task report "create build directory" $host]

      set build_dir [compile_source_cmake_get_build_dir $host]
      if {$build_dir == ""} {
         incr error_count ;# ts_log_severe has already been done
         report_task_add_message report $task_nr "no local build directory on host $host"
         break
      }
    
      # create a new build directory
      if {![remote_file_isdirectory $host $build_dir]} {
         lappend build_3rdparty_hosts $host
         set output [remote_file_mkdir $host $build_dir 0 "root" "777" prg_exit_state]
         if {$prg_exit_state == 0} {
            report_task_add_message report $task_nr "Successfully created build directory $build_dir on host $host"
         } else {
            incr error_count
            report_task_add_message report $task_nr "Creating build directory $build_dir on host $host failed:\n$output"
         }
      } else {
         report_task_add_message report $task_nr "Build directory $build_dir on host $host already exists"
      }

      if {$error_count == 0} {
         report_finish_task report $task_nr 0
      } else {
         report_finish_task report $task_nr 1
      }
   }

   report_write_html report

   return $error_count
}

proc compile_source_cmake_execute {task_name compile_hosts options_var report_var} {
   global CHECK_USER

   upvar $options_var options
   upvar $report_var report

   report_add_message report "starting $task_name"

   set error_count 0

   # table output while running command
   set table_row 2
   set status_rows {}
   set status_cols {status file}

   # start command on all hosts
   set spawn_list {}
   foreach host $compile_hosts {
      ts_log_fine "starting $task_name on host $host"
      set cmd $options($host,cmd)
      set args $options($host,args)
      set dir $options($host,dir)

      # need to set JAVA_HOME
      # if no Java (JDK, also having include/jni.h) is available then disable building with JNI
      unset -nocomplain myenv
      set java_home [host_conf_get_java $host 8 1 1]
      if {$java_home != ""} {
         set myenv(JAVA_HOME) $java_home
      } elseif {$options($host,cmd) == "cmake"} {
         append args " -DWITH_JNI=OFF"
      }
      set open_spawn [open_remote_spawn_process $host $CHECK_USER $cmd $args 0 $dir myenv 0]
      set spawn_id [lindex $open_spawn 1]

      set host_array($spawn_id,host) $host
      set host_array($spawn_id,task_nr) [report_create_task report $task_name $host]
      set host_array($spawn_id,open_spawn) $open_spawn
      lappend spawn_list $spawn_id
      report_task_add_message report $host_array($spawn_id,task_nr) "in $dir started $cmd $args"

      # initialize fancy compile output
      lappend status_rows $host
      set status_array(file,$host) "unknown"
      set status_array(status,$host) "running"
      set status_array(compile_args,$host) $args
   }

   # wait for all commands to finish
   log_user 0
   set do_stop 0
   set done 0
   set status_time [clock seconds]
   set status_updated 0
   set timeout 600
   expect_user {
      -i $spawn_list full_buffer {
         set spawn_id $expect_out(spawn_id)
         set host $host_array($spawn_id,host)
         ts_log_severe "full_buffer on host $host while building, step $task_name"
         set do_stop 1
         incr error_count
      }
      -i $spawn_list timeout {
         ts_log_severe "timeout on host $host while building, step $task_name"
         set do_stop 1
         incr error_count
      }
      -i $spawn_list eof {
         set spawn_id $expect_out(spawn_id)
         set host $host_array($spawn_id,host)
         ts_log_fine "eof on host $host while building, step $task_name"

         report_task_add_message report $host_array($spawn_id,task_nr) "got eof for host \"$host\""
         set host_array($spawn_id,bad_compile) 1

         close_spawn_process $host_array($spawn_id,open_spawn)
         set host_array($spawn_id,open_spawn) "--"
         set index [lsearch -exact $spawn_list $spawn_id]
         set spawn_list [lreplace $spawn_list $index $index]

         set status_array(file,$host)   "-"
         set status_array(status,$host) "eof"
         set status_updated 1
      }
      -i $spawn_list "*\n" {
         set spawn_id $expect_out(spawn_id)
         set host $host_array($spawn_id,host)
         #ts_log_fine "got data from host $host while building, step $task_name"
         set lines [split [string trim $expect_out(0,string)] "\n"]
         foreach line $lines {
            set line [string trim $line]
            if {$line != ""} {
               #ts_log_fine $line
               set now [clock milliseconds]
               set secs [expr $now / 1000]
               set millis [expr $now % 1000]
               set report_line "[clock format $secs -format "%H:%M:%S"].$millis:$line"
               report_task_add_message report $host_array($spawn_id,task_nr) $report_line

               # analyse line
               switch -glob $line {
                  "\\\[*%\\\]*" -
                  "-- *" {
                     #ts_log_fine "==> status line $line"
                     set status_array(file,$host) $line
                     set status_array(status,$host) "running"
                     set status_updated 1
                  }
                  "_exit_status_:(*)*" {
                     set exit_status [get_string_value_between "(" ")" $line]
                     report_task_add_message report $host_array($spawn_id,task_nr) "exited with exit status $exit_status"
                     if {$exit_status == 0} {
                        set status_array(status,$host) "done"
                     } else {
                        set status_array(status,$host) "failed"
                        incr error_count
                     }
                     set status_array(file,$host) "-"
                     set status_updated 1
                     set host_array($spawn_id,exit_status) $exit_status
                  }
                  "script done. (_END_OF_FILE_)" {
                     # we are done with this connection
                     ts_log_fine "done with spawn_id $spawn_id on host $host"
                     close_spawn_process $host_array($spawn_id,open_spawn)
                     set host_array($spawn_id,open_spawn) "--"
                     set index [lsearch -exact $spawn_list $spawn_id]
                     set spawn_list [lreplace $spawn_list $index $index]
                     if {[llength $spawn_list] == 0} {
                        ts_log_fine "all commands finished"
                        set done 1
                     }
                     if {![info exists host_array($spawn_id,exit_status)] || $host_array($spawn_id,exit_status) != 0} {
                        report_finish_task report $host_array($spawn_id,task_nr) 1
                        incr error_count
                     } else {
                        report_finish_task report $host_array($spawn_id,task_nr) 0
                     }
                  }
                  default {
                     ts_log_finer $line
                  }
               }
            }
         }

         # update screen
         set now [clock seconds]
         if {$status_updated && ($status_time < $now || $done)} {
            set status_time $now
            set status_updated 0

            set status_output [print_xy_array $status_cols $status_rows status_array status_max_column_len status_max_index_len]
            
            # show
            clear_screen
            ts_log_frame INFO "================================================================================"
            foreach host $compile_hosts {
               ts_log_info "task \'$task_name\' on \'$host\':  \'$options($host,cmd) $options($host,args)\'" 0 "" 1 0 0
            }
            ts_log_info "$status_output" 0 "" 1 0 0
            ts_log_frame INFO "================================================================================"
         }

         if {!$do_stop && !$done} {
            # continue expect loop
            exp_continue
         }
      }
   }

   # close the remaining connections which did not yet get a eof
   foreach spawn_id $spawn_list {
      close_spawn_process $host_array($spawn_id,open_spawn)
      if {![info exists host_array($spawn_id,exit_status)] || $host_array($spawn_id,exit_status) != 0} {
         report_finish_task report $host_array($spawn_id,task_nr) 1
         incr error_count
      } else {
         report_finish_task report $host_array($spawn_id,task_nr) 0
      }
   }

   if {$error_count > 0} {
      report_add_message report "$task_name failed"
   } else {
      report_add_message report "$task_name succeeded"
   }

   return $error_count
}


proc compile_source_cmake {do_only_hooks compile_hosts report_var {compile_only 0}} {
   global ts_host_config ts_config
   global CHECK_USER CHECK_CMAKE_BUILD_TYPE
   global check_do_clean_compile check_do_3rdparty_build
   global CMAKE_BUILD_ID
   global CMAKE_COMPILE_INSTALL_SEPARATELY

   upvar $report_var report

   # @todo what about do_only_hooks?
   # @todo check for tools and their versions? cmake, bison, flex, ...

   # we do a 3rdparty build only when build directories had to be created
   # - on first build
   # - after clean
   # @todo better check if tools are available and only build them if not (and this could be done in cmake itself)
   set build_3rdparty 0
   
   set error_count 0

   # if clean build requested: simply delete the build directories
   if {$check_do_clean_compile || $check_do_3rdparty_build} {
      incr error_count [compile_source_cmake_clean $compile_hosts report]
   }

   # create build directories if they do not yet exist
   # where they got created we need to build the 3rdparty tools
   set build_3rdparty_hosts {}
   if {$error_count == 0} {
      incr error_count [compile_source_cmake_make_build_dir $compile_hosts report build_3rdparty_hosts]
   }
   
   # no need to call cmake when compiling with 1t. we will not change any configuration
   # while updates to the CMakeLists.txt files will be taken into account
   if {$error_count == 0 && !$compile_only} {
      # call cmake on every host
      # we use the "preferred" host to install common files
      # if there is no "preferred" host, use the first compile host as "preferred" host
      unset -nocomplain options
      set preferred_host [get_preferred_build_host $compile_hosts]
      if {[lsearch -exact $compile_hosts $preferred_host] < 0} {
         set preferred_host [lindex $compile_hosts 0]
      }

      foreach host $compile_hosts {
         set options($host,cmd) "cmake"
         set source_dir [file dirname $ts_config(source_dir)]
         set args "-S $source_dir"
         append args " -DCMAKE_INSTALL_PREFIX=$ts_config(product_root)"

         # use gmake instead of make on sol-amd64
         if {[resolve_arch $host] == "sol-amd64"} {
            append args " -DCMAKE_MAKE_PROGRAM=gmake"
         }

         # enable extensions if extensions are available
         if {$ts_config(ext_source_dir) != "none"} {
            append args " -DPROJECT_EXTENSIONS=$ts_config(ext_source_dir)"
            append args " -DPROJECT_FEATURES=\"gcs-extensions\""
         }

         # handle common files only on the preferred host
         if {$host == $preferred_host} {
            append args " -DINSTALL_SGE_COMMON=ON"
         } else {
            append args " -DINSTALL_SGE_COMMON=OFF"
         }

         # make binaries and tests on compile hosts
         if {[host_conf_is_compile_host $host]} {
            append args " -DINSTALL_SGE_BIN=ON"
            append args " -DINSTALL_SGE_TEST=ON"
         } else {
            append args " -DINSTALL_SGE_BIN=OFF"
            append args " -DINSTALL_SGE_TEST=OFF"
         }

         # compile docs only on the doc compile host and not when just replacing binaries (menu 1t)
         if {[host_conf_is_doc_compile_host $host] && !$compile_only} {
            append args " -DINSTALL_SGE_DOC=ON"
         } else {
            append args " -DINSTALL_SGE_DOC=OFF"
         }

         # add compile options from the cinfiguration
         set compile_options [get_compile_options_string]
         if {$compile_options != "none"} {
            append args " $compile_options"
         }

         # add build type and build id
         append args " -DCMAKE_BUILD_TYPE=$CHECK_CMAKE_BUILD_TYPE -DCMAKE_BUILD_ID=$CMAKE_BUILD_ID -Wno-dev"
         set options($host,args) $args
         set options($host,dir) [compile_source_cmake_get_build_dir $host]
      }

      incr error_count [compile_source_cmake_execute "cmake" $compile_hosts options report]
   }

   if {$error_count == 0} {
      # build 3rdparty tools only on hosts where required
      if {[llength $build_3rdparty_hosts] > 0} {
         unset -nocomplain options
         foreach host $build_3rdparty_hosts {
	    if {[resolve_arch $host] == "sol-amd64"} {
               set options($host,cmd) "gmake"
	    } else {
               set options($host,cmd) "make"
            }
            set num_procs [node_get_processors $host]
            if {$num_procs > 1} {
               set options($host,args) "-j $num_procs VERBOSE=1 3rdparty"
            } else {
               set options($host,args) "VERBOSE=1 3rdparty"

            }
            set options($host,dir) [compile_source_cmake_get_build_dir $host]
         }
         incr error_count [compile_source_cmake_execute "3rdparty" $build_3rdparty_hosts options report]
      }
   }

   if {$CMAKE_COMPILE_INSTALL_SEPARATELY == 1 && $error_count == 0} {
      # call make on every host
      unset -nocomplain options
      foreach host $compile_hosts {
	 if {[resolve_arch $host] == "sol-amd64"} {
            set options($host,cmd) "gmake"
	 } else {
            set options($host,cmd) "make"
         }
         set num_procs [node_get_processors $host]
         if {$num_procs > 1} {
            set options($host,args) "-j $num_procs VERBOSE=1"
         } else {
            set options($host,args) "VERBOSE=1"
         }
         set options($host,dir) [compile_source_cmake_get_build_dir $host]
      }
      incr error_count [compile_source_cmake_execute "make" $compile_hosts options report]
   }

   if {$error_count == 0 && !$compile_only} {
      # now delete install directory
      set task_nr [report_create_task report "clear SGE_ROOT" $host]
      report_task_add_message report $task_nr "deleting directory \"$ts_config(product_root)\""
      if {[remote_file_isdirectory $ts_config(master_host) $ts_config(product_root)] &&
          [delete_directory $ts_config(product_root)] != 0} {
         ts_log_severe "could not delete $ts_config(product_root) directory"
         report_task_add_message report $task_nr "could not delete $ts_config(product_root) directory"
         incr error_count
      }

      if {$error_count == 0} {
         # Wait until product root is available on all used cluster hosts
         foreach host [get_all_hosts] {
            if {[wait_for_remote_dir $host $CHECK_USER $ts_config(product_root) 60 1 1] != 0} {
               incr error_count
               break
            }
         }
      }

      if {$error_count == 0} {
         report_finish_task report $task_nr 0
      } else {
         report_finish_task report $task_nr 1
      }
   }

   if {$compile_only} {
      # need to change the owner of binaries to the test user
      # otherwise install will fail to overwrite binaries belonging to root

      set paths_to_change "3rd_party bin ckpt doc dtrace examples hadoop include install_execd"
      append paths_to_change " install_qmaster inst_sge lib man mpi testbin util utilbin"

      # try to chown on the file server
      set fs_host [fs_config_get_server_for_path $ts_config(product_root) 0]
      if {$fs_host == ""} {
         set fs_host $ts_config(master_host)
      }

      start_remote_prog $fs_host "root" "chown" "--quiet --recursive $CHECK_USER $paths_to_change" \
                        prg_exit_state 60 0 $ts_config(product_root) "" 1 0]
      # we use the --quiet option, so chown will never fail, no need to look at the exit status
   }

   if {$error_count == 0} {
      # call make install on every host
      unset -nocomplain options
      foreach host $compile_hosts {
         set num_procs [node_get_processors $host]
	 if {[resolve_arch $host] == "sol-amd64"} {
            set options($host,cmd) "gmake"
	 } else {
            set options($host,cmd) "make"
         }
         if {$num_procs > 1} {
            set options($host,args) "-j $num_procs install VERBOSE=1"
         } else {
            set options($host,args) "install VERBOSE=1"
         }
         set options($host,dir) [compile_source_cmake_get_build_dir $host]
      }
      incr error_count [compile_source_cmake_execute "install" $compile_hosts options report]
   }

   # @todo we might want to call setfileperm.sh in case we just replaced the binaries

   # we installed new binaries and scripts, version information might have changed
   clear_version_info

   return $error_count
}

#****** check/compile_with_aimk() **************************************************
#  NAME
#    compile_with_aimk() -- compile with aimk
#
#  SYNOPSIS
#    compile_with_aimk { host_list report task_name { aimk_options "" } } 
#
#  FUNCTION
#     Start the aimk parallel on some hosts
#
#  INPUTS
#    host_list --  list of host where aimk should be started
#    a_report    --  the report object
#    task_name --  name of the task in the report object
#    aimk_options -- aimk options
#
#  RESULT
#     0: OK
#     1: ERROR
#*******************************************************************************
proc compile_with_aimk {host_list a_report task_name {aimk_options ""}} {
   global CHECK_USER define_daily_build_nr
   global CHECK_HTML_DIRECTORY CHECK_PROTOCOL_DIR ts_config

   upvar $a_report report

   # check source dir
   if {$ts_config(source_dir) == "none"} {
      report_add_message report "source directory is set to \"none\" - cannot compile"
      return 1
   }

   # setup aimk options
   set my_compile_options [get_compile_options_string]
   if { [string length $aimk_options] > 0 } {
      append my_compile_options " $aimk_options"
   }

   set num 0
   array set host_array {}

   # we'll pass a build number into aimk to distinguish our binaries
   # from official builds.
   set build_number [get_build_number]

   set table_row 2
   set status_rows {}
   set status_cols {status file}
   set compile_prog "$ts_config(testsuite_root_dir)/scripts/remotecompile.sh"
   set compile_dir "$ts_config(source_dir)"

   # add build number
   if {$define_daily_build_nr} {
      set compile_args "-DDAILY_BUILD_NUMBER=$build_number $my_compile_options"
   } else {
      set compile_args "$my_compile_options"
   }

   set spawn_list {}
   foreach host $host_list {
      # use all processors for regular build of C code
      if {$task_name == "compile"} {
         set compile_args "$compile_args -parallel [node_get_processors $host]"
      }

      # start build jobs
      ts_log_fine "starting $task_name on host $host with switches $compile_args"

      # enforce deletion of file containing the build_number
      if {$define_daily_build_nr} {
         delete_build_number_object $host $build_number
      }

      set open_spawn [open_remote_spawn_process $host $CHECK_USER $compile_prog "$compile_dir '$compile_args'" 0 "" "" 0 15 0]
      set spawn_id [lindex $open_spawn 1]

      set host_array($spawn_id,host) $host
      set host_array($spawn_id,task_nr) [report_create_task report $task_name $host]
      set host_array($spawn_id,open_spawn) $open_spawn
      lappend spawn_list $spawn_id

      # initialize fancy compile output
      lappend status_rows $host
      set status_array(file,$host) "unknown"
      set status_array(status,$host) "running"
      set status_array(compile_args,$host) $compile_args
      incr num 1
   }

   ts_log_fine "now waiting for end of compile ..."
   set status_updated 1
   set status_time 0
   set timeout 60
   set done_count 0
   log_user 0

   set org_spawn_list $spawn_list
   set do_stop 0
   while {[llength $spawn_list] > 0} {
      expect {
         -i $spawn_list full_buffer {
            # we got full buffer error, stop compileing
            set do_stop 1
         }
         -i $spawn_list timeout {
            # we got timeout, stop compileing
            set do_stop 1
         }
         -i $spawn_list eof {
            set spawn_id $expect_out(spawn_id)
            set host $host_array($spawn_id,host)
            set line $expect_out(0,string)

            report_task_add_message report $host_array($spawn_id,task_nr) "got eof for host \"$host\""
            set host_array($spawn_id,bad_compile) 1

            close_spawn_process $host_array($spawn_id,open_spawn)
            set host_array($spawn_id,open_spawn) "--"
            set index [lsearch -exact $spawn_list $spawn_id]
            set spawn_list [lreplace $spawn_list $index $index]

            set status_array(file,$host)   "-"
            set status_array(status,$host) "eof"
            set status_updated 1
         }
         -i $spawn_list -- "remotecompile * aimk compile error" {
            set spawn_id $expect_out(spawn_id)
            set host $host_array($spawn_id,host)
            set line $expect_out(0,string)

            report_task_add_message report $host_array($spawn_id,task_nr) $line
            set host_array($spawn_id,bad_compile) 1

            close_spawn_process $host_array($spawn_id,open_spawn)
            set host_array($spawn_id,open_spawn) "--"
            set index [lsearch -exact $spawn_list $spawn_id]
            set spawn_list [lreplace $spawn_list $index $index]

            set status_array(file,$host)   "-"
            set status_array(status,$host) "compile error"
            set status_updated 1
         }
         -i $spawn_list -- "remotecompile * aimk no errors" {
            set spawn_id $expect_out(spawn_id)
            set host $host_array($spawn_id,host)
            set line $expect_out(0,string)

            report_task_add_message report $host_array($spawn_id,task_nr) $line
            set host_array($spawn_id,bad_compile) 0

            close_spawn_process $host_array($spawn_id,open_spawn)
            set host_array($spawn_id,open_spawn) "--"
            set index [lsearch -exact $spawn_list $spawn_id]
            set spawn_list [lreplace $spawn_list $index $index]

            set status_array(file,$host)   "-"
            set status_array(status,$host) "finished"
            set status_updated 1
         }
         -i $spawn_list -- "*\n" {
            set spawn_id $expect_out(spawn_id)
            set host $host_array($spawn_id,host)
            set line [split [string trim $expect_out(0,string)]]
            set report_line "[clock format [clock seconds] -format "%H:%M:%S"]:$line"
            report_task_add_message report $host_array($spawn_id,task_nr) $report_line

            # look for output in the form "<compiler> .... -o target ..."
            #                          or "<compiler> .... -c ...."
            if {[llength $line] > 0} {
               set command [lindex $line 0]
               # ts_log_finest "line: $line"
               switch -exact -- $command {
                  "cc" -
                  "gcc" -
                  "xlc" -
                  "xlc_r" -
                  "insure" -
                  "cl.exe" {
                     set pos [lsearch -exact $line "-o"]
                     if {$pos > 0 && [llength $line] > [expr $pos + 1]} {
                        set status_array(file,$host) [lindex $line [expr $pos + 1]]
                        set status_array(status,$host) "running"
                        set status_updated 1
                     } else {
                        set pos [lsearch -glob $line "*.c"]
                        if {$pos > 0 && [llength $line] > $pos} {
                           set status_array(file,$host) [file tail [lindex $line $pos]]
                           set status_array(status,$host) "running"
                           set status_updated 1
                        }
                     }
                  }
                  "ar" {
                     if {[llength $line] > 2} {
                        set status_array(file,$host) [lindex $line 2]
                        set status_array(status,$host) "running"
                        set status_updated 1
                     }
                  }
                  "\[java\]" {
                     #ts_log_finest $line
                     if {[lsearch -exact $line "jar.wait:"] >= 0} {
                        set status_array(file,$host) "java (wait for java build host)"
                        set status_array(status,$host) "waiting"
                        set status_updated 1
                     } else {
                        set pos [lsearch -glob $line "*.c"]
                        if {$pos > 0 && [llength $line] > $pos} {
                           set status_array(file,$host) "java ([file tail [lindex $line $pos]])"
                           set status_array(status,$host) "running"
                           set status_updated 1
                        } else {
                           set pos [string last ":" $line]
                           set pos1 [string last "java\]\}" $line]
                           if { $pos > 0 && $pos1 > 0 } {
                              incr pos1 6
                              set my_text [string range $line $pos1 $pos]
                              if { [string length $my_text] > 60 } {
                                 set my_text [string range $my_text 0 59]
                              }
                              set status_array(file,$host) "java ($my_text)"
                              set status_array(status,$host) "running"
                              set status_updated 1
                           } else {
                              set status_array(file,$host) "java (unparsed output)"
                              set status_array(status,$host) "running"
                              set status_updated 1
                           }
                        }
                     }
                  }
                  default {
                     #set status_array(file,$host)   "(?)"
                     #set status_updated 1
                     #   ts_log_finest "---> unknown <--- $line"
                  }
               }
            }
         }
      }
      if {$do_stop == 1} {
         foreach tmp_spawn_id $spawn_list {
            set host $host_array($tmp_spawn_id,host)
            ts_log_fine "stoping $tmp_spawn_id (host: $host)!"

            set report_line "[clock format [clock seconds] -format "%H:%M:%S"]: got timeout while waiting for output (some host is extremely slow)"
            report_task_add_message report $host_array($tmp_spawn_id,task_nr) $report_line

            set host_array($tmp_spawn_id,bad_compile) 1
            set tmp_open_spawn $host_array($tmp_spawn_id,open_spawn)
            if { $tmp_open_spawn != "--" && $tmp_open_spawn != "" } {
               close_spawn_process $host_array($tmp_spawn_id,open_spawn)
            }
            set host_array($tmp_spawn_id,open_spawn) "--"
            set status_array(file,$host)   "-"
            set status_array(status,$host) "timeout"
         }
         set spawn_list {}
         set status_updated 1
         set status_time 0
      }

      set now [timestamp]
      if {$status_updated && $status_time < $now} {
         set status_time $now
         set status_updated 0

         # output compile status
         set status_output [print_xy_array $status_cols $status_rows status_array status_max_column_len status_max_index_len]
         
         # show
         clear_screen
         ts_log_frame INFO "================================================================================"
         foreach host $host_list {
            ts_log_info "task \'$task_name\' on \'$host\' with args \'$status_array(compile_args,$host)\'" 0 "" 1 0 0
         }
         ts_log_info "$status_output" 0 "" 1 0 0
         ts_log_frame INFO "================================================================================"
      }
   }
   log_user 1

   set compile_error 0
   foreach spawn_id $org_spawn_list {
      if {$host_array($spawn_id,bad_compile) != 0} {
         ts_log_fine "\n=============\ncompile error on host $host_array($spawn_id,host):\n=============\n"
         report_finish_task report $host_array($spawn_id,task_nr) 1
         set compile_error 1
      } else {
         report_finish_task report $host_array($spawn_id,task_nr) 0
      }
   }

   return $compile_error
}

#****** check/get_build_number() ***********************************************
#  NAME
#     get_build_number() -- create a build number
#
#  SYNOPSIS
#     get_build_number { } 
#
#  FUNCTION
#     Creates a build number.
#     Currently, we use the date (formatted as yyyymmdd) as build number.
#
#  INPUTS
#
#  RESULT
#     build number
#*******************************************************************************
proc get_build_number {} {
   set build [clock format [clock seconds] -format "%Y%m%d" -gmt 1]
   return $build
}

#****** check/delete_build_number_object() *************************************
#  NAME
#     delete_build_number_object() -- delete object code containing build num
#
#  SYNOPSIS
#     delete_build_number_object { host build } 
#
#  FUNCTION
#     The function deletes the object code file from the build directory
#     which has the build number compiled in.
#
#     Currently this is the file sge_feature.o.
#
#     As we use the date as build number, the file is only deleted - and
#     therefore will be rebuilt with a new build number - when it has been
#     created or modified earlier than today.
#
#  INPUTS
#     host  - the host for whose architecture the object module will be deleted
#     build - the build number
#*******************************************************************************
proc delete_build_number_object {host build} {
   global ts_config

   if {$ts_config(source_dir) == "none"} {
      ts_log_config "source directory is set to \"none\" - cannot delete a build object"
      return 
   }

   set arch [resolve_build_arch $host]
   set filename "$ts_config(source_dir)/$arch/sge_feature.o"

   # only delete the file, if it is older than 00:00 today
   if {[file exists $filename]} {
      set midnight [clock scan $build -gmt 1]
      if {[file mtime $filename] < $midnight} {
         file delete $filename
      }
   }
}

#****** compile/get_preferred_build_host() *******************************
#  NAME
#     get_preferred_build_host() -- get the preferred compile host
#
#  SYNOPSIS
#     get_preferred_build_host {}
#
#  FUNCTION
#     Returns a preferred compile host.
#     This is the java compile host if one is configured,
#     otherwise the first host in the compile_hosts list.
#
#  INPUTS
#     compile_hosts - list of all compile hosts
#*******************************************************************************
proc get_preferred_build_host {compile_hosts} {
   set host [host_conf_get_java_compile_host 0]

   if {$host == ""} {
      set host [lindex compile_hosts 0]
   }

   return $host
}


# returns -1: error
# returns 0 : no error
proc prepare_packages { } {
   global CHECK_PACKAGE_DIRECTORY CHECK_DEFAULTS_FILE
   global CHECK_JOB_OUTPUT_DIR CHECK_PACKAGE_TYPE
   global CHECK_USER CHECK_PRODUCT_TYPE CHECK_PROTOCOL_DIR
   global CHECK_GROUP check_name CHECK_CUR_PROC_NAME
   global ts_config

   set check_name "prepare_packages"
   set CHECK_CUR_PROC_NAME "prepare_packages"
   set local_host [gethostname]


   #do pre checks like in compile
   if {[file isdirectory "$CHECK_PROTOCOL_DIR"] != 1} {
      set catch_return [ catch {  file mkdir "$CHECK_PROTOCOL_DIR" } ]
      if { $catch_return != 0 } {
           ts_log_fine "could not create directory \"$CHECK_PROTOCOL_DIR\""
           return -1
      }
   }

   set have_tar 0
   set have_zip 0
   if { [ check_packages_directory $CHECK_PACKAGE_DIRECTORY check_tar ] == 0 } {
      ts_log_fine "found tar files"
      set have_tar 1
   }

   if { [ check_packages_directory $CHECK_PACKAGE_DIRECTORY check_zip ] == 0 } {
      ts_log_fine "found zip files"
      set have_zip 1
   }

   if { $have_tar == 0 && $CHECK_PACKAGE_TYPE == "tar" } {
      ts_log_severe "not all tar files available"
      return -1
   }

   if { $have_zip == 0 && $CHECK_PACKAGE_TYPE == "zip" } {
      ts_log_severe "not all zip files available"
      return -1
   }


   if { $have_tar == 1 && $CHECK_PACKAGE_TYPE == "tar" } {

      # shutdown eventually running system
      shutdown_core_system

      set tar_files [ check_packages_directory $CHECK_PACKAGE_DIRECTORY check_both tar ]

      set restore_host_aliases_file 0
      # copy pos. host_aliases file
      if { [ file isfile "$ts_config(product_root)/$ts_config(cell)/common/host_aliases"] == 1 } {
         ts_log_fine "saving host_aliases file ..."
         set restore_host_aliases_file 1
         catch { exec "cp" "$ts_config(product_root)/$ts_config(cell)/common/host_aliases" "$CHECK_JOB_OUTPUT_DIR/host_aliases"  } result
         puts $result
      }
      # now delete install directory
      ts_log_fine "deleting directory \"$ts_config(product_root)\""
      if { [delete_directory "$ts_config(product_root)"] != 0 } {
         ts_log_warning "could not delete $ts_config(product_root) directory, critical error - stop"
         return -1
      }
      # checking permissions
      catch { exec "mkdir" "$ts_config(product_root)"  } result
      puts $result
      catch { exec "chmod" "755" "$ts_config(product_root)"  } result
      puts $result

      catch { file mkdir "$ts_config(product_root)/$ts_config(cell)" }
      catch { file mkdir "$ts_config(product_root)/$ts_config(cell)/common" }

      # copy pos. host_aliases file to new product root /cell/common
      if { [ file isfile "$CHECK_JOB_OUTPUT_DIR/host_aliases"] == 1 &&
           $restore_host_aliases_file == 1 } {
         ts_log_fine "restoring host_aliases file ..."
         catch { exec "cp" "$CHECK_JOB_OUTPUT_DIR/host_aliases" "$ts_config(product_root)/$ts_config(cell)/common/host_aliases" } result
         puts $result
      }

      # copy package files to product root directory
      ts_log_fine "copy package files to product root directory ..."
      set i 0
      foreach file $tar_files {
         ts_log_progress
         incr i 1
         file copy $CHECK_PACKAGE_DIRECTORY/$file $ts_config(product_root)
      }
      ts_log_fine "done"

      # gunzip package files
      ts_log_fine "gunzip package files ..."
      set i 0
      foreach file $tar_files {
         ts_log_progress
         incr i 1
         set catch_out [catch { exec "gunzip" "$ts_config(product_root)/$file"  } result]
         if { $catch_out != 0 } {
            ts_log_fine $result
         }
      }
      ts_log_fine "done"

      # extract package files
      ts_log_fine "extract package files ..."
      set i 0
      foreach file $tar_files {
         ts_log_progress
         incr i 1
         set help [ string first ".gz" $file ]
         incr help -1
         set file_no_gz [string range $file 0 $help]
         set result [start_remote_prog $local_host $CHECK_USER "tar" "-xvf $file_no_gz" prg_exit_state 60 0 $ts_config(product_root)]
         if { $prg_exit_state != 0 } {
            ts_log_fine $result
         }
      }
      ts_log_fine "done"

      # delete untared package files
      ts_log_fine "delete untared package files ..."
      foreach file $tar_files {
         set help [ string first ".gz" $file ]
         incr help -1
         set file_no_gz [string range $file 0 $help]
         delete_file $ts_config(product_root)/$file_no_gz
      }
      ts_log_fine "done"

      # checking for installed archs
      set sys_archs [get_dir_names $ts_config(product_root)/utilbin ]

      set local_host_arch [ resolve_arch $local_host ]
      set local_arch_ok 0

      set arch_string {}
      foreach arch $sys_archs {
         lappend arch_string $arch
         if { [ string compare $arch $local_host_arch ] == 0 } {
            set local_arch_ok 1
         }
      }
      ts_log_fine "architectures: $arch_string"

      # check for testsuite host binaries
      if { $local_arch_ok != 1 } {
         ts_log_severe "host architecture for host $local_host not installed"
         return -1
      }

      # check all archs to appear in execd host list and vice versa
      set execd_archs ""
      foreach elem $ts_config(execd_hosts) {
         set host_arch [ resolve_arch $elem ]
         if { [string compare $host_arch "unknown" ] == 0 } {
            ts_log_severe "could not resolve host \"$elem\"!"
            return -1
         }
         lappend execd_archs $host_arch
         set found_arch 0
         foreach sarch $sys_archs {
            if { [ string compare $sarch $host_arch] == 0 } {
               set found_arch 1
            }
         }
         if { $found_arch != 1 } {
            ts_log_severe "binaries for host \"$elem\" not in tar files, please add tar file"
            return -1
         }
      }

      # try to resolve hostnames in settings file
      set catch_return [ catch { eval exec "cp ${CHECK_DEFAULTS_FILE} ${CHECK_DEFAULTS_FILE}.[timestamp]" } ]
      if { $catch_return != 0 } {
         puts "could not copy defaults file"
         return -1
      }
      return 0
   }

   if { $have_zip == 1 && $CHECK_PACKAGE_TYPE == "zip" } {

      # shutdown eventually running system
      shutdown_core_system

      set zip_files [ check_packages_directory $CHECK_PACKAGE_DIRECTORY check_both zip ]

      set restore_host_aliases_file 0
      # copy pos. host_aliases file
      if { [ file isfile "$ts_config(product_root)/$ts_config(cell)/common/host_aliases"] == 1 } {
         ts_log_fine "saving host_aliases file ..."
         set restore_host_aliases_file 1
         catch { exec "cp" "$ts_config(product_root)/$ts_config(cell)/common/host_aliases" "$CHECK_JOB_OUTPUT_DIR/host_aliases"  } result
         puts $result
      }
      # now delete install directory
      ts_log_fine "deleting directory \"$ts_config(product_root)\""
      if { [delete_directory "$ts_config(product_root)"] != 0 } {
         ts_log_warning "could not delete $ts_config(product_root) directory, critical error - stop"
         return -1
      }
      # checking permissions
      catch { exec "mkdir" "$ts_config(product_root)"  } result
      puts $result
      catch { exec "chmod" "755" "$ts_config(product_root)"  } result
      puts $result

      catch { file mkdir "$ts_config(product_root)/$ts_config(cell)" }
      catch { file mkdir "$ts_config(product_root)/$ts_config(cell)/common" }

      # copy pos. host_aliases file to new product root /$SGE_CELL/common
      if { [ file isfile "$CHECK_JOB_OUTPUT_DIR/host_aliases"] == 1 &&
           $restore_host_aliases_file == 1 } {
         ts_log_fine "restoring host_aliases file ..."
         catch { exec "cp" "$CHECK_JOB_OUTPUT_DIR/host_aliases" "$ts_config(product_root)/$ts_config(cell)/common/host_aliases" } result
         puts $result
      }

      # copy package files to product root directory
      ts_log_fine "copy package files to product root directory ..."
      set i 0
      if { [catch { file mkdir "$ts_config(product_root)/tmp_zip_copy" }] != 0 } {
         ts_log_fine "could not create directory \"$ts_config(product_root)/tmp_zip_copy\""
         return -1
      }
      foreach file $zip_files {
         ts_log_progress
         incr i 1
         file copy $CHECK_PACKAGE_DIRECTORY/$file $ts_config(product_root)/tmp_zip_copy
      }
      ts_log_fine "done"


      # unzip package files
      ts_log_fine "unzip package files ..."
      foreach file $zip_files {
         ts_log_progress
         set catch_out [catch { exec "unzip" "$ts_config(product_root)/tmp_zip_copy/$file" "-d" "$ts_config(product_root)/tmp_zip_copy"  } result]
         if { $catch_out != 0 } {
            ts_log_fine $result
         }
      }
      ts_log_fine "done"

      # delete untared package files
      ts_log_fine "delete untared package files ..."
      foreach file $zip_files {
         delete_file $ts_config(product_root)/tmp_zip_copy/$file
      }
      ts_log_fine "done"


      # now check if packages are already installed and remove installed ones
      set package_names [ get_dir_names $ts_config(product_root)/tmp_zip_copy ]
      puts "Found following packages: $package_names"
      set user_key "unknown"
      foreach pkg $package_names {
         puts -nonewline "Checking if package \"$pkg\" is already installed on host \"$local_host\" ... "
         set output [start_remote_prog $local_host "root" [get_binary_path $local_host "pkginfo"] "$pkg"]
         if { $prg_exit_state != 0 } {
            puts "not installed"
         } else {
            puts "already installed."
            puts "\n$output\n"
            puts "Press \"yes\" to uninstall ALL packages listed above or \"no\" to continue ..."
            if { $user_key == "unknown" } {
               set user_key [ wait_for_enter 1 ]
            }
            if { $user_key == "yes" } {
               puts "removing package \"$pkg\" ..."
               set output [start_remote_prog $local_host "root" [get_binary_path $local_host "pkgrm"] "-n $pkg"]
               puts $output
               if { $prg_exit_state != 0 } {
                  puts "error uninstalling package \"$pkg\""
                  puts "stop package installation"
                  return -1
               }
            } else {
               puts "will NOT remove package \"\""
               puts "stop package installation"
               return -1
            }
         }
      }

      # now install the packages ...
      set send_speed .1
      set send_slow "1 $send_speed"
      foreach pkg $package_names {
         set id [open_remote_spawn_process "$local_host" "root" "pkgadd" "-d $ts_config(product_root)/tmp_zip_copy $pkg" ]
         log_user 1
         set sp_id [ lindex $id 1 ]
         set timeout 60
         set do_stop 0
         set exit_state 1
         while { $do_stop == 0 } {
            flush stdout
            expect {
               -i $sp_id full_buffer {
                  ts_log_severe "buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
                  close_spawn_process $id
                  return -1
               }
               -i $sp_id timeout {
                  ts_log_severe "unexpected timeout"
                  close_spawn_process $id
                  return -1
               }
               -i $sp_id eof {
                  set exit_state [close_spawn_process $id]
                  set do_stop 1
               }
               -i $sp_id "_exit_status_:*\n" {
                  set buf $expect_out(buffer)
                  set s_start [ string first "(" $buf ]
                  set s_end [ string first ")" $buf ]
                  incr s_start 1
                  incr s_end -1
                  set exit_state [ string range $buf $s_start $s_end ]
                  puts "exit state is: \"$exit_state\""
                  close_spawn_process $id
                  set do_stop 1
               }
               -i $sp_id "default /gridware/sge*]" {
                  flush stdout
                  if { [ string length $ts_config(product_root) ] >= 5  } {
                     send -s -i $sp_id "$ts_config(product_root)\n"
                  } else {
                     ts_log_severe "can't use product root directory (shorter than 5 chars)"
                     close_spawn_process $id
                     return -1
                  }
                  flush stdout
               }
               -i $sp_id "default sgeadmin*]" {
                  flush stdout
                  send -s -i $sp_id "$CHECK_USER\n"
                  flush stdout
               }
               -i $sp_id "Do you want to install these as setuid/setgid files*]" {
                  flush stdout
                  send -s -i $sp_id "y\n"
                  flush stdout
               }


               -i $sp_id "default adm*]" {
                  send -s -i $sp_id "$CHECK_GROUP\n"
                  flush stdout
               }
               -i $sp_id "Waiting for pkgadd of*" {
                  ts_log_severe "$local_host: another pkgadd session is running...\n$expect_out(buffer)"
                  close_spawn_process $id
                  return -1
               }
               -i $sp_id "*\n" {
                  flush stdout
               }
               -i $sp_id default {
                  ts_log_severe "undefined behaviour: $expect_out(buffer)"
                  close_spawn_process $id
                  return -1
               }
            }
         }
         if { $exit_state != 0 } {
            ts_log_severe "exit state of pgkadd \"$pkg\" is $exit_state -> error"
            return -1
         }
      }

      # checking for installed archs
      set sys_archs [get_dir_names $ts_config(product_root)/utilbin ]

      set local_host_arch [ resolve_arch $local_host ]
      set local_arch_ok 0
      puts -nonewline "architectures:"

      foreach arch $sys_archs {
         puts -nonewline " $arch"
         if { [ string compare $arch $local_host_arch ] == 0 } {
            set local_arch_ok 1
         }
      }
      puts ""

      # check for testsuite host binaries
      if { $local_arch_ok != 1 } {
         ts_log_severe "host architecture for host $local_host not installed"
         return -1
      }

      # check all archs to appear in execd host list and vice versa
      set execd_archs ""
      foreach elem $ts_config(execd_hosts) {
         set host_arch [ resolve_arch $elem ]
         if { [string compare $host_arch "unknown" ] == 0 } {
            ts_log_severe "could not resolve host \"$elem\"!"
            return -1
         }
         lappend execd_archs $host_arch
         set found_arch 0
         foreach sarch $sys_archs {
            if { [ string compare $sarch $host_arch] == 0 } {
               set found_arch 1
            }
         }
         if { $found_arch != 1 } {
            ts_log_severe "binaries for host \"$elem\" not in zip files, please add zip file"
            return -1
         }
      }

      # try to resolve hostnames in settings file
      set catch_return [ catch { eval exec "cp ${CHECK_DEFAULTS_FILE} ${CHECK_DEFAULTS_FILE}.[timestamp]" } ]
      if { $catch_return != 0 } {
         puts "could not copy defaults file"
         return -1
      }
      return 0
   }

   return -1
}
# mode : check_both, check_tar, check_zip
# get_files : no, tar, zip
proc check_packages_directory { path { mode "check_both" } { get_files "no" } } {
   global CHECK_PACKAGE_TYPE

   set tar_bin_files [ get_file_names $path "*cs*-*bin-*.tar.gz" ]
   set zip_bin_files [ get_file_names $path "*cs*-*bin-*.zip" ]
   set tar_common_files [ get_file_names $path "*cs*-common*.tar.gz" ]
   set zip_common_files [ get_file_names $path "*cs*-common*.zip" ]
   set tar_doc_files [ get_file_names $path "*cs*-doc*.tar.gz" ]
   set zip_doc_files [ get_file_names $path "*cs*-doc*.zip" ]

   set tar_list "$tar_bin_files $tar_common_files $tar_doc_files"
   set zip_list "$zip_bin_files $zip_common_files $zip_doc_files"


   set nr_tar_bin_files [ llength $tar_bin_files ]
   set nr_zip_bin_files [ llength $zip_bin_files ]
   set nr_tar_common_files [ llength $tar_common_files ]
   set nr_zip_common_files [ llength $zip_common_files ]
   set nr_tar_doc_files [ llength $tar_doc_files ]
   set nr_zip_doc_files [ llength $zip_doc_files ]

   set tar_complete 0
   set zip_complete 0

   if {$tar_bin_files  > 0 && $tar_common_files > 0} {
      set tar_complete 1
   }
   if {$zip_bin_files  > 0 && $zip_common_files > 0} {
      set zip_complete 1
   }

   if { $get_files == "no" } {
      puts ""
      puts "nr. of binary tar files: $nr_tar_bin_files"
      puts "nr. of binary zip files: $nr_zip_bin_files"
      puts "nr. of common tar files: $nr_tar_common_files"
      puts "nr. of common zip files: $nr_zip_common_files"
      puts "nr. of doc tar files: $nr_tar_doc_files"
      puts "nr. of doc zip files: $nr_zip_doc_files"
      if { $tar_complete == 1 } {
         puts "tar files complete"
      } else {
         puts "tar files INCOMPLETE"
      }
      if { $zip_complete == 1 } {
         puts "zip files complete"
      } else {
         puts "zip files INCOMPLETE"
      }

      if { $tar_complete == 1 && $zip_complete == 1 && $mode == "check_both" } {
         return 0
      }
      if { $tar_complete == 1 && $mode == "check_tar" } {
         return 0
      }
      if { $zip_complete == 1 && $mode == "check_zip" } {
         return 0
      }
      return -1
   } else {
      switch -- $get_files {
         "tar" {
             if { $tar_complete == 0 } {
                ts_log_severe "tar files incomplete error"
                return ""
             }
             return $tar_list
         }
         "zip" {
             if { $tar_complete == 0 } {
                ts_log_severe "zip files incomplete error"
                return ""
             }
             return $zip_list
         }
      }
   }
   return -1
}

#****** compile/build_distribution() **********************************
#  NAME
#     build_distribution() -- create distribution packages
#
#  SYNOPSIS
#     build_distribution {arch_list report_var}
#
#  FUNCTION
#     Calls mk_dist to build distribution packages for the given
#     architectures.
#     Logs information and error messages to the HTML report.
#
#  INPUTS
#     arch_list   - list of archtectures for binary packages
#     report_var  - HTML report, call by reference
#
#  RESULT
#     1 - OK, packages got created
#     0 - there were errors
#*******************************************************************************
proc build_distribution {arch_list report_var} {
   global CHECK_USER
   global ts_config
   global ts_checktree

   upvar $report_var report

   # if possible, call mk_dist on the file server
   set host [fs_config_get_server_for_path $ts_config(product_root) 0]
   if {$host == ""} {
      set host [gethostname]
   }

   # create task in HTML output
   set task_nr [report_create_task report "create distribution" $host]

   # we need the package directory configured
   if {$ts_config(package_directory) == "none"} {
      report_task_add_message report $task_nr "no package directory configured"
      report_finish_task report $task_nr 1
      return 0
   }

   # make sure the package directory exists
   if {![remote_file_isdirectory $host $ts_config(package_directory)]} {
      report_task_add_message report $task_nr "creating directory $ts_config(package_directory)"
      remote_file_mkdir host $ts_config(package_directory)
   }

   ts_log_fine "creating tar packages"
   # distribution will be created using mk_dist
   # figure out which commandline options to use
   set args ""
   append args "-vdir $ts_config(product_root)"             ;# find the distrib here
   append args " -version $ts_config(package_release)"      ;# for package names
   append args " -basedir $ts_config(package_directory)"    ;# destination dir
   append args " -bin -testbin -common"                     ;# which packages

   # if we built documentation then also create a doc package
   if {[host_conf_get_doc_compile_host] != ""} {
      append args " -doc"
   }

   # derive mk_dist's product mode from the extensions directory
   if {$ts_config(ext_source_dir) == "none"} {
      append args " -product ocs"
   } else {
      append args " -product gcs"
   }

   # add mk_dist options specific to additional checktrees
   for {set i 0} {$i < $ts_checktree(next_free)} {incr i} {
      if {[info exists ts_checktree($i,mk_dist_options)]} {
         append args " $ts_checktree($i,mk_dist_options)"
      }
   }

   # start mk_dist
   ts_log_fine "starting mk_dist $args $arch_list"
   report_task_add_message report $task_nr "starting mk_dist $args $arch_list"
   set open_spawn [open_remote_spawn_process $host $CHECK_USER "./scripts/mk_dist" "$args $arch_list" 0 $ts_config(source_dir)]
   set sp_id [lindex $open_spawn 1]
   set timeout 60
   set error 0
   expect_user {
      -i $sp_id full_buffer {
         ts_log_fine "buffer overflow, please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
         report_task_add_message report $task_nr "buffer overflow, please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
         incr error
      }
      -i $sp_id timeout {
         ts_log_fine "timeout while waiting for mk_dist output"
         report_task_add_message report $task_nr "timeout while waiting for mk_dist output"
         incr error
      }
      -i $sp_id eof {
         ts_log_fine "unexpected eof"
         report_task_add_message report $task_nr "unexpected eof"
         incr error
      }
      -i $sp_id "_exit_status_:(*)" {
         set exit_status [get_string_value_between "_exit_status_:(" ")" $expect_out(0,string)]
         ts_log_fine "mk_dist exited with exit status $exit_status"
         report_task_add_message report $task_nr "mk_dist exited with exit status $exit_status"
         if {$exit_status != 0} {
            incr error
         }
      }
      -i $sp_id "*\n" {
         ts_log_fine $expect_out(0,string)
         report_task_add_message report $task_nr $expect_out(0,string)
         exp_continue
      }
   }
   close_spawn_process $open_spawn
   ts_log_newline

   if {$error > 0} {
      report_finish_task report $task_nr 1
      return 0
   } else {
      report_finish_task report $task_nr 0
      return 1
   }
}

proc install_binaries {arch_list a_report} {
   global CHECK_PRODUCT_TYPE
   global CHECK_JOB_OUTPUT_DIR
   global CHECK_USER ts_config
   upvar $a_report report

   # try to do the installations on the file server for SGE_ROOT
   set install_host [fs_config_get_server_for_path $ts_config(product_root) 0]
   if {$install_host == ""} {
      set install_host [gethostname]
   }

   set was_error 0

   set task_nr [report_create_task report "install_binaries" $install_host]

   if {$ts_config(source_dir) == "none"} {
      report_task_add_message report $task_nr "source directory is set to \"none\" - cannot build distribution"
      report_finish_task report $task_nr -1
      return -1
   }


   # copy pos. host_aliases file to trash_
   if {[is_remote_file $install_host $CHECK_USER "$ts_config(product_root)/$ts_config(cell)/common/host_aliases"]} {
      report_task_add_message report $task_nr "saving host_aliases file ..."
      set result [start_remote_prog $install_host $CHECK_USER "cp" "$ts_config(product_root)/$ts_config(cell)/common/host_aliases $CHECK_JOB_OUTPUT_DIR/host_aliases"]
      ts_log_fine $result
      report_task_add_message report $task_nr $result
   }

   # now delete install directory
   report_task_add_message report $task_nr "deleting directory \"$ts_config(product_root)\""
   if {[delete_directory "$ts_config(product_root)"] != 0} {
      ts_log_warning "could not delete $ts_config(product_root) directory, critical error - stop"
      report_task_add_message report $task_nr "could not delete $ts_config(product_root) directory, critical error - stop"
      report_finish_task report $task_nr -1
      return -1
   }

   # Wait until product root is available on all used cluster hosts
   foreach tmp_host [get_all_hosts] {
      wait_for_remote_dir $tmp_host $CHECK_USER "$ts_config(product_root)" 60 1 1
   }

   ts_log_fine "starting installation ..."
   set result [remote_file_mkdir $install_host $ts_config(product_root)]
   report_task_add_message report $task_nr $result
   set result [start_remote_prog $install_host $CHECK_USER "chmod" "755 $ts_config(product_root)"]
   report_task_add_message report $task_nr $result

   report_task_add_message report $task_nr "\ninstalling product binaries"

   set inst_env(SGE_ROOT) $ts_config(product_root)

   # pass path to man pages to distinst
   set dist_inst_options "-mansrc uge"

   if {[string compare "none" $ts_config(dist_install_options)] != 0} {
      append dist_inst_options " $ts_config(dist_install_options)"
   }

   set open_spawn [open_remote_spawn_process $install_host $CHECK_USER "./scripts/distinst" "-local -noexit $dist_inst_options $arch_list" 0 $ts_config(source_dir) inst_env]
   set sp_id [lindex $open_spawn 1]
   set timeout -1
   set done 0
   ts_log_fine "installing ... "
   while { $done != 1 } {
      expect_user {
         -i $sp_id full_buffer {
            report_task_add_message report $task_nr "testsuite - compile source buffer overflow please increment CHECK_EXPECT_MATCH_MAX_BUFFER value"
         }
         -i $sp_id "Base directory:" {
             ts_send $sp_id "y\n"
         }
         -i $sp_id "overriding mode" {
             ts_send $sp_id "y\n"
         }
         -i $sp_id "_exit_status_:(*)" {
            set remote_exit_state [get_string_value_between "(" ")" $expect_out(0,string)]
            if {$remote_exit_state != 0} {
               report_task_add_message report $task_nr "distinst exited with exit code $remote_exit_state: $expect_out(buffer)"
               set was_error 1
            }
            set done 1
         }
         -i $sp_id eof {
            set done 1
         }
         -i $sp_id "*\n" {
            report_task_add_message report $task_nr $expect_out(0,string)
            ts_log_progress
         }
      }
   }
   close_spawn_process $open_spawn
   ts_log_fine " done"
   ts_log_newline

   if {!$was_error} {
      # Wait until product root/bin directory is available on all used cluster hosts
      resolve_arch_clear_cache
      foreach tmp_host [get_all_hosts] {
         set arch [resolve_arch $tmp_host]
         set wait_path "$ts_config(product_root)/bin/$arch"
         wait_for_remote_dir $tmp_host $CHECK_USER $wait_path
      }

      foreach elem $ts_config(execd_hosts) {
         set host_arch [resolve_arch $elem 1]
         if {[string compare $host_arch ""] != 0 && [string compare $host_arch "unknown"] != 0} {
            report_task_add_message report $task_nr " arch on host $elem is $host_arch - successfully installed binaries"
         } else {
            report_task_add_message report $task_nr " error installing binaries for host $elem"
            set was_error 1
         }
      }
   }

   if {!$was_error} {
      remote_file_mkdir $install_host "$ts_config(product_root)/man"
      remote_file_mkdir $install_host "$ts_config(product_root)/catman"
      remote_file_mkdir $install_host "$ts_config(product_root)/$ts_config(cell)"
      remote_file_mkdir $install_host "$ts_config(product_root)/$ts_config(cell)/common"

      # copy pos. host_aliases file to new product root /$SGE_CELL/common
      if {[is_remote_file $install_host $CHECK_USER "$CHECK_JOB_OUTPUT_DIR/host_aliases"]} {
           report_task_add_message report $task_nr "restoring host_aliases file ..."
           set result [start_remote_prog $install_host $CHECK_USER "cp" "$CHECK_JOB_OUTPUT_DIR/host_aliases $ts_config(product_root)/$ts_config(cell)/common/host_aliases"]
           report_task_add_message report $task_nr $result
      }

      # For SGE <= 6.2u5: copy source/dist/util/arch to $SGE_ROOT/util.
      if {$ts_config(gridengine_version) <= 62} {
         set arch_script_src "$ts_config(source_dir)/dist/util/arch"
         set arch_script_dst "$ts_config(product_root)/util/arch"
         report_task_add_message report $task_nr "installing $arch_script_src ..."
         start_remote_prog $install_host $CHECK_USER "cp" "$arch_script_src $arch_script_dst"
      }
   }

   # done - final error handling
   if {$was_error} {
      report_finish_task report $task_nr -1
   } else {
      report_finish_task report $task_nr 0
   }
   return $was_error
}


# Vivado Launch Script
#### Change design settings here #######
set design rtclock
set top rtclock
set device xczu3eg-sbva484-1-e
set proj_dir ./synth
set ip_version 1.0
set lib_name ip
set vendor lightside-instruments.com
#####################################
# set IP paths
#####################################

#####################################
# Project Settings
#####################################
create_project -name ${design} -force -dir "./${proj_dir}" -part ${device} -ip
set_property source_mgmt_mode All [current_project]  
set_property top ${top} [current_fileset]
set_property ip_repo_paths ../../../  [current_fileset]
puts "Creating Output Port Lookup IP"
# Project Constraints
#####################################
# Project Structure & IP Build
#####################################
read_verilog "./hdl/rtclock.v"
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

ipx::package_project

set_property name ${design} [ipx::current_core]
set_property library ${lib_name} [ipx::current_core]
set_property vendor_display_name {Lightside Instruments AS} [ipx::current_core]
set_property company_url {http://lightside-instruments.com} [ipx::current_core]
set_property vendor {lightside-instruments.com} [ipx::current_core]
#set_property supported_families {{virtex7} {Production}} [ipx::current_core]
set_property taxonomy {{/lsi/generic}} [ipx::current_core]
set_property version ${ip_version} [ipx::current_core]
set_property display_name ${design} [ipx::current_core]
set_property description ${design} [ipx::current_core]

ipx::add_user_parameter {C_CLK_TO_NS_RATIO} [ipx::current_core]
set_property value_resolve_type {user} [ipx::get_user_parameter C_CLK_TO_NS_RATIO [ipx::current_core]]
set_property display_name {C_CLK_TO_NS_RATIO} [ipx::get_user_parameter C_CLK_TO_NS_RATIO [ipx::current_core]]
set_property value {8} [ipx::get_user_parameter C_CLK_TO_NS_RATIO [ipx::current_core]]
set_property value_format {long} [ipx::get_user_parameter C_CLK_TO_NS_RATIO [ipx::current_core]]

puts stdout [ipx::get_file_groups]
set proj_filegroup_synth [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects [ipx::current_core]]
set proj_filegroup_sim [ipx::get_file_groups xilinx_anylanguagebehavioralsimulation -of_objects [ipx::current_core]]
puts stdout ${proj_filegroup_sim}

ipx::infer_user_parameters [ipx::current_core]

ipx::check_integrity [ipx::current_core]
ipx::save_core [ipx::current_core]
update_ip_catalog
close_project

file delete -force ${proj_dir} 

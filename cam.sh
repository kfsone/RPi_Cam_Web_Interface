#!/bin/bash

# Bootstrap.
cd $(dirname $(readlink -f $0))
source lib/common.shfrag
source ./lib/webservers.shfrag
fn_enable_debug_log cam.txt
fn_require_dialog
fn_load_config true  # Load or generate the config file.

ASK_TO_REBOOT=0
MAINSCRIPT="./RPi_Cam_Web_Interface_Installer.sh"

function get_config_var()
{
    lua - "$1" "$2" <<EOF
local key=assert(arg[1])
local fn=assert(arg[2])
local file=assert(io.open(fn))
local found=false
for line in file:lines() do
  local val = line:match("^%s*"..key.."=(.*)$")
  if (val ~= nil) then
    print(val)
    found=true
    break
  end
end
if not found then
  print(0)
end
EOF
}

function set_config_var()
{
    lua - "$1" "$2" "$3" <<EOF > "$3.bak"
local key=assert(arg[1])
local value=assert(arg[2])
local fn=assert(arg[3])
local file=assert(io.open(fn))
local made_change=false
for line in file:lines() do
  if line:match("^#?%s*"..key.."=.*$") then
    line=key.."="..value
    made_change=true
  end
  print(line)
end

if not made_change then
  print(key.."="..value)
end
EOF
    mv "$3.bak" "$3"
}


# Helper: exit cleanly or ask the user to reboot.
# If the user is asked to reboot and declines, run the MAINSCRIPT.
#
function do_finish()
{
    if [ $ASK_TO_REBOOT -ne 1 ]; then
        exit 0
    fi
    fn_ask "Reboot?" "Would you like to reboot now?"
    if [ $? -eq 0 ]; then # yes
        sync && sync
        reboot
    elif [ $? -eq 1 ]; then # no
        exec sudo $MAINSCRIPT
    fi
}


function do_camera ()
{
    if [ ! -e /boot/start_x.elf ]; then
        fn_feedback 5 \
            "Missing start_x.elf" \
            "Your firmware appears to be out of date, please update it!"
	    exec sudo $MAINSCRIPT
    fi

    fn_ask "Raspberry Pi camera message" \
        "Enable support for Raspberry Pi camera?" \
        --extra-button --extra-label Disable --ok-label Enable
    response=$?
    case $response in
        0)
            fn_info "[Enable] selected."
            set_config_var start_x 1 $RASPICONFIG
            CUR_GPU_MEM=$(get_config_var gpu_mem $RASPICONFIG)
            if [ -z "$CUR_GPU_MEM" ] || [ "$CUR_GPU_MEM" -lt 128 ]; then
                set_config_var gpu_mem 128 $RASPICONFIG
            fi
            sed $RASPICONFIG -i -e "s/^startx/#startx/"
            sed $RASPICONFIG -i -e "s/^fixup_file/#fixup_file/"
            ASK_TO_REBOOT=1
            do_finish
        ;;
        1)
            fn_info "[Cancel] selected."
            exec sudo $MAINSCRIPT
        ;;
        3)
            fn_info "[Disable] selected."
            set_config_var start_x 0 $RASPICONFIG
            sed $RASPICONFIG -i -e "s/^startx/#startx/"
            sed $RASPICONFIG -i -e "s/^start_file/#start_file/"
            sed $RASPICONFIG -i -e "s/^fixup_file/#fixup_file/"
            ASK_TO_REBOOT=1
            do_finish
        ;;
        255)
            fn_info "[Esc] pressed."
            exec sudo $MAINSCRIPT
        ;;
    esac
}


##############################################################################
### Main
##############################################################################


do_camera

exit 1  # should never be reached

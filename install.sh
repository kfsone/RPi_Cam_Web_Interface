#!/bin/bash

# Copyright (c) 2015, Bob Tidey
# All rights reserved.

# Redistribution and use, with or without modification, are permitted provided
# that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Neither the name of the copyright holder nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Description
# This script installs a browser-interface to control the RPi Cam. It can be run
# on any Raspberry Pi with a newly installed raspbian and enabled camera-support.
# RPI_Cam_Web_Interface installer by Silvan Melchior
# Edited by jfarcher to work with github
# Edited by slabua to support custom installation folder
# Additions by btidey, miraaz, gigpi
# Rewritten and split up by Bob Tidey 


# Bootstrap.
cd $(dirname $(readlink -f $0))
source lib/common.shfrag
source ./lib/webservers.shfrag
fn_enable_debug_log install.txt
fn_require_dialog
fn_load_config true  # Load or generate the config file.

rpicamdirold="${rpicamdir}"
if [ -n "${rpicamdirold}" ]; then
  rpicamdirold="/${rpicamdirold}"
fi

# Allow for a quiet install
rm -f exitfile.txt
if [ $# -eq 0 ] || [ "$1" != "q" ]; then

    cfg_file=$(tempfile)
    trap "rm -f ${cfg_file}" EXIT
    exec 3>"${cfg_file}"
    fn_dialog "RPiCam Configuration" \
        --output-fd 3 \
        --separate-widget $'\n'                                 \
        --form ""                                               \
        0 0 0                                                   \
        "Cam subfolder:"        1 1   "$rpicamdir"   1 32 15 0  \
        "Autostart:$optautost"  2 1   "$autostart"   2 32 15 0  \
        "Server:$optservers"    3 1   "$webserver"   3 32 15 0  \
        "Webport:"              4 1   "$webport"     4 32 15 0  \
        "User:$optuser"         5 1   "$user"        5 32 15 0  \
        "Password:"             6 1   "$webpasswd"   6 32 15 0  \
        "jpglink:$optjpglink"   7 1   "$jpglink"     7 32 15 0  \
    || fn_abort "Dialog cancelled."
    exec 3>&-

    exec 3<"${cfg_file}"
    for var in rpicamdir autostart webserver webport user webpasswd jpglink
    do
        read -u 3 -r value
        eval "${var}=\"${value}\""
    done
    exec 3<&-

    if [ -z "${webport}" ]; then
        fn_abort "Missing 'webport', can't proceeed."
    fi

    fn_info "rpicamdir=$rpicamdir, webport=$webport"

    fn_generate_config

    source "${configfile}"
fi


function fn_motion_cfg()
{
    local param="${1}"; shift
    local setting="${1}"; shift

    # Using '#' instead of '/' as separators.
    # Lines that are commented out get swapped in
    sudo sed -i "s#^\(; *\)${param}.*#${param} ${setting}#g" "${motionconf}"
}

function fn_motion_unset()
{
    local param="${1}"; shift
    sudo sed -i "s#^ *${param}.*#; ${param}#g" "${motionconf}"
} 

# Helper function to configure motion detection.
function fn_motion ()
{
    fn_motion_cfg netcam_url "http://localhost:$webport${rpicamdir}/cam_pic.php"
    if [ "$user" == "" ]; then
        fn_motion_unset netcam_userpass
    else
        fn_motion_cfg netcam_userpass "${user}:${webpasswd}"
    fi
    fn_motion_cfg on_event_start "echo -n '1' >${_camdir}/FIFO1"
    fn_motion_cfg on_event_end   "echo -n '0' >${_camdir}/FIFO1"
    fn_motion_cfg control_port 6642
    fn_motion_cfg control_html_output off
    fn_motion_cfg output_pictures  off
    fn_motion_cfg ffmpeg_output_movies off
    fn_motion_cfg ffmpeg_cap_new off
    fn_motion_cfg stream_port 0
    fn_motion_cfg webcam_port 0
    fn_motion_unset process_id_file
    fn_motion_unset videodevice
    sudo sed -i "s#^event_gap *60#event_gap 3#g" "${motionconf}"
    sudo chown motion:www-data -- "${motionconf}"
    sudo chmod ug=rw,o=r -- "${motionconf}"
}


# Helper function to configure autostart.
function fn_autostart ()
{
    # Always disable ourselves first.
    fn_autostart_disable

    # If auto-start is enabled, add in our code.
    if [ "$autostart" == "yes" ]; then
        if [ -z "$(grep '^exit 0' "${autostartfile}")" ]; then
            fn_abort "Cannot find 'exit 0' at end of ${autostartfile}"
        fi

        tempfile=$(tempfile)
        cat <<EOF >"${tempfile}"
${RC_START}
mkdir -p ${MJPEG_DEV}
chown www-data:www-data ${MJPEG_DEV}
chmod 777 ${MJPEG_DEV}
sleep 4;su -c 'raspimjpeg > /dev/null 2>&1 &' www-data
if [ -e /etc/debian_version ]; then
    sleep 4;su -c 'php ${_camdir}/schedule.php > /dev/null 2>&1 &' www-data
else
    sleep 4;su -s '/bin/bash' -c 'php ${_camdir}/schedule.php > /dev/null 2>&1 &' www-data
fi
${RC_END}
EOF

        # Add our configuration prior to the 'exit 0' line in rc.local.
        sudo sed -i -e "/^exit [ ]*0/r ${tempFile}" "${autostartfile}"

        rm -f "${tempfile}"
    fi
}

function fn_check_preconditions ()
{
    # Check if we need to move files from an old install to a new location.
    if [ "${rpicamdir}" != "${rpicamdirold}" ]; then
        fn_debug "camdir has changed: ${rpicamdirold} -> ${rpicamdir}"
        if [ -e "/var/www${rpicamdirold}/index.php" ]; then
            if [ ! -e "/var/www/${rpicamdir}/index.php" ]; then
                fn_debug "camdirold exists. content move indicated."
                _move_content=true
            else
                fn_warn "camdir changed ({$rpicamdirold} -> ${rpicamdir}), " \
                        "but new directory already appears populated. "\
                        "Not copying files." 
            fi
        fi
    fi

    fn_check_missing_or -d "${MJPEG_DEV}"
    fn_check_missiong_or -d "/etc/raspimjpeg"
    fn_check_missing_or -l "/usr/bin/raspimjpeg"
}


# Check if we need to create a named fifo, and make sure that an existing
# file is actually a fifo.
#
# \param   filename    filename only of file to test/create.
#
function fn_check_fifo()
{
    local fifoname="${_camdir}/${1}"; shift

    if [ -e "${fifoname}" -a ! -p "${fifoname}" ]; then
        fn_displace_to_bak "${fifoname}" "Existing file is not a fifo"
    fi
    if [ ! -e "${fifoname}" ]; then
        sudo mknod "${fifoname}" p
    fi
    sudo chmod ugo=rw "${fifoname}"
}


##############################################################################
### Main
##############################################################################

# Check any conditions that the user needs to resovle before we can proceed.
fn_check_preconditions

# Stop the service if it's currently running.
fn_info "Stopping any running rpicam instance."
fn_stop

_camdir="/var/www${rpicamdir}"

sudo mkdir -p "${_camdir}/media"

# Move old material if changing from a different install folder
if [ "${_move_content}" ]; then
    fn_info "Moving old files to new install folder."
    sudo mv ${_camdir}old/* "${_camdir}"
fi

# Copy over the web content.
sudo cp -r www/* "${_camdir}"/
# Make sure there isn't an 'index.html' file blocking index.php
fn_displace_to_bak "${_camdir}/index.html" "RPiCam uses index.php".

# Run the relevant webserver config.
if [ "$webserver" == "apache" ]; then
    fn_apache
elif [ "$webserver" == "nginx" ]; then
    fn_nginx
elif [ "$webserver" == "lighttpd" ]; then
    fn_lighttpd
fi

# Make sure user www-data has bash shell
sudo sed -i "s/^www-data:x.*/www-data:x:33:33:www-data:\/var\/www:\/bin\/bash/g" /etc/passwd

# Make sure the FIFO exists
fn_check_fifo "FIFO"
fn_check_fifo "FIFO1"
fn_check_fifo "FIFO11"

sudo chmod u=rwx,go=rx "${_camdir}/raspizip.sh"

if [ ! -d ${MJPEG_DEV} ]; then
    mkdir "${MJPEG_DEV}"
fi

if [ "$jpglink" == "yes" ]; then
    if [ ! -e ${_camdir}/cam.jpg ]; then
       sudo ln -sf ${MJPEG_DEV}/cam.jpg ${_camdir}/cam.jpg
    fi
fi

sudo rm -f "${_camdir}/status_mjpeg.txt"
if [ ! -e "${MJPEG_STATUS}" ]; then
    echo -n 'halted' >"${MJPEG_STATUS}"
fi

# Make sure that 'raspimjpeg' isn't running somewhere.
sleep 1 ; sudo killall raspimjpeg ; sleep 1

sudo chown www-data:www-data "${MJPEG_STATUS}"
sudo rm -f "${_camdir}/status_mjpeg.txt"
sudo ln -sf "${MJPEG_STATUS}" ${_camdir}/status_mjpeg.txt

sudo chown -R www-data:www-data "${_camdir}"
sudo cp etc/sudoers.d/RPI_Cam_Web_Interface /etc/sudoers.d/
sudo chmod ug=r /etc/sudoers.d/RPI_Cam_Web_Interface

sudo cp -r bin/raspimjpeg "${RASPIMJPEGDIR}/"
sudo chmod u=rwx,go=rx "${RASPIMJPEGDIR}/raspimjpeg"
if [ ! -e /usr/bin/raspimjpeg ]; then
    sudo ln -s "${RASPIMJPEGDIR}/raspimjpeg" /usr/bin/raspimjpeg
fi

sed -e "s#www#www${rpicamdir}#" etc/raspimjpeg/raspimjpeg.1 > etc/raspimjpeg/raspimjpeg
if [[ `cat /proc/cmdline |awk -v RS=' ' -F= '/boardrev/ { print $2 }'` == "0x11" ]]; then
    sed -i 's/^camera_num 0/camera_num 1/g' etc/raspimjpeg/raspimjpeg
fi
if [ -e /etc/raspimjpeg ]; then
    fn_info "Your custom raspimjpg backed up at /etc/raspimjpeg.bak"
    sudo cp -r /etc/raspimjpeg /etc/raspimjpeg.bak
fi
sudo cp -r etc/raspimjpeg/raspimjpeg /etc/
sudo chmod u=rw,go=r /etc/raspimjpeg
if [ ! -e "${_camdir}/raspimjpeg" ]; then
    sudo ln -s /etc/raspimjpeg "${_camdir}/raspimjpeg"
fi

sudo usermod -a -G video www-data
if [ -e "${_camdir}/uconfig ]"; then
    sudo chown www-data:www-data ${_camdir}/uconfig
fi

fn_info "Configuration motion detector."
fn_motion

fn_info "Configuring autostart [(${autostart})]."
fn_autostart

if [ -e ${_camdir}/uconfig ]; then
    sudo chown www-data:www-data ${_camdir}/uconfig
fi

if [ -e "${_camdir}/schedule.php" ]; then
    sudo rm "${_camdir}/schedule.php"
fi

sudo sed -e "s#www#www${rpicamdir}#g" www/schedule.php > www/schedule.php.1
sudo mv www/schedule.php.1 "${_camdir}/schedule.php"
sudo chown www-data:www-data "${_camdir}/schedule.php"

if [ $# -eq 0 ] || [ "$1" != "q" ]; then
    fn_start
fi


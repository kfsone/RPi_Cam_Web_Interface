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
  rpicamdirold=/$rpicamdirold
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

if [ -n "${rpicamdir}" ]; then
    rpicamdirEsc="\\/$rpicamdir"
    rpicamdir=/$rpicamdir
else
    rpicamdirEsc=""
fi


# Helper function to configure motion detection.
function fn_motion ()
{
    sudo sed -i "s/^; netcam_url.*/netcam_url/g" "${motionconf}"        
    sudo sed -i "s/^netcam_url.*/netcam_url http:\/\/localhost:$webport$rpicamdirEsc\/cam_pic.php/g" "${motionconf}"        
    if [ "$user" == "" ]; then
       sudo sed -i "s/^netcam_userpass.*/; netcam_userpass value/g" "${motionconf}"     
    else
       sudo sed -i "s/^; netcam_userpass.*/netcam_userpass/g" "${motionconf}"       
       sudo sed -i "s/^netcam_userpass.*/netcam_userpass $user:$webpasswd/g" "${motionconf}"        
    fi
    sudo sed -i "s/^; on_event_start.*/on_event_start/g" "${motionconf}"        
    sudo sed -i "s/^on_event_start.*/on_event_start echo -n \'1\' >\/var\/www$rpicamdirEsc\/FIFO1/g" "${motionconf}"        
    sudo sed -i "s/^; on_event_end.*/on_event_end/g" "${motionconf}"        
    sudo sed -i "s/^on_event_end.*/on_event_end echo -n \'0\' >\/var\/www$rpicamdirEsc\/FIFO1/g" "${motionconf}"        
    sudo sed -i "s/control_port.*/control_port 6642/g" "${motionconf}"      
    sudo sed -i "s/control_html_output.*/control_html_output off/g" "${motionconf}"     
    sudo sed -i "s/^output_pictures.*/output_pictures off/g" "${motionconf}"        
    sudo sed -i "s/^ffmpeg_output_movies on/ffmpeg_output_movies off/g" "${motionconf}"     
    sudo sed -i "s/^ffmpeg_cap_new on/ffmpeg_cap_new off/g" "${motionconf}"     
    sudo sed -i "s/^stream_port.*/stream_port 0/g" "${motionconf}"      
    sudo sed -i "s/^webcam_port.*/webcam_port 0/g" "${motionconf}"      
    sudo sed -i "s/^process_id_file/; process_id_file/g" "${motionconf}"
    sudo sed -i "s/^videodevice/; videodevice/g" "${motionconf}"
    sudo sed -i "s/^event_gap 60/event_gap 3/g" "${motionconf}"
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
mkdir -p /dev/shm/mjpeg
chown www-data:www-data /dev/shm/mjpeg
chmod 777 /dev/shm/mjpeg
sleep 4;su -c 'raspimjpeg > /dev/null 2>&1 &' www-data
if [ -e /etc/debian_version ]; then
    sleep 4;su -c 'php /var/www$rpicamdir/schedule.php > /dev/null 2>&1 &' www-data
else
    sleep 4;su -s '/bin/bash' -c 'php /var/www$rpicamdir/schedule.php > /dev/null 2>&1 &' www-data
fi
${RC_END}
EOF

        # Add our configuration prior to the 'exit 0' line in rc.local.
        sudo sed -i -e "/^exit [ ]*0/r ${tempFile}" "${autostartfile}"

        rm -f "${tempfile}"
    fi
}


##############################################################################
### Main
##############################################################################


# Stop the service if it's currently running.
fn_info "Stopping any running rpicam instance."
fn_stop

sudo mkdir -p /var/www$rpicamdir/media

# Move old material if changing from a different install folder
if [ ! "$rpicamdir" == "$rpicamdirold" ]; then
    fn_info "Moving old files to new install folder."

    if [ -e /var/www$rpicamdirold/index.php ]; then
        sudo mv /var/www$rpicamdirold/* /var/www$rpicamdir
    fi
fi

sudo cp -r www/* /var/www$rpicamdir/
if [ -e /var/www$rpicamdir/index.html ]; then
    sudo rm /var/www$rpicamdir/index.html
fi

if [ "$webserver" == "apache" ]; then
    fn_apache
elif [ "$webserver" == "nginx" ]; then
    fn_nginx
elif [ "$webserver" == "lighttpd" ]; then
    fn_lighttpd
fi

# Make sure user www-data has bash shell
sudo sed -i "s/^www-data:x.*/www-data:x:33:33:www-data:\/var\/www:\/bin\/bash/g" /etc/passwd

if [ ! -e /var/www$rpicamdir/FIFO ]; then
    sudo mknod /var/www$rpicamdir/FIFO p
fi
sudo chmod ugo=rw /var/www$rpicamdir/FIFO

if [ ! -e /var/www$rpicamdir/FIFO11 ]; then
    sudo mknod /var/www$rpicamdir/FIFO11 p
fi
sudo chmod ugo=rw /var/www$rpicamdir/FIFO11

if [ ! -e /var/www$rpicamdir/FIFO1 ]; then
    sudo mknod /var/www$rpicamdir/FIFO1 p
fi

sudo chmod ugo=rw /var/www$rpicamdir/FIFO1
sudo chmod u=rwx,go=rx /var/www$rpicamdir/raspizip.sh

if [ ! -d /dev/shm/mjpeg ]; then
    mkdir /dev/shm/mjpeg
fi

if [ "$jpglink" == "yes" ]; then
    if [ ! -e /var/www$rpicamdir/cam.jpg ]; then
       sudo ln -sf /dev/shm/mjpeg/cam.jpg /var/www$rpicamdir/cam.jpg
    fi
fi

if [ -e /var/www$rpicamdir/status_mjpeg.txt ]; then
    sudo rm /var/www$rpicamdir/status_mjpeg.txt
fi
if [ ! -e /dev/shm/mjpeg/status_mjpeg.txt ]; then
    echo -n 'halted' > /dev/shm/mjpeg/status_mjpeg.txt
fi
sudo chown www-data:www-data /dev/shm/mjpeg/status_mjpeg.txt
sudo ln -sf /dev/shm/mjpeg/status_mjpeg.txt /var/www$rpicamdir/status_mjpeg.txt

sudo chown -R www-data:www-data /var/www$rpicamdir
sudo cp etc/sudoers.d/RPI_Cam_Web_Interface /etc/sudoers.d/
sudo chmod ug=r /etc/sudoers.d/RPI_Cam_Web_Interface

sudo cp -r bin/raspimjpeg /opt/vc/bin/
sudo chmod u=rwx,go=rx /opt/vc/bin/raspimjpeg
if [ ! -e /usr/bin/raspimjpeg ]; then
    sudo ln -s /opt/vc/bin/raspimjpeg /usr/bin/raspimjpeg
fi

sed -e "s/www/www$rpicamdirEsc/" etc/raspimjpeg/raspimjpeg.1 > etc/raspimjpeg/raspimjpeg
if [[ `cat /proc/cmdline |awk -v RS=' ' -F= '/boardrev/ { print $2 }'` == "0x11" ]]; then
    sed -i 's/^camera_num 0/camera_num 1/g' etc/raspimjpeg/raspimjpeg
fi
if [ -e /etc/raspimjpeg ]; then
    fn_info "Your custom raspimjpg backed up at /etc/raspimjpeg.bak"
    sudo cp -r /etc/raspimjpeg /etc/raspimjpeg.bak
fi
sudo cp -r etc/raspimjpeg/raspimjpeg /etc/
sudo chmod u=rw,go=r /etc/raspimjpeg
if [ ! -e /var/www$rpicamdir/raspimjpeg ]; then
    sudo ln -s /etc/raspimjpeg /var/www$rpicamdir/raspimjpeg
fi

sudo usermod -a -G video www-data
if [ -e /var/www$rpicamdir/uconfig ]; then
    sudo chown www-data:www-data /var/www$rpicamdir/uconfig
fi

fn_info "Configuration motion detector."
fn_motion

fn_info "Configuring autostart [(${autostart})]."
fn_autostart

if [ -e /var/www$rpicamdir/uconfig ]; then
    sudo chown www-data:www-data /var/www$rpicamdir/uconfig
fi

if [ -e /var/www$rpicamdir/schedule.php ]; then
    sudo rm /var/www$rpicamdir/schedule.php
fi

sudo sed -e "s/www/www$rpicamdirEsc/g" www/schedule.php > www/schedule.php.1
sudo mv www/schedule.php.1 /var/www$rpicamdir/schedule.php
sudo chown www-data:www-data /var/www$rpicamdir/schedule.php

if [ $# -eq 0 ] || [ "$1" != "q" ]; then
    fn_start
fi

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
# This script updates the installer for the browser-interface to control the RPi Cam. It can be run
# on any Raspberry Pi with a newly installed raspbian and enabled camera-support.
# Based on RPI_Cam_WEb_Interface installer by Silvan Melchior
# Edited by jfarcher to work with github
# Edited by slabua to support custom installation folder
# Additions by btidey, miraaz, gigpi
# Split up and refactored by Bob Tidey 


# Bootstrap
cd $(dirname $(readlink -f $0))
source lib/common.shfrag
fn_enable_debug_log update.txt
fn_require_dialog


trap 'fn_abort' 0
set -e

fn_info "Getting commit hashes..."
remote=$(
 git ls-remote -h origin master |
 awk '{print $1}'
)
local=$(git rev-parse HEAD)

printf "Local : %s\nRemote: %s\n" $local $remote

if [[ $local == $remote ]]; then
    fn_feedback 2 "Update status" "Commits match: Nothing to update."
else
    fn_feedback 2 "Update status" "Commits don't match, performing update."
    git fetch origin master
    git reset --hard origin/master
    fn_feedback 2 "Update status" "Update finished."
fi
trap : 0

# We call updated install script passing through any quiet parameter
./install.sh $*

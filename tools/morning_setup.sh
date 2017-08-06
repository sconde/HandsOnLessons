#!/bin/sh -x

acct=ATPESC2017
nnodes=1
tl=20
cooley_username=mcmiller
localos=`uname`
linuxvnc=''
if [[ "$localos" == "Linux" ]]; then
    if [  -f /usr/bin/vncviewer ]; then
        linuxvnc=vncviewer
    #elif [  -f /usr/bin/vinagre ]; then
    #    linuxvnc=vinagre
    else
         echo "Please install vncviewer (from TigerVNC) and rerun the script"
         exit 1
    fi
fi

# Ensure ~/.ssh/config exists and has limited permissions
if [[ ! -e ~/.ssh/config ]]; then
    if [[ ! -e ~/.ssh ]]; then
        mkdir ~/.ssh
        chmod 700 ~/.ssh ~/.ssh/config
    fi
    touch ~/.ssh/config
    chmod 700 ~/.ssh/config
fi

#
# Append stuff to ~/.ssh/config for ssh control master to cooley
#
cat >> ~/.ssh/config << EOF
#added by NumericalPackagesHandsOn
Host cooley cooley.alcf.anl.gov
    User $cooley_username
    Compression yes
    ControlMaster auto
    ControlPersist 12h
    ControlPath ~/.ssh/cm_socket/%r@cooley.alcf.anl.gov:%p
EOF

#
# open login to cooley (will prompt) and put in bg and keep open all day
# This is the login that all others will use shared authentication with
#
ssh -N -f cooley.alcf.anl.gov 

#
# copy vnc dot files to cooley prompt for desired vnc password
#
ssh cooley "mkdir   ~/.vnc; cat > ~/.vnc/xstartup" << EOF
#!/bin/bash
#created by NumericalPackagesHandsOn
export DISPLAY=:0.0
export HANDSON=/projects/ATPESC2017/NumericalPackages/handson/
xterm &
twm
EOF
ssh cooley "chmod u+x ~/.vnc/xstartup"

ssh cooley "mkdir   ~/.vnc; cat >> ~/.soft.cooley" << EOF
#added by NumericalPackagesHandsOn
+gcc-4.8.1
EOF
#
# Get a temporary password from user and confirm its intended
#
while true; do
    read -p "Create temporary VNC Password: " pw
    echo "You have entered \"$pw\", is this correct?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break 2;;
        esac
    done
done
# Push the password to cooley and vncpasswd encode it
ssh cooley "rm -f ~/.vnc/passwd; echo $pw | vncpasswd -f > ~/.vnc/passwd; chmod 600 ~/.vnc/passwd"

#
# Reserve 3 nodes for interactive use all day
#
ssh -t -t -f cooley "qsub -I -n $nnodes -t $tl -A $acct" > ./qsub-interactive.out 2>&1 &

#
# Loop watching output from above to get allocation node name
#
nodid=""
while [[ -z "$nodid" ]] ; do
    echo "Checking for allocation completion"
    nodid=$(cat ./qsub-interactive.out | tr ' ' '\n' | grep cc[0-9][0-9][0-9].cooley | cut -d'.' -f1)
    sleep 5
done
echo "Got allocation at $nodid"

#
# Startup xvncserver on the allocation
#
ssh cooley "nohup ssh $nodid x0vncserver --display=:0.0 --NeverShared=1 --geometry=2400x1500+0+0 --PasswordFile=/home/$cooley_username/.vnc/passwd --MaxProcessorUsage=100 >& /dev/null &"
sleep 5 

#
# Set up 2-hop ssh tunnel to allocation, (above) through login and run xstartup there
#
ssh -f -L 22590:$nodid:5900 cooley "nohup ssh $nodid ~/.vnc/xstartup >& /dev/null &"
sleep 5 

#
# finally, start the vnc client on local machine
#
if [[ "$localos" == Darwin ]]; then
    open vnc://localhost:22590
elif [[ "$localos" == Linux ]]; then
    $linuxvnc localhost::22590
elif [[ "$localos" == windows ]]; then
    echo "not implemented"
fi

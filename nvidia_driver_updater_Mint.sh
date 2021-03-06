#!/bin/bash

usage() {
         echo "Usage: $0 [-u|--uninstall] [-h|--help]"
         echo
         echo "-u, --uninstall		undo everything this script does"
         echo "-h, --help		display this usage guide"
}

#Undoes everything the script does
uninstall() {
	[ -e /usr/src/nvidia/nvidia_update.sh ] && sudo rm /usr/src/nvidia/nvidia_update.sh
	[ -e /etc/kernel/postinst.d/nvidia ] && sudo rm /etc/kernel/postinst.d/nvidia
	#Will only delete /etc/kernel/* if it's empty which it will be if the user added no
	#extra scripts to the directory
	[ -d /etc/kernel/postinst.d/ ] && sudo rmdir /etc/kernel/postinst.d 2>/dev/null
	[ -d /etc/kernel/ ] && sudo rmdir /etc/kernel 2>/dev/null

	#Delete rc.local changes
	sudo sed -i --follow-symlinks '/chvt/d' /etc/rc.local

	#Delete the actual nvidia driver that was downloaded from the nvidia website
	if [ -e /usr/src/nvidia/nvidia-driver ]
	then
		echo -n "Do you want to remove the NVIDIA driver that you downloaded and renamed (/usr/src/nvidia/nvidia-driver)? [Y/n]: " | fmt -w `tput cols`
		read answer
	
		case "$answer" in
			""|y|Y)
			echo "Removing /usr/src/nvidia/nvidia-driver"
			sudo rm /usr/src/nvidia/nvidia-driver
			;;
			*)
			echo "You chose NOT to remove /usr/src/nvidia/nvidia-driver. If you want to do so manually in the future, you can safely remove /usr/src/nvidia, as this is a folder this script created." | fmt -w `tput cols`
			DNR='true'
			;;
		esac
	fi

	#If the driver was removed, delete the /usr/src/nvidia folder that this script created
	if [[ "$DNR" != "true" ]]
	then
		[ -d /usr/src/nvidia ] && sudo rmdir /usr/src/nvidia 2>/dev/null
	fi

	echo
	echo "Uninstall complete"
}

#Check number of arguments
if [[ "$#" -gt 1 ]]
then
	usage
	exit 1
fi

#Check options
case "$1" in
	"")
	;;
	--uninstall|-u)
	uninstall
	exit 0
	;;
	--help|-h)
	usage
	exit 0
	;;
	*)
	echo "Unknown argument: $1"
	usage
	exit 1
	;;
esac


clear
[ ! -d /usr/src/nvidia/ ] && sudo mkdir /usr/src/nvidia/

[ -e /usr/src/nvidia/nvidia-driver ] || { echo 'You must first download the right NVIDIA driver from http://www.nvidia.com/Download/index.aspx. It will be named something similar to "NVIDIA-Linux-x86_64-319.17.run". Rename the file to "nvidia-driver" and move it to /usr/src/nvidia/. Once you have done this, run this script again. There is no need to keep this file up to date since the script will download the newest version of it from the NVIDIA website if it is outdated.' | fmt -w `tput cols`; exit 1; }

sudo chmod a+x /usr/src/nvidia/nvidia-driver

#The actual update script
(
cat << 'nvidia_update'
#!/bin/bash

#The --update arg downloads the latest version of the driver from NVIDIA
#if this one is outdated
/usr/src/nvidia/nvidia-driver --update

#Undo tty2.conf changes
TTY_CONF=/etc/init/tty2.conf.orig
if [[ -e $TTY_CONF ]]
then
        rm ${TTY_CONF%.orig}
        mv ${TTY_CONF} ${TTY_CONF%.orig}
fi

#Delete rc.local changes
sed -i --follow-symlinks '/chvt/d' /etc/rc.local

#Reboot
echo -n "Do you want to reboot? [Y/n]: " | fmt -w `tput cols`
read answer
	
case "$answer" in
	""|y|Y)
	reboot
	;;
	*)
	/bin/chvt 1
	;;
esac
nvidia_update
) | sudo tee /usr/src/nvidia/nvidia_update.sh >/dev/null

sudo chmod a+x /usr/src/nvidia/nvidia_update.sh

#The /etc/kernel/postinst.d/ directory contains scripts that automatically get run
#immediately after a new kernel has been installed
sudo mkdir -p /etc/kernel/postinst.d/

(
cat << 'postinst'
#!/bin/bash
#Delete 'exit 0' from rc.local for a second
#Its easier to delete exit 0 temporarily than to try to paste text above it
grep -q 'exit 0' /etc/rc.local && sed -i --follow-symlinks '/exit 0/d' /etc/rc.local
#Make OS switch to tty2 on boot. tty2 is where the nvidia driver will be installed from
#The "sleep 5" bit is necessary because lightdm tries to switch to tty7 at about the same time
#so rc.local just makes sure that its the last one to switch
echo '{ /bin/sleep 5; /bin/chvt 2; } &' >> /etc/rc.local
#Restore 'exit 0' to rc.local
echo 'exit 0' >> /etc/rc.local
#Modify tty2.conf to run the nvidia_update.sh script instead of asking for login credentials
sed -i.orig -e 's/respawn/#respawn/g' -e 's/\(exec.*\)/#\1/g' /etc/init/tty2.conf
echo 'exec /sbin/getty -8 38400 tty2 -n -l /usr/src/nvidia/nvidia_update.sh' >> /etc/init/tty2.conf
postinst
) | sudo tee /etc/kernel/postinst.d/nvidia >/dev/null

sudo chmod a+x /etc/kernel/postinst.d/nvidia

echo "Installation complete. The next time your kernel updates, as soon as you reboot, the latest nvidia driver will be downloaded and installed." | fmt -w `tput cols`

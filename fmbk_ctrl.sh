#!/usr/bin/env sh

#####       fmbk_ctrl.sh            #####
# FarmBook sensor node control utility  #
# author: Lin, Cheng-Tao (mutolisp)     #
# email: mutolisp@gmail.com             #
# 2014-10-15                            #
# 2015-01-12 revised                    #
#####                               #####


# platform: linino (openWRT)
# variables
FMBKBIN=/root
SD=/mnt/sda1
UPLOADER=${SD}/bin/dropbox_uploader.sh
DATE=`date '+%Y%m%d'`
TIME=`date '+%H%M%S'`
# generate uniq md5 value to identify node 
# and only get the first 8 characters
MD5=md5sum
SENSRID=`/sbin/ifconfig eth0  | grep HWaddr | awk -F' ' '{print $5}' | ${MD5} | cut -c 1-8`
SENSRLOG=sht_gy30_log.csv
UPLOADER_CONF_URL="https://www.dropbox.com/s/pp5vmbrlicndn7t/dropbox_uploader.conf?dl=0"
DROPBOX_UPLOADER="https://raw.githubusercontent.com/mutolisp/Dropbox-Uploader/master/dropbox_uploader.sh"
DBUPCONF=/root/.dropbox_uploader
FMBKCTRL="https://www.dropbox.com/s/oqydxgoopbiak44/fmbk_ctrl.sh?dl=0"
WAKESETTINGS="https://www.dropbox.com/s/74c76spu3yordg0/change.txt?dl=0"

##### Functions ########
enable_wifi() {
        # check the connection, use curl to connect google page, if !HTTP1.1 302 Found,
        # try for maximum 5 times
        for i in $(seq 5);
        do
            WELT=`curl -s -I http://www.google.com | head -n1 |cut -d$' ' -f2`
            if [[ "${WELT}" != "302" ]]; then
                # turn on wifi and wait for 10 seconds
                wifi down && sleep 1
                wifi up && sleep 10;
            else
                #echo "(`date '+%Y-%m-%d %H:%M:%S %Z'`) Step 0 WIFI connected!" >> ${SD}/${SENSRID}-fmbk_ctrl.log
                WIFISTATUS="1"
                break
            fi
            if [[ "${i}" == "5"  ]]; then
                #echo "(`date '+%Y-%m-%d %H:%M:%S %Z'`) Step 0 WIFI connection error!" >> ${SD}/${SENSRID}-fmbk_ctrl.log
                WIFISTATUS="0"
            fi
        done 
        echo ${WIFISTATUS} > /tmp/wifi-status
}

system_conf() {
    SYSTEMCONF=/etc/config/system
cat > ${SYSTEMCONF} << _EOF
config system
    option timezone_desc 'Rest of the World (UTC)'
    option hostname 'Fmbk${SENSRID}'
    option zonename 'Asia/Taipei'
    option timezone 'CST-8'
    option conloglevel '8'
    option cronloglevel '8'

config timeserver 'ntp'
    list server '0.openwrt.pool.ntp.org'
    list server '1.openwrt.pool.ntp.org'
    list server '2.openwrt.pool.ntp.org'
    list server '3.openwrt.pool.ntp.org'
_EOF
}

snapshot() {
        if [ -d ${SD}/${SENSRID}/${DATE} ]; then
            echo "${SD}/${SENSRID}/${DATE} exists, and I will store photos here." >> ${SD}/${SENSRID}/fmbk_ctrl.log
        else 
            echo "Creating ${SD}/${SENSRID}/${DATE} directory..." >> ${SD}/${SENSRID}/fmbk_ctrl.log
            mkdir -p ${SD}/${SENSRID}/${DATE}
        fi 
        resolution=1280x720
        video=/dev/video0
        priority=19
        nice -n ${priority} fswebcam ${SD}/${SENSRID}/${DATE}/`date +%Y%m%d_%H%M%S`.jpg -D 3 -r ${resolution} -d ${video} --no-banner
        echo "(`date '+%Y%m%d_%H:%M:%S_%Z'`) Taking snapshot" >> ${SD}/${SENSRID}/fmbk_ctrl.log
        #nice -n ${priority} mjpg_streamer -i "input_uvc.so -d /dev/video0 -r ${resolution} -q 85 -f 1" -o "output_file.so -s 1 -f ${SD}/photos/${DATE}" &
        #sleep 5 &&
        #kill `pidof mjpg_streamer`
}

db_uploader_check() {

        # check the API key file first before upload files
        # if the .dropbox_uploader does not exist or the file size is zero, download it from
        # the internet
        if [ ! -f /root/.dropbox_uploader -o ! -s /root/.dropbox_uploader ] ; then
            if [ ! -f ${SD}/bin/.dropbox_uploader ] ; then
                curl -s -k -L ${UPLOADER_CONF_URL} > /tmp/.dropbox_uploader
                cp -f /tmp/.dropbox_uploader /root/.dropbox_uploader
                cp -f /tmp/.dropbox_uploader ${SD}/bin/.dropbox_uploader
            else
                cp -f ${SD}/bin/.dropbox_uploader /root/.dropbox_uploader
            fi
        fi
}

update_ctrl() {
        # get dropbox_uploader.sh
        #echo "Downloading dropbox_uploader ..."
        #if [ ! -f ${UPLOADER} -o -s  ${UPLOADER} ]; then
        #    curl -s -k -L ${DROPBOX_UPLOADER} > /tmp/dropbox_uploader.sh &&
        #    cp -f /tmp/dropbox_uploader.sh ${UPLOADER} &&
        #    chmod +x ${UPLOADER}
        #fi
        #if [ ! -L /usr/bin/dropbox_uploader.sh ]; then 
        #   ln -s ${UPLOADER} /usr/bin/dropbox_uploader.sh | tee -a ${SD}/debug20120225.log
        #fi

        echo "Downloading fmbk_ctrl.sh ..."
        curl -s -k -L ${FMBKCTRL} > ${SD}/bin/fmbk_ctrl.sh_new &&
        cp -f ${SD}/bin/fmbk_ctrl.sh_new ${SD}/bin/fmbk_ctrl.sh &&
        chmod +x ${SD}/bin/fmbk_ctrl.sh
        cp ${SD}/bin/fmbk_ctrl.sh /root/fmbk_ctrl.sh
        if [ ! -L /usr/bin/fmbk_ctrl.sh ]; then 
            ln -s /root/fmbk_ctrl.sh /usr/bin/fmbk_ctrl.sh | tee -a ${SD}/debug20120225.log
        fi 

        # Update wakeup time tables 
        echo "Downloading wakeuptime.txt ..."
        curl -s -k -L ${WAKESETTINGS} > /mnt/sda1/change.txt | tee -a ${SD}/debug20120225.log

        echo "(`date '+%Y-%m-%d %H:%M:%S'`) Step 1. Update required scripts (dropbox_uploader, fmbk_ctrl, wakeuptime)" >> ${SD}/${SENSRID}/fmbk_ctrl.log
}

##### Main process #####
case $1 in
    "init")
        ################## 0 Setup WIFI interface ############################
        # setup timezone and sensor node name 
        system_conf | tee -a ${SD}/debug20120225.log

        # setup wifi ssid/password
        # [TBD] /etc/conf/wireless
        WIFICONF=/etc/config/wireless
        # grep the beginning line number of wifi-iface (wifi interface)
        # The original wireless config file setup wifi interface as AP mode.
        # If so, change it to client mode
        if [ `cat ${WIFICONF} | grep \'ap\' | wc -l` == 1 ]; then 
            WIFILNUM=`awk '/wifi-iface/ { print NR-1 }' ${WIFICONF}`
            cp -r ${WIFICONF} ${WIFICONF}.orig
            awk -v lnum=${WIFILNUM} 'NR<=lnum' ${WIFICONF}.orig > ${WIFICONF}
        # setup the new wifi client mode 
cat >> ${WIFICONF} << _EOF
config wifi-iface
     option device 'radio0'
     option network lan
     option mode 'sta'
     option ssid 'Farmbook'
     option encryption 'psk2'
     option key '1234567890'
_EOF

        fi
        # check for network config file
        NETCONF=/etc/config/network
        if [ `grep "option ipaddr '192.168.240.1'" ${NETCONF} | wc -l` == 1 ]; then
            NETLNUM=`awk '/lan/ { print NR}' ${NETCONF}`
            NETWLNUM=`awk '/wan/ { print NR}' ${NETCONF}`
            cp -r ${NETCONF} ${NETCONF}.orig
            awk -v lan=${NETLNUM} -v wan=${NETWLNUM} 'NR<lan || NR >=wan' ${NETCONF}.orig > ${NETCONF}

            echo "config interface 'lan'" >> ${NETCONF}
            echo "    option proto 'dhcp'" >> ${NETCONF}
            echo "(`date '+%Y-%m-%d %H:%M:%S'`) configure network" >> ${SD}/debug20120225.log
            
        fi
        
        # check wifi connectivity
        enable_wifi
        echo "(`date '+%Y-%m-%d %H:%M:%S'`) check wifi availability" >> ${SD}/debug20120225.log

        # wait 20 seconds for NTP 
        sleep 20

        ################## 1 Setup dropbox uploader ######
        # setup dropbox API KEY authentication
        ##################################################

        db_uploader_check

        echo "(`date '+%Y-%m-%d %H:%M:%S'`) Step 0.1 Write dropbox API Key to /root/.dropbox_uploader" >> ${SD}/${SENSRID}/fmbk_ctrl.log
        echo "(`date '+%Y-%m-%d %H:%M:%S'`) write dropbox_uploader api key" >> ${SD}/debug20120225.log

        # create sensor id directory to save sensoring logs and photos
        if [ ! -d ${SD}/${SENSRID} ]; then
            mkdir -p ${SD}/${SENSRID}
        fi


        ################## 2 Get required script #########
        # dependency: coreutils-stat
        ##################################################

        if [ ! -d ${SD}/bin ]; then
            mkdir -p ${SD}/bin
            echo "(`date '+%Y-%m-%d %H:%M:%S'`) mkdir ${SD}/bin" >> ${SD}/debug20120225.log
        fi
        # update fmbk_ctrl.sh script
        update_ctrl
        echo "(`date '+%Y-%m-%d %H:%M:%S'`) update fmbk_ctrl.sh script" >> ${SD}/debug20120225.log

        ################## 3 Update/install opkg  ########
        # install required packages
        ##################################################

        opkg update &&
        installed_pkgs="kmod-video-uvc\|coreutils-stat\|v4l-utils\|bash\|fswebcam"
        if [[ `opkg list-installed | grep ${installed_pkgs} | wc -l` != 5 ]]; then
            opkg install kmod-video-uvc coreutils-stat v4l-utils bash fswebcam &&
            echo "(`date '+%Y-%m-%d %H:%M:%S'`) Step 2. Install required software done (via opkg)" >> ${SD}/${SENSRID}/fmbk_ctrl.log
            echo "(`date '+%Y-%m-%d %H:%M:%S'`) install/upgrade required packages" >> ${SD}/debug20120225.log
        fi
        sleep 1
        snapshot | tee -a ${SD}/debug20120225.log
        echo "(`date '+%Y-%m-%d %H:%M:%S'`) taking photo" >> ${SD}/debug20120225.log
        ;;

    "upload")
        # prepare for upload temporary (up-temp) directory
        if [ ! -d ${SD}/tmp_upload/${DATE} ]; then
            mkdir -p ${SD}/tmp_upload/${DATE} | tee -a ${SD}/debug20120225.log
            echo "(`date '+%Y-%m-%d %H:%M:%S'`) mkdir -p ${SD}/tmp_upload/${DATE}" >> ${SD}/debug20120225.log
        fi
        # copy photos and sensoring data into up-temp directory
        cp -rf ${SD}/${SENSRID}/${DATE} ${SD}/tmp_upload/ | tee -a ${SD}/debug20120225.log
        echo "cp -rf ${SD}/${SENSRID}/${DATE} ${SD}/tmp_upload/"
        cp -rf ${SD}/sht_gy30_log.csv ${SD}/tmp_upload/${DATE}/${DATE}${TIME}.csv | tee -a ${SD}/debug20120225.log
        echo "cp -rf ${SD}/sht_gy30_log.csv ${SD}/tmp_upload/${DATE}/${DATE}${TIME}.csv"
        # backup original file
        cp -f ${SD}/sht_gy30_log.csv ${SD}/sht_gy30_log${DATE}${TIME}.csv.bak | tee -a ${SD}/debug20120225.log
        # cleanup the original log file
        :> ${SD}/sht_gy30_log.csv | tee -a ${SD}/debug20120225.log

        # if wifi-status == 1, upload all the sensoring data and fmbk_ctrl.log (controller log)
        if [[ `grep 1 /tmp/wifi-status` == 1 ]]; then
            db_uploader_check &&
            ${UPLOADER} -f ${DBUPCONF} -k -s mkdir ${SENSRID}/${DATE} | tee -a ${SD}/debug20120225.log
            ${UPLOADER} -f ${DBUPCONF} -k upload ${SD}/${SENSRID}/fmbk_ctrl.log ${SENSRID}/${DATE}/fmbk_ctrl.log | tee -a ${SD}/debug20120225.log
            for i in `ls ${SD}/tmp_upload/${DATE}/`
            do
				# Bill Modified 2015/04/12
				# filter ${i} is a not-zero size file
				if [ -s ${SD}/tmp_upload/${DATE}/${i} ];then  
					${UPLOADER} -f ${DBUPCONF} -k -s upload ${SD}/tmp_upload/${DATE}/${i} ${SENSRID}/${DATE}/${i} | tee -a ${SD}/debug20120225.log
					echo "(`date '+%Y-%m-%d %H:%M:%S'`) upload ${SD}/tmp_upload/${DATE}/${i}" >> ${SD}/debug20120225.log
				fi
            done &&
            rm -fr ${SD}/tmp_upload/*
            sleep 5 
        fi
        ;;

    *)
        echo "Usage: fmbk_ctrl.sh {init|upload}"
        echo ""
        echo "init: initializing parameters"
        echo "(0) Connect WiFi"
        echo "(1) Update control script"
        echo "(2) update dropbox_uploader"
        echo ""
        echo "upload: upload data to dropbox"
        exit
        ;;
esac

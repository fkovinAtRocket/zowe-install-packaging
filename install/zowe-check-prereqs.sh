#!/bin/sh
# Verify that the Zowe pre-reqs are in place before you install Zowe on z/OS
# Note:  This script does not change anything on your system.

# Testing:  You must set these variables before you run this script:
# INSTALL_DIR=/u/tstradm/zowe/zowe-0.9.0       # this is the test location for testing this script on MV3B.  Remove this line before shipping.  

# Run this script AFTER you un-PAX the Zowe PAX file.

# Assume this script is invoked from the 'install' directory.  
#
#  This script may invoke others later, e.g.  giza-packaging/Zoeinstall/verify*.sh

echo Script zowe-check-prereqs.sh started

# This script is expected to be located in 'install' directory
# otherwise you must set INSTALL_DIR to the Zowe install directory before you run this script
# e.g. export INSTALL_DIR=/u/tstradm/zowe/zowe-0.9.0/install

if [[ -n "${INSTALL_DIR}" ]]
then 
    echo Info: INSTALL_DIR environment variable is set to ${INSTALL_DIR}
else 
    echo Info: INSTALL_DIR environment variable is empty
    if [[ `basename $PWD` != install ]]
    then
        echo Warning: You are not in the \'install\' directory
        echo Warning: '${INSTALL_DIR} is not set'
        echo Warning: '${INSTALL_DIR} must be set to the Zowe install directory'
        echo Warning: script will run, but with errors
    else
        INSTALL_DIR=`pwd`
        echo Info: INSTALL_DIR environment variable is now set to ${INSTALL_DIR}
    fi    
fi

echo
echo Check entries in the install directory
instdirOK=1
for dir in files install licenses scripts
do
  ls ${INSTALL_DIR}/../$dir >/dev/null
  if [[ $? -ne 0 ]]
  then
    echo Error: directory \"$dir\" not found in ${INSTALL_DIR}/..
    instdirOK=0
  fi
done
if [[ $instdirOK -eq 1 ]]
then
  echo OK
fi

# The user running this script requires certain basic privileges to list the resources that are to be checked.

echo
echo Check user has the basic auth to list the resources
basicauthOK=1
msg=`tsocmd lu izusvr 2>/dev/null | head -1`

case $msg in
UNABLE\ TO\ LOCATE\ USER\ *) 
  echo Error:  User IZUSVR is not defined 
  echo Warning: IZUADMIN, IZUGUEST and IZUUNGRP will not be checked as a result
  basicauthOK=0
;;

NOT\ AUTHORIZED\ TO\ LIST\ *) 
  echo Info:  User IZUSVR is defined but you are not authorized to list it
  echo Warning: IZUADMIN, IZUGUEST and IZUUNGRP will not be checked as a result   
;;

USER=IZUSVR\ *) 
  # echo OK:  User IZUSVR is defined and you are authorized to list it  

  echo
  echo Check RACF or other SAF security settings are correct
  tsocmd lg izuadmin 2>/dev/null |grep IZUSVR >/dev/null
  if [[ $? -ne 0 ]]
  then
    echo Error: user IZUSVR is not in group IZUADMIN
    basicauthOK=0
  fi

  echo
  echo Check IZUGUEST
  tsocmd lg izuungrp 2>/dev/null |grep IZUGUEST >/dev/null
  if [[ $? -ne 0 ]]
  then
    echo Error: user IZUGUEST is not in group IZUUNGRP
    basicauthOK=0 
  fi

;;

*) 
  echo Error:  Unexpected response to RACF LISTUSER command
  echo $msg
  basicauthOK=0
esac
if [[ $basicauthOK -eq 1 ]]
then 
  echo OK
fi


echo
echo Is opercmd available?
${INSTALL_DIR}/../scripts/opercmd "d t" 1> /dev/null 2> /dev/null  # is 'opercmd' available and working?
if [[ $? -ne 0 ]]
then
  echo Error: Unable to run opercmd REXX exec from # >> $LOG_FILE
  ls -l ${INSTALL_DIR}/../scripts/opercmd # try to list opercmd
  echo Warning: z/OS release will not be checked
else
# use opercmd

  echo
  echo OK: opercmd is available
  echo
  echo Check z/OS RELEASE
  release=`${INSTALL_DIR}/../scripts/opercmd 'd iplinfo'|grep RELEASE`
  # the selected line will look like this ...
  # RELEASE z/OS 02.03.00    LICENSE = z/OS
  
  vrm=`echo $release | sed 's+.*RELEASE z/OS \(........\).*+\1+'`
  echo release of z/OS is $release
  if [[ $vrm < "02.02.00" ]]
        then echo Error: version $vrm not supported
        else echo OK: version $vrm is supported
  fi
  
fi

# z/OSMF and other pre-req jobs are up and running
# z/OS V2R2 with PTF UI46658 or z/OS V2R3, 

# z/OS UNIX System Services enabled, and 
# Integrated Cryptographic Service Facility (ICSF) configured and started.


echo
echo Check install user is a member of the IZUADMIN group

# get list of groups this user is in
echo "Installer's TSO userid:"
userid=`tsocmd lu 2>/dev/null |sed -n 's/.*USER=\([^ ]*\) *NAME=.*/\1/p'`
echo $userid

echo "installer's group(s):"
tsocmd lu 2>/dev/null |sed -n 's/.*GROUP=\([^ ]*\) *AUTH=.*/\1/p' | grep "^IZUADMIN$"
if [[ $? -ne 0 ]]
then
  echo Error:  User $userid is not a member of the IZUADMIN group
else  
  echo OK
fi



# 1- RDEFINE OPERCMDS MVS.START.** UACC(NONE)
# 2- PERMIT MVS.START.** CLASS(OPERCMDS) ACC(UPDATE) ID(IBMUSER)
# 3- SETR GENERIC(OPERCMDS) RACLIST(OPERCMDS) REFRESH


match_profile ()
{
  className=$1    # the CLASS containing all the profiles that user can access
  profileName=$2  # the profile that we want to match in that list
  tsocmd "search class($className) user($userid)" 2> /dev/null |sed 's/\(.*\) .*/\1/' > /tmp/find_profile.out
  while read string 
  do
    
    l=$((`echo $profileName | wc -c`))  # length of profile we're looking for, including null terminator
    i=1
    while [[ $i -lt $l ]]
    do
        r=`echo $string       | cut -c $i,$i` # ith char from RACF definition
        p=`echo $profileName  | cut -c $i,$i` # ith char from profile we're looking for

        if [[ $r = '*' ]]
        then
          rm        /tmp/find_profile.out
          return 0  # asterisk matches rest of string
        fi

        if [[ $r != $p ]]
        then
          break   # mismatch char for this profile, try next
        fi

        i=$((i+1))
    done

    if [[ $i -eq $l ]]
    then
      rm        /tmp/find_profile.out
      return 0  # whole string matched
    fi


  done <    /tmp/find_profile.out
  rm        /tmp/find_profile.out
  return 1    # no strings matched
}

echo
echo Check user can issue START/STOP commands

startstopOK=1
for profile in "MVS.START.STC" "MVS.STOP.STC"
do
  match_profile "OPERCMDS" $profile
  if [[ $? -eq 0 ]]
  then
    : # echo OK: User $userid is authorized to use OPERCMDS $profile
  else 
    echo Error: User $userid is not authorized to use OPERCMDS $profile
    startstopOK=0
  fi
done
if [[ $startstopOK -eq 1 ]]
then 
  echo OK
fi 

echo
echo Check user can issue SDSF commands
# Check ISF access:
# Here are the latest set of TSO commands to resolve the issue: 
# 1- RDEFINE SDSF  ISF*.** UACC(NONE)
# 2- PERMIT  ISF*.** CLASS(SDSF) ACC(READ) ID(IBMUSER)
# 3- SETR GENERIC(SDSF) RACLIST(SDSF) REFRESH 

sdsfOK=1
for profile in "ISF.CONNECT" "ISFATTR" "ISFCMD.ODSP" "ISFOPER"
do
  match_profile "SDSF" $profile
  if [[ $? -eq 0 ]]
  then
    : # echo OK: User $userid is authorized to use SDSF $profile
  else 
    echo Info: User $userid is not authorized to use SDSF $profile
    sdsfOK=0
  fi
done

if [[ $sdsfOK -eq 1 ]]
then 
  echo OK
fi 



echo
echo Check user is authorized to set -a extattr APF and -p program control bits 

extrattrOK=1
for profile in "BPX.FILEATTR.APF" "BPX.FILEATTR.PROGCTL"
do
  match_profile "FACILITY" $profile
  if [[ $? -eq 0 ]]
  then
    : # echo OK: User $userid is authorized to use $profile
  else 
    echo Error: User $userid is not authorized to use $profile
    extrattrOK=0
  fi
done
if [[ $extrattrOK -eq 1 ]]
then 
  echo OK
fi

# 3. Ports are available
echo
echo Check the ports in the yaml file are not already in use
portList=`sed -n 's/.*\(Port=\)\([0-9]*\)/\2/p' ${INSTALL_DIR}/zowe-install.yaml`
portsOK=1
for port in $portList 
do
if [[ $port -ne 22 && $port -ne 23 ]]
then
  tsocmd netstat 2>/dev/null | grep "Local Socket:   ::\.\.${port} *$" >/dev/null
  if [[ $? -eq 0 ]]
  then
    echo Error: port $port is already in use
    portsOK=0
  else  
    : # echo OK: port $port is not in use
  fi
fi
done
if [[ $portsOK -eq 1 ]]
then 
  echo OK
fi

# 4. z/OSMF 
    # 4.1 servers are up 
    # checkJob  IZUANG1
    # checkJob  IZUSVR1
    # checkJob  AXR
    # checkJob  CEA       # the CIM server
    # checkJob  ICSF      # it might be this name on a real system
    # checkJob  CSF       # OR it might be this name on a zD&T system
    # checkJob  RACF      # OR another security product


    # 4.2 Jobs with JCT
echo
echo Check z/OSMF servers are up

zosmfOK=1

for jobname in IZUANG1 IZUSVR1 # RACF
do
  tsocmd status ${jobname} 2>/dev/null | grep "JOB ${jobname}(S.*[0-9]*) EXECUTING" >/dev/null
  if [[ $? -eq 0 ]]
  then 
      : # echo OK: Job ${jobname} is executing

  else 
      echo Error: Job ${jobname} is not executing
      zosmfOK=0
  fi
done
if [[ $zosmfOK -eq 1 ]]
then 
  echo OK
fi
    
# 9. z/OSMF    

# --- this section is TBD ------
# IEFC001I PROCEDURE IZUSVR1 WAS EXPANDED USING SYSTEM LIBRARY ADCD.Z23B.PROCLIB

    # 4.2  Ability to to send HTTP requests to zOSMF with X-CSRF-ZOSMF-HEADER.
    # When trying to call zOSMF such as using the URL:
    # https://aquagiza21.fyre.ibm.com:10443/zosmf/restfiles/ds?dslevel=tstradm

# https://9.20.65.202:10443/zosmf/info  on ukzowe1
# https://9.20.65.202:10443/zosmf/restjobs/jobs (you need to log in)

# IEE252I MEMBER IZUPRM00 FOUND IN ADCD.Z23B.PARMLIB
# CSRF_SWITCH(OFF) 


echo
echo Check z/OSMF ltpa.keys file is readable

if [[ -n "${ZOWE_ZOSMF_PATH}" ]]
then 
    : # echo warning: ZOWE_ZOSMF_PATH is already set to ${ZOWE_ZOSMF_PATH} 
else
    ZOWE_ZOSMF_PATH="/var/zosmf/configuration/servers/zosmfServer/"   # this won't normally be set until Zowe is configured
fi    

ls -l ${ZOWE_ZOSMF_PATH}/resources/security/ltpa.keys | grep "^-r.* IZUSVR *IZUADMIN .*ltpa.keys$" >/dev/null
if [[ $? -ne 0 ]]
then
  echo z/OSMF ltpa.keys file is not readable and owned by IZUSVR in group IZUADMIN
else
  echo OK
fi


# 7. Check interface name specified in /zaas1/scripts/ipupdate.sh ?
# 8. /u/tstradm/.profile file exists

echo
echo Check Node version

# 9.1. Node is installed and working
# IBM SDK for Node.js z/OS Version 6.11.2 or later.
nodeVersion=`node --version`
if [[ $? -ne 0 ]]
then
  # node version error

  echo $nodeVersion | grep 'not found'
  if [[ $? -eq 0 ]]   # this test is wrong.
  then 
    # echo node not found in your path ... trying standard location
    nodelink=`ls -l /usr/lpp/IBM/cnj/IBM/node-*|grep ^l`  # is there a node symlink in this list?
    if [[ $? -eq 0 ]]
    then 
        # echo symlink to node found 
        nodeTarget=`echo $nodelink | sed 's+.*/usr\(.*\) ->.*+\1+'`   # get target of symlink
        nodeVersion=`/usr/${nodeTarget}/bin/node --version`
        if [[ $? -ne 0 ]]
        then
          nodeVersion=    # set it to empty string
        
        fi

    fi  
  else
    # the error was not just "not found"
     nodeVersion=    # set it to empty string 
  fi
fi


# echo node version is \"$nodeVersion\"

if [[ -n "${nodeVersion}" ]]
then 
    # nodeVersion is not empty 
    if [[ "$nodeVersion" < "v6.11" ]]
          then 
            echo Error: node version $nodeVersion is less than minimum level required
          else 
            echo OK # : node version $nodeVersion is at least the minimum level required
    fi
else
    echo Error: can not determine node version
fi


# 9.2 Java installed and right version
# IBM Java Version 1.8 or later.
# /java/java80_64/J8.0_64/bin/java
# it might be here ... ls /*
# /usr/lpp/java/current_64
# /usr/lpp/java/current_64/bin/java -version   # on zD&T
echo
echo Check Java version
java -version 1>/dev/null 2>/dev/null
if [[ $? -ne 0 ]]
then
  echo Error: failed to find java 
else
  response=`java -version 2>&1 | grep ^"java version"`
  if [[ $? -ne 0 ]]
  then
    echo Error: failed to find java version number
  else
    if [[ "$response" < "java version \"1.8" ]]
    then 
      echo Error: $response is less than minimum level required
    else 
      echo OK # $response is at least the minimum level required
    fi
  fi
fi


# C:\GIZA\giza-packaging\ZoeInstall>

# - external scripts, in preparation:
# checkConfig.sh
# checkPorts.sh


# verifyConfig.sh
# # verifyhttpserver.jstemplate
# # verifyhttpsserver.jstemplate
# verifyptfs.sh
# verifyZoe.sh
# # verifyzosmf.jstemplate
# verifyzosmf.sh
# verifyzosmfaccess.sh

# print out the state of all the CEE_RUNOPTS 

echo
echo Checking CEE_RUNOPTS

set | grep _CEE_RUNOPTS
echo 

# also the LDA can be used to confirm both REGION choices 
# and the effects of any IEFUSI exits. 
    # LDA is found using DDLIST, an ISPF command dialog, which is not directly runnable from a shell script.
    # Or use REXX.
    # http://www.askthezoslady.com/tso-region-size-really-means/
    # Either way, not a 1-line command.  
    # z/OSMF IZUSVR1 sets MEMLIMIT=6G on the PGM=BPXBATSL  statement

echo
echo Check the USS AUTOCVT

${INSTALL_DIR}/../scripts/opercmd "D OMVS,o" | grep "AUTOCVT *= OFF" > /dev/null
if [[ $? -ne 0 ]]
then
  echo Warning:  OMVS AUTOCVT is not set to OFF.  Files may appear in wrong code page.
else
  echo OK:  OMVS AUTOCVT is set to OFF
fi


# Some cheap validations can be included in the startup itself 
# which can be nice to catch config changes 
# (and those customers that didn’t run the validation…)


echo
echo Script zowe-check-prereqs.sh ended



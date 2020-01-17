#!/bin/bash

# ----------------------------------------------------------------------------
#
# knsk.sh
#
# This script delete Kubernetes' namespaces that stuck in Terminanting status
#
#                                                          thyarles@gmail.com
#
# ----------------------------------------------------------------------------

# Variables
  set -u       # Ensure declaration of variables before use it
  K="kubectl"  # Short for kubectl
  DELBRK=0     # Don't delete broken API by default
  DELRES=0     # Don't delete inside resources by default
  FORCE=0      # Don't force deletion with kubeclt proxy by default
  CLEAN=0      # Start clean flag
  FOUND=0      # Start found flag
  KPORT=8765   # Default port to up kubectl proxy
  TIME=15      # Default timeout to wait for kubectl command responses
  C="\e[96m"   # Cyan
  M="\e[95m"   # Magenta
  B="\e[94m"   # Blue
  Y="\e[93m"   # Yellow
  G="\e[92m"   # Green
  R="\e[91m"   # Red
  S="\e[0m"    # Reset
  N="\n"       # New line

# Function to show help
  show_help () {
    echo -e "\n$(basename $0) [options]\n"
    echo -e "  --skip-tls\t\tSet --insecure-skip-tls-verify on kubectl call"
    echo -e "  --delete-api\t\tDelete broken API founded in your Kubernetes cluster"
    echo -e "  --delete-resource\tDelete resources founded in your stucked namespaces"
    echo -e "  --delete-all\t\tDelete resources and API founded"
    echo -e "  --force\t\tForce deletion of stucked namespaces even if a clen deletion fail"
    echo -e "  --port {number}\tUp kubectl prosy on this port, default is 8765"
    echo -e "  --timeout {number}\tMax time (in seconds) to wait for Kubectl commands"
    echo -e "  --no-color\t\tAll output without colors (useful for scripts)"
    echo -e "  -h --help\t\tShow this help\n"
    exit 0
  }

# Check for parameters
  while (( "$#" )); do
    case $1 in
      --skip-tls)	
        K=$K" --insecure-skip-tls-verify"
        shift
      ;;
      --delete-api)
        DELBRK=1
        shift
      ;;
      --delete-resource)
        DELRES=1
        shift
      ;;
      --delete-all)
        DELBRK=1
        DELRES=1
        shift
      ;;
      --force)
        FORCE=1
        shift
      ;;
      --port)
        shift
        # Check if the port is a number
        [ "$1" -eq "$1" ] 2>/dev/null || show_help
        KPORT=$1
        shift
      ;;
      --timeout)
        shift
        # Check if the time is a number
        [ "$1" -eq "$1" ] 2>/dev/null || show_help
        TIME=$1
        shift
      ;;
      --no-color)
        C=''; M=''; B=''; Y=''; G=''; R=''; S=''
        shift
      ;;
      *) show_help
    esac
  done

# Function to format and print messages
  pp () {
    # First argument is the type of message
    # Second argument is the message
    case $1 in
      t1)     echo  -e "$N$G$2$S"                        ;;
      t2)     echo  -e "$N$Y$2$S"                        ;;
      t3)     echo  -e "$Y.: $2"                         ;;
      t4)     echo  -e "$Y   > $2"                       ;;
      t2n)    echo -ne "$N$Y$2...$S"                     ;;
      t3n)    echo -ne "$Y.: $2...$S"                    ;;
      t4n)    echo -ne "$Y   > $2...$S"                  ;;
      ok)     echo  -e "$G ok$S"                         ;;
      found)  echo  -e "$R found$S"                      ;;
      nfound) echo  -e "$Y not found$S"                  ;;
      del)    echo  -e "$G deleted$S"                    ;;
      skip)   echo  -e "$C deletion skipped$S"           ;;
      error)  echo  -e "$R error$S"                      ;;
      fail)   echo  -e "$R fail$S"; echo -e "$N$2.$N"; exit 1
    esac
  }

# Function to sleep for a while
  timer () {
    OLD_IFS="$IFS"; IFS=:; set -- $*; SECS=$1; MSG=$2
    while [ $SECS -gt 0 ]; do
      sleep 1 &
      printf "\r.: \e[93m$MSG... %02d:%02d\e[0m" $(( (SECS/60)%60)) $((SECS%60))
      SECS=$(( $SECS - 1 ))
      wait
    done
    printf "\r- $MSG... ok!  " 
    set -u; IFS="$OLD_IFS"; echo -e "\n"; export CLEAN=0
  }  

# Check if kubectl is available
  pp t1 "Kubernetes NameSpace Killer"
  pp t2n "Checking if kubectl is configured"
  $K cluster-info >& /dev/null; E=$?
  [ $E -gt 0 ] && pp fail "Check if the kubeclt is installed and configured"
  pp ok

# Check for broken APIs
  pp t2n "Checking for unavailable apiservices"
  APIS=$($K get apiservice | grep False | cut -f1 -d ' ')
  # More info in https://github.com/kubernetes/kubernetes/issues/60807#issuecomment-524772920
  if [ "x$APIS" == "x" ]; then
    pp nfound  # Nothing found, go on
  else
    pp found   # Something found, let's deep in
    for API in $APIS; do
      pp t3n "Broken -> $R$API$S"
      if (( $DELBRK )); then
        CLEAN=1
        timeout $TIME $K delete apiservice $API >& /dev/null; E=$?
        if [ $E -gt 0 ]; then pp error; else pp del; fi
      else
        pp skip
      fi
    done
    [ $CLEAN -gt 0 ] && timer 30 "apiresources deleted, waiting to see if Kubernetes do a clean namespace deletion"
  fi

# Look for stucked namespaces
  pp t2n "Checking for namespaces in Terminating status"
  NSS=$($K get ns 2>/dev/null | grep Terminating | cut -f1 -d ' ')
  NSS="eleicao"
  if [ "x$NSS" == "x" ]; then
    pp nfound
  else
    pp found; FOUND=1
    for NS in $NSS; do
      pp t3n "Checking resources in namespace $R$NS$S"
      RESS=$($K api-resources --verbs=list --namespaced -o name 2>/dev/null | \
           xargs -n 1 $K get -n $NS --no-headers=true --show-kind=true 2>/dev/null | \
           grep -v Cancelling | cut -f1 -d ' ')
      if [ "x$RESS" == "x" ]; then
        pp nfound
      else
        pp found
        for RES in $RESS; do
          pp t4n $RES 
          if (( $DELRES )); then
            CLEAN=1
            timeout $TIME $K -n $NS --grace-period=0 --force=true delete $RES > /dev/null 2>&1; E=$?
            if [ $E -gt 0 ]; then pp error; else pp del; fi
          else
            pp skip
          fi
        done
      fi
    done
  fi

exit

if [ "x$namespace" != "x" ]; then echo -e "found!\n"

  # Set the flag
  found=1

  # Finding all resources that still exist in namespace
  for n in $namespace; do

    echo -e -n "  -- Checking resources in namespace $n... "

    resources=$($k api-resources --verbs=list --namespaced -o name 2>/dev/null | \
                xargs -n 1 $k get -n $n --no-headers=true --show-kind=true 2>/dev/null | \
                grep -v Cancelling | cut -f1 -d ' ')

    if [ "x$resources" != "x" ]; then echo -e "found!\n"
      
      # Delete namespace pedding resources
      for r in $resources; do echo -e "     --- $r"; done
      echo -e -n "\n     Should I delete it for you (yes/[no])? > "; read action; echo -e ""

      if [ "x$action" != "xyes" ]; then
        echo -e "\tOk, the right way is delete not available apiservices resources, check it on"
        echo -e "\thttps://github.com/kubernetes/kubernetes/issues/60807#issuecomment-524772920\n"
      else
        # Set the flag
        clean=1
        for r in $resources; do
          echo -e -n "     >> Deleting $r... "
          $k -n $n --grace-period=0 --force=true delete $r > /dev/null 2>&1; error=$?
          if [ $error -gt 0 ]; then 
            echo -e "failed!"
          else
            echo -e "ok!"
          fi
        done   
        echo -e
      fi
    else 
      echo -e "not found!\n"
    fi  
  done 
else

  # No namespace in Terminating mode found
  echo -e "not found!\n"

fi

if [ $clean -gt 0 ]; then
  # As resources was deleted, set a timer to see if Kubernetes do a clean deletion of stucked namespaces
  OLD_IFS="$IFS"; IFS=:
  set -- $*; secs=60
  while [ $secs -gt 0 ]; do
    sleep 1 &
    printf "\r- Waiting a minute to see if Kubernetes do a clean namespace deletion... %02d:%02d" $(( (secs/60)%60)) $((secs%60))
    secs=$(( $secs - 1 ))
    wait
  done
  printf "\r- Waiting a minutes to see if Kubernetes do a clean namespace deletion... ok!  " 
  set -u; IFS="$OLD_IFS"; echo -e "\n"; clean=0
fi

# If flag found is setted, check again for stucked namespaces
if [ $found -gt 0 ]; then

  echo -e -n "- Checking again for namespaces in Terminating status... "
  namespace=$($k get ns 2>/dev/null | grep Terminating | cut -f1 -d ' ')
  
  if [ "x$namespace" != "x" ]; then echo -e "found!\n"

    # Try to get the access token
    echo -e -n "  -- Getting the access token to force deletion... "
    t=$($k -n default describe secret \
      $($k -n default get secrets | grep default | cut -f1 -d ' ') | \
      grep -E '^token' | cut -f2 -d':' | tr -d '\t' | tr -d ' '); error=$?

    if [ $error -gt 0 ]; then 
      echo -e "failed!\n"
      exit 1
    else
      echo -e "ok!\n"
    fi

    # Start the kubeclt proxy
    echo -e -n "  -- Starting kubectl proxy... "
    p=8765
    $k proxy --accept-hosts='^localhost$,^127\.0\.0\.1$,^\[::1\]$' -p $p  > /tmp/proxy.out 2>&1 &
    error=$?; k_pid=$!

    if [ $error -gt 0 ]; then 
      echo -e "failed (please, check if the port $p is free)!\n"
      exit 1
    else
      echo -e "ok (on port $p)!\n"
    fi

    # Forcing namespace deletion
    for n in $namespace; do
      echo -e -n "  >> Forcing deletion of $n... "
      j=/tmp/$n.json
      $k get ns $n -o json > $j 2>/dev/null
     
      # If in MacOS sed is called different
      # Thanks https://github.com/ChrisScottThomas
      if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/\"kubernetes\"//g" $j
      else
        sed -i s/\"kubernetes\"//g $j
      fi

      curl -s -o $j.log -X PUT --data-binary @$j http://localhost:$p/api/v1/namespaces/$n/finalize -H "Content-Type: application/json" --header "Authorization: Bearer $t" --insecure

      sleep 5
      echo -e "ok!"
    done

    # Kill kubectl proxy
    echo -e -n "\n  -- Stopping kubectl proxy... "
    kill $k_pid; wait $k_pid 2>/dev/null

    if [ $error -gt 0 ]; then 
      echo -e "failed!\n"
      exit 1
    else
      echo -e "ok!\n"
    fi
  else
    # Flag found not setted
    echo -e "not found!\n"
  fi
fi

echo -e "Done! Please, check if your stucked namespace was deleted!\n"


#kubectl patch pvc pvc_name -p '{"metadata":{"finalizers":null}}'
#kubectl patch pv pv_name -p '{"metadata":{"finalizers":null}}'
#kubectl patch pod pod_name -p '{"metadata":{"finalizers":null}}'

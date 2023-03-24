#!/bin/bash
## BUILD SCRIPT ##
#limit datasize 1000M || ulimit -v 1048576 -u 1048576 -d 1048576 -s 1048576 || true


#BUILDER_TOK=$(cat /dev/urandom |tr -cd '[:alnum:]' 2>/dev/null |head -c 10 2>/dev/null )
BUILDER_TOK=$(echo "$@"|md5sum|cut -d" " -f1)
echo "::BUILDER:INIT ::"$(date +%F_%T)
echo "::BUILDER:ARGS ::"$@

test -e .buildenv && echo "FOUND .ENV ..loading "
test -e .buildenv && source .buildenv

## pull request rate:
## if you do docker login before pull , your account might be rate limited quickly
## when using proxy registry in your daemon you might skip the login
LOGIN_BEFORE_PULL=false
## should the image be pushed if only native build worked and buildx failed ?
ALLOW_SINGLE_ARCH_UPLOAD=NO
export ALLOW_SINGLE_ARCH_UPLOAD=NO

## quicken up settings ( in gitlab CI only  set REGISTRY_USER and REGISTRY_PASSWORD
PROJECT_NAME=hocker
export PROJECT_NAME=hocker

#export CI_REGISTRY=docker.io
#CI_REGISTRY=docker.io


_ping_docker_registry_v2() {
    res=$(curl $1"/v2/_catalog" 2>/dev/null)
    echo "$res"|grep repositories -q && echo "OK"
    echo "$res"|grep repositories -q || echo "FAIL"
}
_ping_localhost_registry() {
    _ping_docker_registry_v2 127.0.0.1:5000
}
_get_docker_localhost_registry_ip() {
         docker inspect buildregistry |grep IPAddress|cut -d'"' -f4|grep -v ^$|sort -u |while read testip;do
         _ping_docker_registry_v2 $testip:5000|grep -q OK && echo $testip:5000 ;done|head -n1

}

echo "INIT:DUMPING ENV"
env|grep -e REGISTRY -e CACHE |grep -v PASS

[[ -z "$REGISTRY_USER" ]] && echo "REGISTRY_USER NOT SET"
[[ -z "$REGISTRY_USER" ]] && exit 1

[[ -z "$REGISTRY_PASSWORD" ]] && echo "REGISTRY_PASSWORD NOT SET"
[[ -z "$REGISTRY_PASSWORD" ]] && exit 1

[[ -z "$LOCAL_REGISTRY_CACHE" ]] && LOCAL_REGISTRY_CACHE=/tmp/buildcache_persist/registry

[[ -z "$REGISTRY_HOST" ]] && echo "DEFAULT_VAL_USED REGISTRY_HOST=docker.io "
[[ -z "$REGISTRY_HOST" ]] && export REGISTRY_HOST=docker.io
[[ -z "$REGISTRY_HOST" ]] && REGISTRY_HOST=docker.io

[[ -z "$CI_REGISTRY" ]] && echo "DEFAULT_VAL_USED CI_REGISTRY=$REGISTRY_HOST "
[[ -z "$CI_REGISTRY" ]] && export CI_REGISTRY=$REGISTRY_HOST
[[ -z "$CI_REGISTRY" ]] && CI_REGISTRY=$REGISTRY_HOST

[[ -z "$REGISTRY_PROJECT" ]] && echo "DEFAULT_VAL_USED REGISTRY_PROJECT=thefoundation "
[[ -z "$REGISTRY_PROJECT" ]] && export REGISTRY_PROJECT=thefoundation
[[ -z "$REGISTRY_PROJECT" ]] && REGISTRY_PROJECT=thefoundation

[[ -z "$CACHE_PROJECT_NAME" ]] && echo "DEFAULT_VAL_USED CACHE_PROJECT_NAME=buildcache_thefoundation "
[[ -z "$CACHE_PROJECT_NAME" ]] && CACHE_PROJECT_NAME=buildcache
[[ -z "$CACHE_PROJECT_NAME" ]] && export CACHE_PROJECT_NAME=buildcache


[[ -z "$CACHE_REGISTRY_HOST" ]] && echo "DEFAULT_VAL_USED CACHE_REGISTRY_HOST=$REGISTRY_HOST "
[[ -z "$CACHE_REGISTRY_HOST" ]]    && CACHE_REGISTRY_HOST=$REGISTRY_HOST
[[ -z "$CACHE_REGISTRY_PROJECT" ]] && CACHE_REGISTRY_PROJECT=$REGISTRY_PROJECT
[[ -z "$CACHE_PROJECT_NAME" ]] && CACHE_PROJECT_NAME=$PROJECT_NAME

[[ -z "$FINAL_CACHE_REGISTRY_HOST" ]] && echo "DEFAULT_VAL_USED FINAL_CACHE_REGISTRY_HOST=$REGISTRY_HOST "
[[ -z "$FINAL_CACHE_REGISTRY_HOST" ]]    && FINAL_CACHE_REGISTRY_HOST=$REGISTRY_HOST

echo "$CACHE_REGISTRY_HOST"|grep  -q docker.io &&  (echo "$REGISTRY_PROJECT" |grep -q thefoundation) && CACHE_PROJECT_NAME=buildcache


[[ -z "$BUILD_TARGET_PLATFORMS" ]] && {

#BUILD_TARGET_PLATFORMS="linux/amd64,linux/arm64,linux/arm/v7,darwin"
#BUILD_TARGET_PLATFORMS="linux/amd64,linux/arm64,linux/arm/v7"
BUILD_TARGET_PLATFORMS="linux/amd64,linux/arm64"
#BUILD_TARGET_PLATFORMS="linux/amd64"
}

###MODE DECISION
## DEFAULT : one full image to save runner time
MODE=onefullimage
#MODE=featuresincreasing

## BUILD SINGLE LAYER IMAGE
MERGE_LAYERS=NO
export MERGE_LAYERS=NO
#MERGE_LAYERS=YES
#export DOCKER_BUILDKIT=1

_diskfree() {  df -m / ;cat /etc/mtab |cut -d" " -f2|grep -v -e /proc -e /sys -e /dev |grep -v '^/$'|while read testme;do test -d $testme && df -m  $testme|tail -n+2;done ; } ;
_oneline() { tr -d '\n' ; } ;
_buildx_arch() {
    case "$(uname -m)" in
    aarch64) echo linux/arm64;;
    x86_64)  echo linux/amd64 ;;
    armv7l|armv7*) echo linux/arm/v7;;
    armv6l|armv6*) echo linux/arm/v6;;
    esac ; } ;
_reformat_docker_purge() { sed 's/^deleted: .\+:\([[:alnum:]].\{2\}\).\+\([[:alnum:]].\{2\}\)/\1..\2|/g;s/^\(.\)[[:alnum:]].\{61\}\(.\)/\1.\2|/g' |tr -d '\n' ; } ;

## Colors ;
## Colors ;
uncolored="\033[0m" ; lightblueb="\033[1;36m" ; lightblue="\033[0;36m" ; purple="\033[0;35m" ; purpleb="\033[1;35m" ;
 black="\033[0;30m" ;  blackb="\033[1;30m"    ; white="\033[0;37m"     ; whiteb="\033[1;37m" ;    red="\033[0;31m"  ;    redb="\033[1;31m" ;
yellow="\033[0;33m" ; yellowb="\033[1;33m"    ;  blue="\033[0;34m"     ; blueb="\033[1;34m"  ;  green="\033[0;32m"  ; greenb="\033[1;93m"  ;

function black          {   echo -en "${black}${1}${uncolored}"                 ; } ;   function blackb          {   echo -en "${blackb}";cat;echo -en "${uncolored}"     ; } ;  function echo_black   {   echo -en "${black}${1}${uncolored}"              ; } ;   function echo_blackb     {   echo -en "${blackb}${1}${uncolored}"               ; } ;
function white          {   echo -en "${white}";cat;echo -en "${uncolored}"     ; } ;   function whiteb          {   echo -en "${whiteb}";cat;echo -en "${uncolored}"     ; } ;  function echo_white   {   echo -en "${white}${1}${uncolored}"              ; } ;   function echo_whiteb     {   echo -en "${whiteb}${1}${uncolored}"               ; } ;
function   red          {   echo -en "${red}";cat;echo -en "${uncolored}"       ; } ;   function   redb          {   echo -en "${redb}";cat;echo -en "${uncolored}"       ; } ;  function echo_red     {   echo -en "${red}${1}${uncolored}"                ; } ;   function echo_redb       {   echo -en "${redb}${1}${uncolored}"                 ; } ;
function green          {   echo -en "${green}";cat;echo -en "${uncolored}"     ; } ;   function greenb          {   echo -en "${greenb}";cat;echo -en "${uncolored}"     ; } ;  function yellow       {   echo -en "${yellow}";cat;echo -en "${uncolored}" ; } ;   function yellowb         {   echo -en "${yellowb}";cat;echo -en "${uncolored}"  ; } ;
function blue           {   echo -en "${blue}";cat;echo -en "${uncolored}"      ; } ;   function blueb           {   echo -en "${blueb}";cat;echo -en "${uncolored}"      ; } ;  function echo_green   {   echo -en "${green}${1}${uncolored}"              ; } ;   function echo_greenb     {   echo -en "${greenb}${1}${uncolored}"               ; } ;
function purple         {   echo -en "${purple}";cat;echo -en "${uncolored}"    ; } ;   function purpleb         {   echo -en "${purpleb}";cat;echo -en "${uncolored}"    ; } ;  function echo_yellow  {   echo -en "${yellow}${1}${uncolored}"             ; } ;   function echo_blue       {   echo -en "${blue}${1}${uncolored}"                 ; } ;
function lightblue      {   echo -en "${lightblue}";cat;echo -en "${uncolored}" ; } ;   function lightblueb      {   echo -en "${lightblueb}";cat;echo -en "${uncolored}" ; } ;  function echo_yellowb {   echo -en "${yellowb}${1}${uncolored}"            ; } ;   function echo_lightblue  {   echo -en "${lightblue}${1}${uncolored}"            ; } ;
function echo_blueb     {   echo -en "${blueb}${1}${uncolored}"                 ; } ;   function echo_purple     {   echo -en "${purple}${1}${uncolored}"                 ; } ;  function echo_purpleb {   echo -en "${purpleb}${1}${uncolored}"            ; } ;   function echo_lightblueb {   echo -en "${lightblueb}${1}${uncolored}"           ; } ;
function colors_list    {   echo_black "black";   echo_blackb "blackb";   echo_white "white";   echo_whiteb "whiteb";   echo_red "red";   echo_redb "redb";   echo_green "green";   echo_greenb "greenb";   echo_yellow "yellow";   echo_yellowb "yellowb";   echo_blue "blue";   echo_blueb "blueb";   echo_purple "purple";   echo_purpleb "purpleb";   echo_lightblue "lightblue";   echo_lightblueb "lightblueb"; } ;

_clock() { echo -n WALLCLOCK : |redb ;echo  $( date -u "+%F %T" ) |yellow ; } ;

case $1 in
  base-focal|base-bionic) MODE="minimal" ;;
  php72|p72|php72_nomysql|p72_nomysql)  MODE="featuresincreasing" ;;
  php74|p74|php74_nomysql|p74_nomysql)  MODE="featuresincreasing" ;;
  php80|p80|php80_nomysql|p80_nomysql)  MODE="featuresincreasing" ;;
  php81|p81|php81_nomysql|p81_nomysql)  MODE="featuresincreasing" ;;

  php5|p5)               MODE="onefullimage" ;;
  php72-maxi|p72-maxi)   MODE="onefullimage" ;;
  php74-maxi|p74-maxi)   MODE="onefullimage" ;;
  php80-maxi|p80-maxi)   MODE="onefullimage" ;;
  php81-maxi|p81-maxi)   MODE="onefullimage" ;;

  php72-mini|p72-mini)   MODE="minimal" ;;
  php74-mini|p74-mini)   MODE="minimal" ;;
  php80-mini|p80-mini)   MODE="minimal" ;;
  php81-mini|p81-mini)   MODE="minimal" ;;

  rest|aux) MODE="onefullimage" ;;
  ""  )     MODE="featuresincreasing" ;;  ## empty , build all
  **  )     MODE="featuresincreasing" ;;  ## out of range , build all

esac
##
buildargs="";
echo -n "::SHOW:CONFIG"|yellow
echo "MERGE_LAYERS=$MERGE_LAYERS ALLOW_SINGLE_ARCH_ULOAD=$ALLOW_SINGLE_ARCH_ULOAD BUILD_TARGET_PLATFORMS=$BUILD_TARGET_PLATFORMS"
echo "######"
echo -n "::SYS:PREP"|yellow
echo -n "::DISABLE:SELINUX"|yellow
echo 0 |tee  /sys/fs/selinux/enforce
cat  /sys/fs/selinux/enforce
sysctl net.ipv6.conf.all.disable_ipv6=1

if [ "$(date -u +%s)" -ge  "$(($(cat /tmp/.dockerbuildenvlastsysupgrade|sed 's/^$/0/g')+3600))" ] ;then
  echo -n "+↑UPGR↑+|"|blue
  which apt-get 2>/dev/null |grep -q apt-get && apt-get update &>/dev/null || true
  which apk     2>/dev/null |grep -q apk     && apk     update &>/dev/null  || true
  echo -n "+↑PROG↑+|"|yellow
  ##alpine
  which git       2>/dev/null |grep -q git || which apk  2>/dev/null |grep -q apk && apk add git sed util-linux bash && apk add jq || true
  which apk       2>/dev/null |grep -q apk && apk add git util-linux bash qemu-aarch64 qemu-x86_64 qemu-i386 qemu-arm || true
  ##deb
  (which git 2>/dev/null |grep -q git || which apt-get   2>/dev/null |grep -q "/apt-get" && apt-get install -y git bash && apt-get -y install jq || true ) | red
  which apt-get   2>/dev/null |grep -q apt-get && ( apt-get install -y binfmt-support 2>&1|| true ) |blue
  ( which apt-get   2>/dev/null |grep -q "/apt-get" && ( dpkg --get-selections|grep -v deinst|grep -e qemu-user-stat -e qemu-user-binfmt  ) | grep -q -e qemu-user-stat -e  qemu-user-binfmt || apt-get install -y  qemu-user-static || apt-get install -y  qemu-user-binfmt || true ) |blue

  mkdir -p /etc/libvirt/
  echo "max_threads_per_process = 4" >> /etc/libvirt/qemu.conf


( echo -n ":REG_LOGIN[test:init]:" |blue; sleep $(($RANDOM%2));sleep $(($RANDOM%3)); echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}"  2>&1 || exit 235 ; docker logout 2>&1  ) |grep -i -v warning |blue  | _oneline
else
  echo " → no upgr (1h threshold)→"|green
fi
echo $(date -u +%s) > /tmp/.dockerbuildenvlastsysupgrade

startdir=$(pwd)
#mkdir buildlogs || mv buildlogs/*log /tmp/ || true
echo -n "::GIT"|red|whiteb
/bin/sh -c "test -d Hocker || git clone https://github.com/TheFoundation/Hocker.git --recurse-submodules && (cd Hocker ;git pull origin master --recurse-submodules )"|green|whiteb
imagetester=$(pwd)/Hocker/thefoundation-imagetester.sh
cp $imagetester build/
(cd $(pwd)/Hocker/; git submodule update --remote)
echo "using $imagetester"|yellow
#echo -n ":BUILD:VERIFY:"|blue;echo "using $imagetester"|yellow
#ls -lh1 $imagetester

cd Hocker/build/
## end head preparation stage
####
                        ###
_build_docker_buildx() {
        cd ${startdir}
        PROJECT_NAME=hocker
        export PROJECT_NAME=hocker
        pwd |green
        echo -n ":REG_LOGIN[buildx]:"|blue;(  echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}"  2>&1  || true |grep -v -i -e assword -e  redential| _oneline ) ; ( (docker logout 2>&1 || true ) | grep emoving)| _oneline
        which apk |grep "/apk" -q && apk add git bash
        #export DOCKER_BUILDKIT=1
        git clone git://github.com/docker/buildx ./docker-buildx
        buildx_dir=$(pwd)"/docker-buildx"
        ##  --platform=local needs experimental docker scope

        [[ "${LOGIN_BEFORE_PULL}" = "true" ]] &&  {  echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}"  2>&1 || exit 235 ; } |_oneline ;
        [[ "${LOGIN_BEFORE_PULL}" = "true" ]] ||    docker logout  2>&1 |_oneline
        echo daemon settings
        cat /etc/docker/daemon.json|green
        /bin/bash -c "docker pull  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:buildhelper_buildx || true " 2>/dev/null
        DOCKER_CLI_EXPERIMENTAL=enabled docker pull  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:buildhelper_buildx || true | _oneline
        docker logout 2>&1 |_oneline
        ## now image is extracted ( contains only one file named buildx )
        ## when the buildx file is older than 2 weeks buildx is rebuilt
        HAVETOBUILDX=true ;
        mkdir buildx-save;

        docker save ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:buildhelper_buildx -o buildx-save/buildx.tar && cd buildx-save && tar xvf buildx.tar
        for mylayer in $(find -name "layer.tar") ;do tar xvf ${mylayer};done
        ## search through image for a file called buildx that is executable and newer than 2 weeks
        find -name "buildx" -executable -mtime -15 |grep buildx$ && { HAVETOBUILDX=false ;
                                                                     test -f buildx && mkdir -p ~/.docker/cli-plugins/ && cp buildx ~/.docker/cli-plugins/docker-buildx && chmod +x ~/.docker/cli-plugins/docker-buildx ; mv buildx ..; } ;

        if [ "${HAVETOBUILDX}" = "true" ] ; then
        echo "BUILDX missing-pulling from hub and recreating too old or not executable"
          docker build -t ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:buildhelper_buildx ${buildx_dir}
          _diskfree|blue;docker system df|red;docker image ls|grep buildx|blue |_oneline;echo
          ( echo -n ":REG_LOGIN[push:buildx]:" |blue; sleep $(($RANDOM%2));sleep $(($RANDOM%3)); echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}"  2>&1 || exit 235 ;  ) |grep -i -v warning |blue  | _oneline
          echo -n ":DOCKER:PUSH@"${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:buildhelper_buildx":"
          (docker push ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:buildhelper_buildx |grep -v -e Waiting$ -e Preparing$ -e "Layer already exists$";docker logout 2>&1 | _oneline |grep -v -e emov -e redential)  |sed 's/$/ →→ /g;s/Pushed/+/g' |tr -d '\n'
          docker build -o . ${buildx_dir}
          echo "after build"|blue
          cp buildx ${startdir}
          pwd;ls
          test -f buildx && mkdir -p ~/.docker/cli-plugins/ && cp buildx ~/.docker/cli-plugins/docker-buildx && chmod +x ~/.docker/cli-plugins/docker-buildx
        fi

    echo ; } ;


_docker_pull_multiarch() {
    echo "docker_pull_multiarch called with $@"
     PULLTAG="$1"; echo -n "↓↓PULL(multiarch)→→"|green
    [[ -z "$PULLTAG"  ]] && ( echo "no PULLTAG" |red)
    [[ -z "$LOCAL_REGISTRY"  ]] || ( echo "USING LOCAL_REGISTRY $LOCAL_REGISTRY FIRST" |green)

    #for curtag in ${PULLTAG} $(DOCKER_CLI_EXPERIMENTAL=enabled  docker buildx imagetools inspect "${PULLTAG}" 2>&1 |grep Name|cut -d: -f2- |sed 's/ //g'|grep @) ;do
    #curtag=${PULLTAG}
    for curtag in $([[ -z "$LOCAL_REGISTRY"  ]] || echo "$LOCAL_REGISTRY"/${PULLTAG}) ${PULLTAG} ;do
       [[ "${LOGIN_BEFORE_PULL}" = "true" ]] &&  { echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}" 2>&1 || exit 235 ; } |_oneline;echo ;
       [[ "${LOGIN_BEFORE_PULL}" = "true" ]] ||    docker logout  2>&1 |_oneline;echo
    for current_target in $(echo ${BUILD_TARGET_PLATFORMS}|sed 's/,/ /g');do
        echo ;echo -n "docker pull  (native)                     ${curtag} | :: |" | blue
          docker pull   ${curtag} 2>&1  |grep -v -e Verifying -e Download|grep -v -i helper |sed 's/Pull.\+/↓/g'|sed 's/\(Waiting\|Checksum\|exists\|complete\|fs layer\)$/→/g'|_oneline
        echo ;echo the following step will fail on most daemons..stay relaxed |green
        echo -n "docker pull --platform=${current_target}  ${curtag} | :: |" | blue
        ( DOCKER_CLI_EXPERIMENTAL=enabled  docker pull --platform=${current_target}  ${curtag} 2>&1 || true ) |grep -v -e Verifying -e Download|grep -v -i helper |sed 's/Pull.\+/↓/g'|sed 's/\(Waiting\|Checksum\|exists\|complete\|fs layer\)$/→/g'|_oneline
    done
    echo ;echo "now pulling multiarch by digest"|green
    for mydigest in $(DOCKER_CLI_EXPERIMENTAL=enabled  docker manifest inspect ${curtag} |jq  -c '.manifests[]|.digest'|sed 's/"//g') ;do echo "->pull digest for $mydigest";
        docker pull ${curtag}@${mydigest} 2>&1 |grep -v -e Verifying -e Download|grep -v -i helper |sed 's/Pull.\+/↓/g'|sed 's/\(Waiting\|Checksum\|exists\|complete\|fs layer\)$/→/g'|_oneline &
        echo ${mydigest} >> /dev/shm/pulled_docker_digests
   done;
   done
   docker image ls
wait
    #echo -n "removing last digest:";docker rmi --no-prune ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}
    echo -n ; }  ;

_docker_push() {
    echo "docker_push called with $@"
    ##docker buildx 2>&1 |grep -q "imagetools" || ( )
    IMAGETAG_SHORT=$1
    export DOCKER_BUILDKIT=0
    echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}"  2>&1 || exit 235 ;
    echo -n "↑↑↑UPLOAD↑↑↑ "|yellow;_clock
    docker system df|red;docker image ls |grep -e ${REGISTRY_PROJECT} |grep ${PROJECT_NAME} |blue
    echo -n ":REG_LOGIN[push]:"
    sleep $(($RANDOM%2));sleep  $(($RANDOM%3)); echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}"
    echo -n ":DOCKER:PUSH@"${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}":"|blue
    (docker push ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} |grep -v -e Waiting$ -e Preparing$ -e "Layer already exists$";docker logout 2>&1 | _oneline)  |sed 's/$/ →→ /g;s/Pushed/+/g' |tr -d '\n'|yellow
    echo -n "|" ; } ;


_docker_build() {
        echo  "::builder::main( $@ ) "|blue ;_clock
        echo "_docker_build called with $@"|red
        buildstring="" ## rebuilt from features
        IMAGETAG_SHORT="$1"
        IMAGETAG="$2"
        DFILENAME="$3"
        #MYFEATURESET="$4"
        MYBUILDSTRING=$(echo -n "$4"  |base64 -d | _oneline)
        TARGETARCH="$5"
        ## CALLED WITHOUT FIFTH ARGUMENT , BUILD ONLY NATIVE
        echo $TARGETARCH|tr -d '\n'|wc -c |grep -q ^0$ && echo native build
        echo $TARGETARCH|tr -d '\n'|wc -c |grep -q ^0$ && TARGETARCH=$(_buildx_arch)
        TARGETARCH_NOSLASH=${TARGETARCH//\//_};
        TARGETARCH_NOSLASH=${TARGETARCH_NOSLASH//,/_}
        [[ -z "$CACHE_REGISTRY_HOST" ]] && CACHE_REGISTRY_HOST=$REGISTRY_HOST
        [[ -z "$CACHE_REGISTRY_PROJECT" ]] && CACHE_REGISTRY_PROJECT=$CACHE_REGISTRY_PROJECT
        [[ -z "$CACHE_PROJECT_NAME" ]] && CACHE_PROJECT_NAME=$PROJECT_NAME
        echo "$CACHE_REGISTRY_HOST" | grep  -q -i quay.io && export CACHE_REGISTRY_HOST=127.0.0.1:5000
        [[ -z "$CICACHETAG" ]] && export CICACHETAG=${FINAL_CACHE_REGISTRY_HOST}/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:cicache_${REGISTRY_PROJECT}_${PROJECT_NAME}


        echo "_docker_build loaded ARGS AND ENV"|green
        echo "ARGS:"|yellow
        echo TARGETARCH_NOSLASH=$TARGETARCH_NOSLASH |blue
        echo IMAGETAG=$IMAGETAG
        echo IMAGETAG_SHORT=$IMAGETAG_SHORT
        echo DFILENAME=${DFILENAME}
        echo CICACHETAG=${CICACHETAG}
        LOCAL_REGISTRY=""
        LOCAL_REGISTRY=$(_get_docker_localhost_registry_ip)
        [[ -z "$LOCAL_REGISTRY" ]] || $CACHE_REGISTRY_HOST=$LOCAL_REGISTRY
        [[ -z "$LOCAL_REGISTRY" ]] || export LOCAL_REGISTRY="$LOCAL_REGISTRY"

        BUILDCACHETAG=${CACHE_REGISTRY_HOST}/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:buildcache_${REGISTRY_PROJECT}_${PROJECT_NAME}_${IMAGETAG_SHORT}
        PUSHCACHETAG=${FINAL_CACHE_REGISTRY_HOST}/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:buildcache_${REGISTRY_PROJECT}_${PROJECT_NAME}_${IMAGETAG_SHORT}
        echo "${FINAL_CACHE_REGISTRY_HOST}"|grep -q quay.io && PUSHCACHETAG=127.0.0.1:5000/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:buildcache_${REGISTRY_PROJECT}_${PROJECT_NAME}_${IMAGETAG_SHORT}
        echo "LOCAL_REGISTRY: "$(
                                 [[ -z "$LOCAL_REGISTRY" ]] && ( echo "NOT FOUND";docker ps -a |grep registry)
                                 [[ -z "$LOCAL_REGISTRY" ]] || echo "$LOCAL_REGISTRY";)
        echo " #### "
        echo "BUILDCACHETAG=$BUILDCACHETAG"
        echo "CICACHETAG=${CICACHETAG}"
        echo " #### "
        echo "PUSHCACHETAG=$PUSHCACHETAG"
    ##### DETECT APT PROXY
        echo -n ":searching proxy..."|red
        ### if somebody/someone/(CI)  was so nice and set up an docker-container named "apt-cacher-ng" which uses standard exposed port 3142 , use it
        #if echo $(docker inspect --format='{{(index (index .NetworkSettings.Ports "3142/tcp") 0).HostPort}}' apt-cacher-ng || true ) |grep "3142"  ; then
    ## APT CACHE DOCKER
        foundcache=no
        echo $(docker ps -a |grep -e apt-cacher-ng -e ultra-apt-cacher )|grep -e  "80/tcp" -e "3142/tcp" -e ultra-apt && foundcache=yes
        if [ "$foundcache" = "yes" ]  ;then
            proxyaddr=$(
                (
                docker inspect ultra-apt-cacher 2>/dev/null |grep IPAddress|cut -d'"' -f4|grep -v ^$|sort -u |while read testip;do curl -s $testip:80/|grep -i apt|grep -i -q cache && echo $testip:80 ;done|head -n1
                docker inspect apt-cacher-ng    2>/dev/null |grep IPAddress|cut -d'"' -f4|grep -v ^$|sort -u |while read testip;do curl -s $testip:3142/|grep -qi "apt-cacher" && echo $testip:3142 ;done|head -n1
                ) |head -n1
            )
            echo "DETECTED PROXY: $proxyaddr"
            [[ -z "$proxyaddr" ]] || if [ "${CI_COMMIT_SHA}" = "00000000" ] ; then ### fails on github/gitlab-runners
             #BUILDER_APT_HTTP_PROXY_LINE='http://'$( docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' apt-cacher-ng |head -n1)':3142/' ;
             BUILDER_APT_HTTP_PROXY_LINE='http://'$proxyaddr'/' ;
             else
            ## last fail: Connection failure: Address family not supported by protocol [IP: 172.20.0.5 3142]
             ###BUILDER_APT_HTTP_PROXY_LINE='http://'$( docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' apt-cacher-ng |head -n1)':3142/' ;
             #
#             echo "NOT USING PROXY BECAUSE WE ARE ON GITLAB RUNNER , set CI_COMMIT_SHA=00000000 to use anyway"
            echo "DANGER , I SEEM TO RUN ON GITHUB/GITLAB etc. RUNNER , apt-caching might fail"
            BUILDER_APT_HTTP_PROXY_LINE='http://'$proxyaddr'/' ;
            fi
        fi
        if [ "x" = "x${BUILDER_APT_HTTP_PROXY_LINE}" ] ; then
        [[ -z "$APT_HTTP_PROXY_URL" ]] || USING APT_HTTP_PROXY_URL FROM SECRETS
        [[ -z "$APT_HTTP_PROXY_URL" ]] || BUILDER_APT_HTTP_PROXY_LINE=$APT_HTTP_PROXY_URL

        fi
        if [ "x" = "x${BUILDER_APT_HTTP_PROXY_LINE}" ] ; then
            echo "==NO OVERRIDE APT PROXYSET"
        else
            echo "==USING APT PROXY STRING:"${BUILDER_APT_HTTP_PROXY_LINE} ; buildstring='--build-arg APT_HTTP_PROXY_URL='${BUILDER_APT_HTTP_PROXY_LINE}' ';
        fi
    #APT CACHE IN /etc/
        if $( test -d /etc/apt/  &&  grep ^Acquire::http::Proxy /etc/apt/ -rlq) ;then  echo -n "FOUND NATIVE APT proxy:";
                proxystring=$(grep ^Acquire::http::Proxy /etc/apt/ -r|cut -d: -f2-|sed 's/Acquire::http::Proxy//g;s/ //g;s/\t//g;s/"//g;s/'"'"'//g;s/;//g');
                buildstring='--build-arg APT_HTTP_PROXY_URL='${proxystring};
        else
            echo "NO SYSTEM APT PROXY FOUND" ;
          export APT_HTTP_PROXY_URL="";
        fi
        buildstring=${MYBUILDSTRING}" "${buildstring}
        start=$(date -u +%s)
        ## NO BUILDX ,use standard instructions
        #export DOCKER_BUILDKIT=0
        echo;_clock
        echo -n "TAG: $IMAGETAG | BUILD: $buildstring | PULLING ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} IF NOT FOUND | "|yellow
        echo pull our own recent image with DOCKER_BUILDKIT=0 |green
        _docker_pull_multiarch ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}
        echo pull the baseimage in dockerfile: from |green
        _docker_pull_multiarch $(cat ${DFILENAME}|grep ^FROM|sed 's/^FROM/ /g' |cut -d"#" -f1 |cut -f1)
        echo;_clock


        #buildstring=$buildstring" "$(echo $MYEATURESET|sed 's/@/=true --build-arg /g'|sed 's/ --build-arg//g;s/^/ --build-arg /g'|sed 's/^ --build-arg $//g' |_oneline);
        echo -n "→FEATURES  : "|blue;echo -n "${MYBUILDSTRING}";
        echo -n "→BUILD ARGS: "|blue;echo $buildstring
        _clock
        native_build_failed=yes
        buildx_failed=no
        ## BUILDX does not support squash (2020) USING https://gitlab.com/the-foundation/docker-squash-multiarch
        #if [ "${MERGE_LAYERS}" = "YES" ] ; then
        #        buildstring=${buildstring}" --squash "
        #fi
        echo -n "testing for buildx:"|red
        if $(docker buildx 2>&1 |grep -q "imagetools") ;then echo "FOUND"|green ; else echo "MISSING"|red;fi

        ## HAVING BUILDX , builder should loop over stack e.g. armV7 / aarch64 / amd64
            if $(docker buildx 2>&1 |grep -q "imagetools") ;then
                echo " TRYING MULTIARCH "|blue
                #echo ${have_buildx} |grep -q =true$ &&  docker buildx create --buildkitd-flags '--allow-insecure-entitlement network.host' --driver-opt network=host --driver docker-container --use --name mybuilder_${BUILDER_TOK} ; echo ${have_buildx} |grep -q =true$ &&  docker buildx create --use --name mybuilder_${BUILDER_TOK}; echo ${have_buildx} |grep -q =true$ &&  docker buildx create --append --name mybuilder_${BUILDER_TOK} --platform=linux/aarch64 rpi4
                # --driver docker-container --driver-opt network=host
                echo "RECREATING buildx HELPER" | green
                (echo -n buildx:rm: |yellow;
                docker buildx rm mybuilder_${BUILDER_TOK}|red | _oneline ;
                echo -n "buildx:create:qemu" |yellow ;
                docker run --rm --privileged multiarch/qemu-user-static --reset -p yes 2>&1 |green
                echo -n "buildx:create:qemu" |yellow ;
                docker buildx create  --buildkitd-flags '--allow-insecure-entitlement network.host' --use --driver-opt network=host  --name mybuilder_${BUILDER_TOK} 2>&1 | blueb | _oneline ;echo
                #docker buildx create  --driver docker-container --driver-opt image=moby/buildkit:master,network=host --buildkitd-flags '--allow-insecure-entitlement network.host' --use --driver-opt network=host  --name mybuilder_${BUILDER_TOK} 2>&1 | blueb | _oneline ;
                echo "TESTING CREATED BUILDER:"|blue
                docker buildx inspect --bootstrap 2>&1 |yellow) # | yellow|_oneline|grep -A4 -B4  ${TARGETARCH} && arch_ok=yes
                arch_ok=yes
                if [ "$arch_ok" = "yes" ] ;then echo "arch_ok" for $TARGETARCH
                ## RANDOMIZE LOGIN TIME ; SO MULTIPLE RUNNERS DON't TRIGGER POSSIBLE BOT/DDOS-PREVENTION SCRIPTS
                rsleepa=$(($RANDOM%2))
                rsleepb=$(($RANDOM%3))
                echo "WAITING $rsleepa + $rsleepb"|green
                sleep $rsleepa;sleep $rsleepb ;
                echo -n "docker:login:( ${REGISTRY_USER}@${REGISTRY_HOST} )"|blue
                loginresult=$( echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}"  2>&1 |grep -v  "WARN" |_oneline)
                echo "$loginresult" | red
                if echo "$loginresult"|grep -i  "unauthorized" ; then
                 echo "could not login . would never push .." |red
                exit 40
                fi
                if echo "$loginresult"|grep -i -v "unauthorized" ; then
                echo "login seems ok"|green
                echo -ne "d0ck³r buildX , running the following command ( first to daemon , then Registry , cache source and target may vary ):"|yellow|blueb;echo -ne "\e[1;31m"
                echo "docker buildx build  --output=type=image                --pull --progress plain --network=host --memory-swap -1 --memory 1024M --platform=${TARGETARCH} --cache-from=type=registry,ref=${PUSHCACHETAG} --cache-to=type=registry,mode=max,ref=${BUILDCACHETAG} -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} $buildstring -f ${DFILENAME}"  . | yellowb
                echo "IMAGE FROM TAG IS :"|blue;grep "FROM" ${DFILENAME}|grep -v "#FROM"
                echo "ON THIS MACHINE THERE ARE THE FOLLOWING CACHES AND REGISTRY RUNNING:"
                docker ps -a |grep -e apt-cache -e registry
                echo -e "\e[0m\e[1;42m STDOUT and STDERR goes to: "${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log \e[0m"
                ##docker buildx build --platform=linux/amd64,linux/arm64,linux/arm/v7,darwin --cache-from ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} -o type=registry $buildstring -f "${DFILENAME}"  .  &> ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
                #docker buildx build  --pull --progress plain --platform=linux/amd64,linux/arm64,linux/arm/v7  --cache-from=type=registry,ref=${CACHE_REGISTRY_HOST}/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:zzz_buildcache_${IMAGETAG_SHORT} --cache-to=type=registry,mode=max,ref=${CACHE_REGISTRY_HOST}/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:zzz_buildcache_${IMAGETAG_SHORT} -o type=local,dest=./dockeroutput $buildstring -f "${DFILENAME}"  .  &> ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
                #--cache-from type=local,src=/root/buildcache/ --cache-to type=local,dest=/root/buildcache/
## :MAIN: BUILDX RUN
                #build2reg without uploading@singlearch
                test -e ${startdir}/buildlogs/ || mkdir ${startdir}/buildlogs/
                echo "::BUILDX:2reg NOUPLOAD@singlearch"   | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log"
                time docker buildx build  --output=type=registry,push=false   --pull --progress plain --network=host --memory-swap -1 --memory 1024M --platform=$(_buildx_arch) --cache-from=type=registry,ref=${PUSHCACHETAG} --cache-to=type=registry,mode=max,ref=${BUILDCACHETAG}  -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} $buildstring -f "${DFILENAME}"  .  2>&1 |tee  -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log"|grep -e CACHED -e ^$ -e '\[linux/' -e '[0-9]\]' -e 'internal]' -e DONE -e fail -e error -e Error -e ERROR |grep -v  -e localized-error-pages -e liberror-perl -e ErrorHandler.phpt  |awk '!x[$0]++'|green |sed  -u 's/^/|REG-NOUPL |/g'
## if local docker daemon does not see buildx cache for whatever reasen ( running isolated )
                docker system df|red;docker image ls |grep -e ${REGISTRY_PROJECT} |grep ${PROJECT_NAME} |blue

                #mkfifo buildimagefifo
                #  ( cat buildimagefifo|docker load &> ${startdir}/buildlogs/load-${IMAGETAG}.${TARGETARCH_NOSLASH}.log  ;
                #  sleep 5;
                #  echo "fifo loading done" |green
                #  cat ${startdir}/buildlogs/load-${IMAGETAG}.${TARGETARCH_NOSLASH}.log ; ) &

                ## ## output type docker is not always possible
                ## echo "::BUILDX:2daemon" | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.2daemon.log"
                ## time ( docker buildx build   --output=type=docker --pull --progress plain --network=host --memory-swap -1 --memory 1024M  --platform=$(_buildx_arch) --cache-from=type=registry,ref=${CACHE_REGISTRY_HOST}/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:zzz_buildcache_${IMAGETAG_SHORT} -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}  $buildstring -f "${DFILENAME}"  .  2>&1 |tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.2daemon.log" |grep -e CACHED -e ^$ -e '\[linux/' -e '[0-9]\]' -e 'internal]' -e DONE -e fail -e error -e Error -e ERROR |grep -v  -e localized-error-pages -e liberror-perl -e ErrorHandler.phpt  |awk '!x[$0]++'|blue|sed  -u 's/^/|DAEMON |/g' )
#                time ( docker buildx build   --output=type=tar,dest=buildimagefifo --pull --progress plain --network=host --memory-swap -1 --memory 1024M  --cache-to=type=inline  --cache-from ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}  $buildstring -f "${DFILENAME}"  .  2>&1 |tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.2daemon.log" |grep -e CACHED -e ^$ -e '\[linux/' -e '[0-9]\]' -e 'internal]' -e DONE -e fail -e error -e Error -e ERROR |grep -v  -e localized-error-pages -e liberror-perl -e ErrorHandler.phpt  |awk '!x[$0]++'|blue|sed  -u 's/^/|DAEMON |/g' )

                # time ( docker build --pull --progress plain --network=host --memory-swap -1 --memory 1024M  --cache-from ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}  $buildstring -f "${DFILENAME}"  .  2>&1 |tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.2daemon.log" |grep -e CACHED -e ^$ -e '\[linux/' -e '[0-9]\]' -e 'internal]' -e DONE -e fail -e error -e Error -e ERROR |grep -v  -e localized-error-pages -e liberror-perl -e ErrorHandler.phpt  |awk '!x[$0]++'|blue|sed  -u 's/^/|DAEMON (native) |/g' )

[[ "${SKIP_IMAGETEST}"  = "yes"  ]] && {
echo "build_ok:yes"  && build_success=yes
echo -n ; } ;

[[ "${SKIP_IMAGETEST}"  = "yes"  ]] || {
## image is being tested
            build_succes=no
            echo "TEST:TESTRUN"|green;
            echo -n ":BUILD:VERIFY:"|blue;echo "using "$(ls -lh1 $imagetester)|yellow
            _diskfree|blue;docker system df|red;docker image ls |grep -e ${REGISTRY_PROJECT} |grep ${PROJECT_NAME} |blue
            ## in workers of GitLab-Runners/GH-Actions mounts are empty.. create a dockerfile
            #echo "FROM ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}" > "${DFILENAME}.imagetest"
            echo "CREATING NEW DOCKERFILE ${DFILENAME}.imagetest | SOURCE ${DFILENAME}"|green
            cp -auv "$imagetester" image-tester.sh
            wget -c https://the-foundation.gitlab.io/static-testing-assets/ssl/dhparam-8192.pem -O dhparam.pem

            ( cat "${DFILENAME}"|grep -v ^HEALTHCHECK|grep -v ^CMD
            echo
            echo "COPY dhparam.pem /etc/ssl/dhparam.pem"
            echo "COPY image-tester.sh / "
            echo "CMD /bin/bash /image-tester.sh" )  | tee "${DFILENAME}.imagetest"|head -n5 |red
            echo "((CONTENTS OF REGULAR DOCKERFILE))"|yellow
            echo ..
            echo ..
            cat "${DFILENAME}.imagetest"|tail -n 5 |purple
            _clock
            echo "::BUILDX:IMAGETEST:2daemon"| tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.2daemon.TESTRUN.log" |green
            time ( docker buildx build   --output=type=docker                     --pull --progress plain  --network=host --memory-swap -1 --memory 1024M   --cache-from=type=registry,ref=${BUILDCACHETAG}  -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}.imagetest  $buildstring -f "${DFILENAME}.imagetest"  .  2>&1 |tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.2daemon.TESTRUN.log" | grep -v "sha256:"|awk '!x[$0]++'|blue|sed  -u 's/^/|DAEM-IMAGETEST |/g' )
            _clock
            docker system df|red;docker image ls |grep -e ${REGISTRY_PROJECT} |grep ${PROJECT_NAME} |blue
            #echo "rebuilding in host( should be cached as well)"
            #time ( docker build --progress plain --network=host --memory-swap -1 --memory 1024M  --cache-from ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}.imagetest  $buildstring -f "${DFILENAME}.imagetest"  .  2>&1 |tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.2daemon.TESTRUN.log" | awk '!x[$0]++'|blue|sed  -u 's/^/|DAEM-IMAGETEST |/g' )
            #docker system df|red;docker image ls |grep -e ${REGISTRY_PROJECT} |grep ${PROJECT_NAME} |blue
            echo docker run  ' --rm -e "TERM=xterm-256color" -t '${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}'.imagetest /bin/bash /thefoundation-imagetester.sh'
            docker run  -e MAIL_HOST=localhost \
                        -e APP_URL=localtest.lan \
                        -e MAIL_USERNAME=testLocalImage \
                        -e MAIL_PASSWORD=testLocalPass \
                        -e MYSQL_ROOT_PASSWORD=ImageTesterRoot \
                        -e MYSQL_USERNAME=ImageTestUser \
                        -e MYSQL_PASSWORD=ImageTestPW \
                        -e MYSQL_DATABASE=ImageTestDB \
                        -e MARIADB_REMOTE_ACCESS=true \
                         --rm -e "TERM=xterm-256color"  -t ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}.imagetest /bin/bash /image-tester.sh |  tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log"

            echo -n "deleting imagetester" ;docker rmi ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}.imagetest | tr -d '\n';echo
            tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok"
            tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  && build_success=yes ;
            test -e "${DFILENAME}.imagetest" && rm "${DFILENAME}.imagetest"
## attention: imgetest does only check on the current achitecture
echo -n ; } ;
            echo "state after imagetest: build_success="$build_success;
            [[ "$build_success" = "no" ]]  && [[ "FORCE_UPLOAD" = "true" ]] && build_success=yes && echo "BUILDING TO REGISTRY WITHOUT TEST .. REASON: FORCE_UPLOAD=true"
            [[ "$build_success" = "no" ]]  && echo "test run failed"
            [[ "$build_success" = "yes" ]] && {
###   upload    multiarch withbuildx
echo "uploading multiarch with buildx"
            _clock;
            test -e /tmp/multisquash || git clone https://gitlab.com/the-foundation/docker-squash-multiarch.git /tmp/multisquash  &> ${startdir}/buildlogs/install_multisquash.log &
            echo "::BUILDX:2reg PUSHING MULTIARCH TO REGISTRY AS ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}"   | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log"
            time docker buildx build  --output=type=registry,push=true  --push  --pull --progress plain --network=host --memory-swap -1 --memory 1024M --platform=${TARGETARCH}   --cache-from=type=registry,ref=${BUILDCACHETAG} --cache-to=type=registry,mode=max,ref=${PUSHCACHETAG}  -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} $buildstring -f "${DFILENAME}"  .  2>&1 |tee  -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log"|grep -e CACHED -e ^$ -e '\[linux/' -e '[0-9]\]' -e 'internal]' -e DONE -e fail -e error -e Error -e ERROR |grep -v  -e localized-error-pages -e liberror-perl -e ErrorHandler.phpt  |awk '!x[$0]++'|green|sed  -u 's/^/|REG |/g'
            _clock
            echo "${MERGE_LAYERS}" |grep -q "YES" && {
                test -e /tmp/multisquash/docker-squash-multiarch.sh &&   echo "SQUASHing ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}"|green | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log"
                test -e /tmp/multisquash/docker-squash-multiarch.sh && ( echo "${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}" |grep -q base || time bash /tmp/multisquash/docker-squash-multiarch.sh "${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}" | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log" )
              echo ; } ;
            echo ; } ;
            _clock
            echo -n ":past:buildx_multiarch"|green|whiteb;echo ;tail -n6 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log"|grep -v "exporting config sha256" |yellow
                fi ## LOGIN succeeded
            fi # end if buildx has TARGETARCH
        fi # end if buildx

        _clock
        if $( grep -q -e "failed to solve" -e "no builder.*found" -e 'code = Unknown desc = executor failed running' -e "runc did not terminate successfully" -e "multiple platforms feature is currently not supported for docker drive"  ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log" 2>/dev/null );then
            echo -n "::build:catch:BUILDX FAILED grep statemnt:"|red;echo "log:"|blue
            tail -n 80  ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log"
### docker build native start
        ##  "buildx docker failure" > possible errors often arise from missing qemu / buildkit runs only on x86_64 ( 2020 Q1 )
        _clock
        echo "BUILDING NATIVE SINCE BUILDX FAILED (tests say)   --   DOING MY ARCHITECURE ONLY"
        if $(echo ${TARGETARCH}|grep -q $(_buildx_arch) );then ## native build only works on current arch
            ## DO WE HAVE BUILDX
            if $(docker buildx 2>&1 |grep -q "imagetools" ) ;then
                echo -n "::build::x" ;
                echo -ne "d0ck³r buildX , running the following command ( to daemon):"|yellow|blueb;echo -ne "\e[1;31m"
                 echo "${REGISTRY_PASSWORD}" | docker login --username "${REGISTRY_USER}" --password-stdin "${REGISTRY_HOST}"  2>&1 || exit 235 ;

                docker pull ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}  2>&1  | _oneline
                echo docker buildx build  --output=type=image --pull --progress plain --network=host --memory-swap -1 --memory 1024M --platform=$(_buildx_arch)  --cache-from=type=registry,ref=${BUILDCACHETAG}  -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} $buildstring -f "${DFILENAME}"  . | yellowb
                echo -e "\e[0m\e[1;42m STDOUT and STDERR goes to: "${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log \e[0m"
## :NATIVE: BUILDX RUN
        _clock
            echo "::BUILDX:native:2daemon"| tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log"
            time docker buildx build  --output=type=image                     --pull --progress plain --network=host --memory-swap -1 --memory 1024M --platform=$(_buildx_arch) --cache-from=type=registry,ref=${BUILDCACHETAG}  -t  ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}  $buildstring -f "${DFILENAME}"  .  2>&1 |tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log" |awk '!x[$0]++'|green
            else
                echo -n "::build: NO buildx: "; do_native_build=yes;
                echo "::build: DOING MY ARCHITECURE ONLY ";_buildx_arch
                echo -ne "DOCKER bUILD(native), running the following command: \e[1;31m"
                export DOCKER_BUILDKIT=0
                echo docker build  --cache-from=type=registry,ref=${CACHE_REGISTRY_HOST}/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:zzz_buildcache_${IMAGETAG_SHORT}   $buildstring -f "${DFILENAME}" --rm=false -t ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} .
                echo -e "\e[0m\e[1;42m STDOUT and STDERR goes to:" ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
                DOCKER_BUILDKIT=0 time docker build  --cache-from=type=registry,ref=${BUILDCACHETAG}   $buildstring -f "${DFILENAME}" --rm=false -t ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} . 2>&1 |tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log" |awk '!x[$0]++'|green
                echo -n "VERIFYING NATIVE BUILD";docker system df|red;docker image ls |grep -e ${REGISTRY_PROJECT} |grep ${PROJECT_NAME} |blue
                grep -i -e "uccessfully built " -e  "writing image" -e "exporting layers"  -e "exporting config" ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log" && native_build_failed=no
                #if [ "${native_build_failed}" = "no" ] ; then echo OK ;else echo NATIVE BUILD FAILED ; exit 33 ;fi
                _clock
                ###PUSH ONLY NATIVE ARCH IF ALLOW_SINGLE_ARCH_UPLOAD is YES
                if [ "${ALLOW_SINGLE_ARCH_UPLOAD}" = "YES" ] ; then
                    echo -n "::PUSH::NATIVE_ARCH"|yellow
                    tail -n 11 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log"| grep -q -e "uccessfully built " -e DONE -e "exporting config" && _docker_push ${IMAGETAG_SHORT}
                fi # allow single arch
            fi ##if buildx present else

        fi ## if buildx arch
        _clock

        fi ##buildx failed
        echo "::build:creating merged log"|green
        test -e ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log" && cat ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log" >  ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log" && rm ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".native.log"
        test -e ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log" && cat  ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log" > ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log" && rm ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".buildx.log"
        ## see here https://github.com/docker/buildx
        ##END BUILD STAGE
        _clock
        echo -n "|" ;
        test -f ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log" && echo there is a log in ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
        echo -n "|::END BUILDER::|" ;_clock
        tail -n 10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log" 2>/dev/null| grep -i -e "failed" -e "did not terminate sucessfully" -q || return 0 && return 23

echo -n ; } ;
## END docker_build


_docker_rm_buildimage() { echo "deleting ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${1}" ; docker image rm ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${1} ${PROJECT_NAME}:${1}  2>&1 | grep -v "Untagged"| _reformat_docker_purge |_oneline ; } ;
#####################################
_docker_purge() {
    IMAGETAG_SHORT=$1
    echo;echo -n "::.oO0 PURGE 0Oo.::"
     ( docker image rm ${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT} hocker:${IMAGETAG_SHORT}  2>&1 | grep -v "Untagged"| _reformat_docker_purge
    docker image prune -a -f  --filter 'label!=*qemu*' --filter 'label!=*moby/buildkit*' --filter 'label!=*apt-cacher-ng*'  --filter 'label!=*docker*dind*' 2>&1  | _reformat_docker_purge|red
    echo -n "→→→";
    docker system prune -a -f --filter 'label!=*qemu*' --filter 'label!=*moby/buildkit*' --filter 'label!=*apt-cacher-ng*'  --filter 'label!=*docker*dind*' 2>&1 | _reformat_docker_purge |red ) | _oneline
    echo ;echo "::IMG:"|blue
    docker system df|red;docker image ls |tail -n+2 |sed 's/$/|/g'|tr -d '\n'|yellow
    #docker logout 2>&1 | _oneline
    echo -n "|" ; } ;
#####################################




_run_buildwheel() { ## ARG1 Dockerfile-name ## ARG2 Empty or NOMYSQL
[[ -z "${SKIP_IMAGETEST}" ]] && SKIP_IMAGETEST="no";
echo "::_run_buildwheel SKIP_IMAGETEST=${SKIP_IMAGETEST}"
runbuildfail=0
DFILENAME=$1
## Prepare env
#   test -f ${DFILENAME} && ( cat  ${DFILENAME} > Dockerfile.current ) || (echo "Dockerfile not found";break)
if $(test -f ${DFILENAME});then echo -n ;else   echo "Dockerfile not found..";break;fi

SHORTALIAS=$(basename $(readlink -f ${DFILENAME}))

## for current_target in ${BUILD_TARGET_PLATFORMS//,/ };do
for current_target in $(echo "${BUILD_TARGET_PLATFORMS}");do
realtarget=$current_target
echo "TARGET::"$current_target
TARGETARCH_NOSLASH=${current_target//\//_};
TARGETARCH_NOSLASH=${TARGETARCH_NOSLASH//,/_}
echo "::BUILD:PLATFORM:"$realtarget"::AIMING..."|red
FEATURESET_MINI_NOMYSQL=$(echo -n|cat ${DFILENAME}|grep -v -e MYSQL -e mysql -e MARIADB -e mariadb|grep ^ARG|grep =true|sed 's/ARG \+//g;s/ //'|cut -d= -f1 |awk '!x[$0]++' |grep INSTALL|sed 's/$/@/g'|tr -d '\n' )
FEATURESET_MINI=$(echo -n|cat ${DFILENAME}|grep ^ARG|grep =true|sed 's/ARG \+//g;s/ //'|cut -d= -f1 |awk '!x[$0]++' |grep INSTALL|sed 's/$/@/g'|tr -d '\n' )
FEATURESET_MAXI=$(echo -n|cat ${DFILENAME}|grep ^ARG|grep =    |sed 's/ARG \+//g;s/ //'|cut -d= -f1 |awk '!x[$0]++' |grep INSTALL|sed 's/$/@/g'|tr -d '\n' )
FEATURESET_MAXI_NOMYSQL=$(echo -n|cat ${DFILENAME}|grep -v -e MYSQL -e mysql -e MARIADB -e mariadb|grep ^ARG|grep =|sed 's/ARG \+//g;s/ //'|cut -d= -f1 |awk '!x[$0]++' |grep INSTALL|sed 's/$/@/g'|tr -d '\n' )


#echo " #### "|uncolored
echo "BUILDMODE:" $MODE


## +++ begin build stage ++++
if echo "$MODE" | grep -e "featuresincreasing" -e "mini" ;then  ## BUILD 2 versions , a minimal default packages (INSTALL_WHATEVER=true) and a full image     ## IN ORDER OF APPEARANCE in Dockerfile

## 1 mini
##remove INSTALL_part from FEATURESET so all features underscore separated come up
  if [[ "$2" == "NOMYSQL"  ]];then
  echo "NOMYSQL"
###1.1 mini nomysql ####CHECK IF DOCKERFILE OFFERS MARIADB  |
    if [ 0 -lt  "$(cat ${DFILENAME}|grep INSTALL_MARIADB|wc -l)" ];then
        echo "MARIADB FOUND IN DOCKERFILE 1.1 @ ${current_target}"
        FEATURESET=${FEATURESET_MINI_NOMYSQL}
        buildstring=$(echo ${FEATURESET} |sed 's/@/\n/g' | grep -v ^$ | sed 's/ \+$//g;s/^/--build-arg /g;s/$/=true /g'|grep -v MARIADB|_oneline)" --build-arg INSTALL_MARIADB=false ";
        #tagstring=$(echo "${FEATURESET}"|cut -d_ -f2 |cut -d= -f1 |awk '{print tolower($0)}') ;
        tagstring=""
        cleantags=""
        #cleantags=$(echo "${tagstring}"|sed 's/@/_/g'|sed 's/^_//g;s/_\+/_/g') | _oneline
        IMAGETAG=$(echo ${DFILENAME}|sed 's/Dockerfile-//g' |awk '{print tolower($0)}')"-"$cleantags"_"$(date -u +%Y-%m-%d_%H.%M)"_"$(echo $CI_COMMIT_SHA|head -c8);
        IMAGETAG=$(echo "$IMAGETAG"|sed 's/_\+/_/g;s/_$//g');IMAGETAG=${IMAGETAG/-_/_};IMAGETAG_SHORT=${IMAGETAG/_*/}
        IMAGETAG=${IMAGETAG}_NOMYSQL
        IMAGETAG_SHORT=${IMAGETAG_SHORT}_NOMYSQL
        #### since softlinks are eg Dockerfile-php7-bla → Dockerfile-php7.4-bla
        #### we pull also the "dotted" version" before , since they will have exactly the same steps and our "undotted" version does not exist
        SHORTALIAS=$(echo "${SHORTALIAS}"|sed 's/Dockerfile//g;s/^-//g')
        build_success="no";start=$(date -u +%s)
        seconds=$((end-start))
        echo -en "\e[1:42m";
        TZ=UTC printf "1.1 FINISHED: %d days %(%H hours %M minutes %S seconds)T\n" $((seconds/86400)) $seconds | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
        echo "::BUILD:PLATFORM:"$realtarget"::BUILDING...${DFILENAME}.."|red
        build64=" "$(echo $buildstring|base64 | _oneline)" "; _docker_build ${IMAGETAG_SHORT} ${IMAGETAG}  ${DFILENAME} ${build64} ${realtarget// /}
        end=$(date -u +%s)
        seconds=$((end-start))
        echo -en "\e[1:42m";
        TZ=UTC printf "1.2 FINISHED: %d days %(%H hours %M minutes %S seconds)T\n" $((seconds/86400)) $seconds | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
        docker system df|red;docker image ls |grep -e ${IMAGETAG_SHORT} -e ${PROJECT_NAME} |blue
        echo "VERIFY BUILD LOG: "${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
        all_ok=no
        logs_ok=no
        build_success="no"
        [[ "${SKIP_IMAGETEST}" = "yes" ]] && { (echo SKIPPED IMAGETEST ;echo  build_ok:yes ) |tee  ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" ; } ;
        cat ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"  |tail -n 50 | grep  -e "error: failed to solve:" -e "did not terminate successfully"  || logs_ok=yes;echo "#######"
        tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  && build_success=yes ;
        tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  ||  { echo "test run failed" ;echo;tail -n20 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log"  ; } ;
        ## if we skipped the image test , we pretend it went well
        [[ "${SKIP_IMAGETEST}" = "yes" ]] && { echo "TESTNRUN skipped";build_success=yes ; } ;
        [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] && all_ok=yes
        echo -n "all OK:"|purple;
        echo $all_ok
        [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] && {
        echo "BUILD SUCESSFUL(according to logs and tests)"|green
        docker system df|red;docker image ls|grep -e buildx -e apt-cache  -e ${REGISTRY_PROJECT} -e ${PROJECT_NAME} -e ${IMAGETAG_SHORT}
#_docker_push ${IMAGETAG_SHORT}
        echo -n ; } ;
        [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] || {
          echo "BUILD FAILED logs OK: $logs_ok  ..  TEST RUN OK:  $build_success "|red;
          tail -n 25 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log" ;
          [[ "$FORCE_UPLOAD" = "true" ]] || runbuildfail=$((${runbuildfail}+100))
          echo -n ; } ;

        #uncomment next line to keep the image for the second run
        _docker_rm_buildimage ${IMAGETAG_SHORT} 2>/dev/null | _oneline || true
        #remove all pulled old images from dockerhub
        test -e /dev/shm/pulled_docker_digests && cat /dev/shm/pulled_docker_digests|while read digest;do docker image rm ${digest};done;rm /dev/shm/pulled_docker_digests
        echo return val currently: ${runbuildfail} |green
    fi
  else ## NOMYSQL

###1.2 mini mysql
      echo "1.2"
      FEATURESET=${FEATURESET_MINI}
      buildstring=$(echo ${FEATURESET} |sed 's/@/\n/g' | grep -v ^$ | sed 's/ \+$//g;s/^/--build-arg /g;s/$/=true /g'|grep -v MARIADB|_oneline)" --build-arg INSTALL_MARIADB=true ";
      tagstring="" ; ## nothing , aka "the standard"
      #cleantags=$(echo "${tagstring}"|sed 's/@/_/g'|sed 's/^_//g;s/_\+/_/g') | _oneline
      cleantags=""
      IMAGETAG=$(echo ${DFILENAME}|sed 's/Dockerfile-//g' |awk '{print tolower($0)}')"-"$cleantags"_"$(date -u +%Y-%m-%d_%H.%M)"_"$(echo $CI_COMMIT_SHA|head -c8);
      IMAGETAG=$(echo "$IMAGETAG"|sed 's/_\+/_/g;s/_$//g');IMAGETAG=${IMAGETAG/-_/_};IMAGETAG_SHORT=${IMAGETAG/_*/}
      #IMAGETAG_SHORT=${IMAGETAG_SHORT}
      #### since softlinks are eg Dockerfile-php7-bla → Dockerfile-php7.4-bla
      #### we pull also the "dotted" version" before , since they will have exactly the same steps and our "undotted" version does not exist
      SHORTALIAS=$(echo "${SHORTALIAS}"|sed 's/Dockerfile//g;s/^-//g')
      build_success="no";start=$(date -u +%s)

      doreplace="no";
      echo "${DFILENAME}"|grep -q "_NOMYSQL"  || doreplace=yes
      echo "${DFILENAME}"|grep -q -e "Dockerfile-base" -e  "5.6"  && doreplace="no"
      echo "${DFILENAME}"|grep -q "alpine"  && doreplace="no"
      [[ "$doreplace" = "no" ]] || {
      echo "REPLACING FROM TAG";echo "BEFORE:"$(grep "^FROM" ${DFILENAME} )
      sed 's~^FROM.\+~FROM '${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${IMAGETAG_SHORT}_NOMYSQL'~g' -i ${DFILENAME} -i
      echo "AFTER:"$(grep "^FROM" ${DFILENAME} )
      }

      echo "::BUILD:PLATFORM:"$realtarget"::BUILDING...${DFILENAME}.."|red
      build64=" "$(echo $buildstring|base64 | _oneline)" "; _docker_build ${IMAGETAG_SHORT} ${IMAGETAG}  ${DFILENAME} ${build64} ${realtarget// /}
      end=$(date -u +%s)
      seconds=$((end-start))
      echo -en "\e[1:42m";
      TZ=UTC printf "1.2 FINISHED: %d days %(%H hours %M minutes %S seconds)T\n" $((seconds/86400)) $seconds | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
      docker system df|red;docker image ls |grep -e ${IMAGETAG_SHORT} -e ${PROJECT_NAME} |blue
      echo "VERIFY BUILD LOG: "${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
      all_ok=no
      logs_ok=no
      build_success="no"
      [[ "${SKIP_IMAGETEST}" = "yes" ]] && { (echo SKIPPED IMAGETEST ;echo  build_ok:yes ) |tee  ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" ; } ;
      cat ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"  |tail -n 50 | grep  -e "error: failed to solve:" -e "did not terminate successfully"  || logs_ok=yes;echo "#######"
      tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  && build_success=yes ;
      tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  ||  { echo "test run failed" ;echo;tail -n20 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log"  ; } ;
      ## if we skipped the image test , we pretend it went well
      [[ "${SKIP_IMAGETEST}" = "yes" ]] && { echo "TESTNRUN skipped";build_success=yes ; } ;
      [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] && all_ok=yes
      echo -n "all OK:"|purple;
      echo $all_ok
      [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] && {
      echo "BUILD SUCESSFUL(according to logs and tests)"|green
      docker system df|red;docker image ls|grep -e buildx -e apt-cache  -e ${REGISTRY_PROJECT} -e ${PROJECT_NAME} -e ${IMAGETAG_SHORT}
#      _docker_push ${IMAGETAG_SHORT}

      echo -n ; } ;
      [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] || {
        echo "BUILD FAILED logs OK: $logs_ok  ..  TEST RUN OK:  $build_success "|red;
        tail -n 25 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log" ;
        runbuildfail=$((${runbuildfail}+100))
        echo -n ; } ;
        #uncomment next line to keep the image for the second run
                _docker_rm_buildimage ${IMAGETAG_SHORT} 2>/dev/null | _oneline || true
#remove all pulled old images from dockerhub
test -e /dev/shm/pulled_docker_digests && cat /dev/shm/pulled_docker_digests|while read digest;do docker image rm ${digest};done;rm /dev/shm/pulled_docker_digests
      echo "return val currently: ${runbuildfail}" |green


  fi ## END IF NOMYSQL

fi # end if MODE=featuresincreasing

## maxi build gets triggered on featuresincreasing and onefullimage
## remove INSTALL_part from FEATURESET so all features underscore separated comes up
tagstring=$(echo "${FEATURES}"|cut -d_ -f2 |cut -d= -f1 |awk '{print tolower($0)}') ;
cleantags=$(echo "${tagstring}"|sed 's/^_//g;s/_\+/_/g')
if $(echo $MODE|grep -q -e featuresincreasing -e onefullimage -e full) ; then
echo -n "FULL"
#if [[ "$2" == "NOMYSQL"  ]];then

##LOGIC overwrite## nomysql jobs timed out
if [[ "$2" == "NOMYSQL"  ]];then

echo "NOMYSQL not trigered by inverse logic for nomysql/maxi builds"
else

###2.1 maxi nomysql
    if [ 0 -lt  "$(cat ${DFILENAME}|grep INSTALL_MARIADB|wc -l)" ];then
          echo "MARIADB FOUND IN DOCKERFILE 2.1"
        FEATURESET="${FEATURESET_MAXI_NOMYSQL}"
        buildstring=$(echo ${FEATURESET} |sed 's/@/\n/g' | grep -v ^$ | sed 's/ \+$//g;s/^/--build-arg /g;s/$/=true /g'|grep -v MARIADB|_oneline)" --build-arg INSTALL_MARIADB=false ";
        tagstring=$(echo "${FEATURESET}"|sed 's/@/\n/g'|cut -d_ -f2 |cut -d= -f1 |sed 's/$/_/g'|awk '{print tolower($0)}' | _oneline |sed 's/_\+$//g') ;
        cleantags=$(echo "${tagstring}"|sed 's/@/_/g'|sed 's/^_//g;s/_\+/_/g'|sed 's/_/-/g' | _oneline)
        IMAGETAG=$(echo ${DFILENAME}|sed 's/Dockerfile-//g' |awk '{print tolower($0)}')"-"$cleantags"_"$(date -u +%Y-%m-%d_%H.%M)"_"$(echo $CI_COMMIT_SHA|head -c8);
        IMAGETAG=$(echo "$IMAGETAG"|sed 's/_\+/_/g;s/_$//g');IMAGETAG=${IMAGETAG/-_/_};IMAGETAG_SHORT=${IMAGETAG/_*/}
        IMAGETAG=${IMAGETAG}_NOMYSQL
        IMAGETAG_SHORT=${IMAGETAG_SHORT}_NOMYSQL
        #### since softlinks are eg Dockerfile-php7-bla → Dockerfile-php7.4-bla
        #### we pull also the "dotted" version" before , since they will have exactly the same steps and our "undotted" version does not exist
        SHORTALIAS=$(echo "${SHORTALIAS}"|sed 's/Dockerfile//g;s/^-//g')
        build_success="no";start=$(date -u +%s)

      doreplace="no";
      echo "${DFILENAME}"|grep "_NOMYSQL"  || doreplace=yes
      echo "${DFILENAME}"|grep -e "Dockerfile-base" -e  "5.6" -q && doreplace="no"
      echo "${DFILENAME}"|grep "alpine"  && doreplace="no"

      [[ "$doreplace" = "no" ]]|| {

      echo "REPLACING FROM TAG";echo "BEFORE:"$(grep "^FROM" ${DFILENAME} )
## special_case, use mini featureset as FROM base image
          ##speacial case, big NOMYSQL FROM SMALL _NOMYSQL
          myFEATURESET=${FEATURESET_MINI_NOMYSQL}
          mytagstring=$(echo "${myFEATURESET}"|sed 's/@/\n/g'|cut -d_ -f2 |cut -d= -f1 |sed 's/$/_/g'|awk '{print tolower($0)}' | _oneline |sed 's/_\+$//g') ;
          mycleantags=$(echo "${tagstring}"|sed 's/@/_/g'|sed 's/^_//g;s/_\+/_/g'|sed 's/_/-/g' | _oneline)
          myIMAGETAG=$(echo ${DFILENAME}|sed 's/Dockerfile-//g' |awk '{print tolower($0)}')"-"$cleantags"_"$(date -u +%Y-%m-%d_%H.%M)"_"$(echo $CI_COMMIT_SHA|head -c8);
          myIMAGETAG=$(echo "$myIMAGETAG"|sed 's/_\+/_/g;s/_$//g');myIMAGETAG=${myIMAGETAG/-_/_};myIMAGETAG_SHORT=${IMAGETAG/_*/}
          myIMAGETAG="${myIMAGETAG}_NOMYSQL"


      sed 's~^FROM.\+~FROM '${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${myIMAGETAG}'~g'  ${DFILENAME} |grep  FROM #-i
      echo "AFTER:"$(grep "^FROM" ${DFILENAME} )
      }

        echo "::BUILD:PLATFORM:"$realtarget"::BUILDING...${DFILENAME}.."|red
        build64=" "$(echo $buildstring|base64 | _oneline)" "; _docker_build ${IMAGETAG_SHORT} ${IMAGETAG}  ${DFILENAME} ${build64} ${realtarget// /}
        end=$(date -u +%s)
        seconds=$((end-start))
        echo -en "\e[1:42m";
        TZ=UTC printf "1.2 FINISHED: %d days %(%H hours %M minutes %S seconds)T\n" $((seconds/86400)) $seconds | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
        docker system df|red;docker image ls |grep -e ${IMAGETAG_SHORT} -e ${PROJECT_NAME} |blue
        echo "VERIFY BUILD LOG: "${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
        all_ok=no
        logs_ok=no
        build_success="no"
        [[ "${SKIP_IMAGETEST}" = "yes" ]] && { (echo SKIPPED IMAGETEST ;echo  build_ok:yes ) |tee  ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" ; } ;
        cat ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"  |tail -n 50 | grep  -e "error: failed to solve:" -e "did not terminate successfully"  || logs_ok=yes;echo "#######"
        tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  && build_success=yes ;
        tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  ||  { echo "test run failed" ;echo;tail -n20 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log"  ; } ;
        ## if we skipped the image test , we pretend it went well
        [[ "${SKIP_IMAGETEST}" = "yes" ]] && { echo "TESTNRUN skipped";build_success=yes ; } ;
        [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] && all_ok=yes
        echo -n "all OK:"|purple;
        echo $all_ok
        [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] && {
        echo "BUILD SUCESSFUL(according to logs and tests)"|green
        docker system df|red;docker image ls|grep -e buildx -e apt-cache  -e ${REGISTRY_PROJECT} -e ${PROJECT_NAME} -e ${IMAGETAG_SHORT}
#        _docker_push ${IMAGETAG_SHORT}
        echo -n ; } ;
        [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] || {
          echo "BUILD FAILED logs OK: $logs_ok  ..  TEST RUN OK:  $build_success "|red;
          tail -n 25 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log" ;
          runbuildfail=$((${runbuildfail}+100))
          echo -n ; } ;
          #uncomment next line to keep the image for the second run
                  _docker_rm_buildimage ${IMAGETAG_SHORT} 2>/dev/null | _oneline || true
#remove all pulled old images from dockerhub
test -e /dev/shm/pulled_docker_digests && cat /dev/shm/pulled_docker_digests|while read digest;do docker image rm ${digest};done;rm /dev/shm/pulled_docker_digests
        echo return val currently: ${runbuildfail} |green
    fi
#else ## NOMYSQL

echo MYSQL
###2.1 maxi mysql
    FEATURESET=${FEATURESET_MAXI}
    buildstring=$(echo ${FEATURESET} |sed 's/@/\n/g' | grep -v ^$ | sed 's/ \+$//g;s/^/--build-arg /g;s/$/=true /g'|grep -v MARIADB|_oneline)" --build-arg INSTALL_MARIADB=true ";
    tagstring=$(echo "${FEATURESET}"|sed 's/@/\n/g'|cut -d_ -f2 |cut -d= -f1 |sed 's/$/_/g'|awk '{print tolower($0)}' | _oneline |sed 's/_\+$//g') ;
    cleantags=$(echo "${tagstring}"|sed 's/@/_/g'|sed 's/^_//g;s/_\+/_/g'|sed 's/_/-/g' | _oneline)
    IMAGETAG=$(echo ${DFILENAME}|sed 's/Dockerfile-//g' |awk '{print tolower($0)}')"-"$cleantags"_"$(date -u +%Y-%m-%d_%H.%M)"_"$(echo $CI_COMMIT_SHA|head -c8);
    IMAGETAG=$(echo "$IMAGETAG"|sed 's/_\+/_/g;s/_$//g');IMAGETAG=${IMAGETAG/-_/_};IMAGETAG_SHORT=${IMAGETAG/_*/}
    IMAGETAG_SHORT=${IMAGETAG_SHORT}
    #### since softlinks are eg Dockerfile-php7-bla → Dockerfile-php7.4-bla
    #### we pull also the "dotted" version" before , since they will have exactly the same steps and our "undotted" version does not exist
    SHORTALIAS=$(echo "${SHORTALIAS}"|sed 's/Dockerfile//g;s/^-//g')
    build_success="no";start=$(date -u +%s)

      echo "REPLACING FROM TAG";echo "BEFORE:"$(grep "^FROM" ${DFILENAME} )
## special_case, use mini featureset as FROM base image
          ##speacial case, big NOMYSQL FROM SMALL _NOMYSQL
          #myFEATURESET=${FEATURESET_MINI_NOMYSQL}
          myFEATURESET="${FEATURESET_MAXI_NOMYSQL}"
          mytagstring=$(echo "${myFEATURESET}"|sed 's/@/\n/g'|cut -d_ -f2 |cut -d= -f1 |sed 's/$/_/g'|awk '{print tolower($0)}' | _oneline |sed 's/_\+$//g') ;
          mycleantags=$(echo "${tagstring}"|sed 's/@/_/g'|sed 's/^_//g;s/_\+/_/g'|sed 's/_/-/g' | _oneline)
          myIMAGETAG=$(echo ${DFILENAME}|sed 's/Dockerfile-//g' |awk '{print tolower($0)}')"-"$cleantags"_"$(date -u +%Y-%m-%d_%H.%M)"_"$(echo $CI_COMMIT_SHA|head -c8);
          myIMAGETAG=$(echo "$myIMAGETAG"|sed 's/_\+/_/g;s/_$//g');myIMAGETAG=${myIMAGETAG/-_/_};myIMAGETAG_SHORT=${IMAGETAG/_*/}
          myIMAGETAG="${myIMAGETAG}_NOMYSQL"
      sed 's~^FROM.\+~FROM '${REGISTRY_HOST}/${REGISTRY_PROJECT}/${PROJECT_NAME}:${myIMAGETAG}'~g'  ${DFILENAME} |grep  FROM #-i
      echo "AFTER:"$(grep "^FROM" ${DFILENAME} )

    echo "::BUILD:PLATFORM:"$realtarget"::BUILDING...${DFILENAME}.."|red
    build64=" "$(echo $buildstring|base64 | _oneline)" "; _docker_build ${IMAGETAG_SHORT} ${IMAGETAG}  ${DFILENAME} ${build64} ${realtarget// /}
    end=$(date -u +%s)
    seconds=$((end-start))
    echo -en "\e[1:42m";
    TZ=UTC printf "1.2 FINISHED: %d days %(%H hours %M minutes %S seconds)T\n" $((seconds/86400)) $seconds | tee -a ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
    docker system df|red;docker image ls |grep -e ${IMAGETAG_SHORT} -e ${PROJECT_NAME} |blue
    echo "VERIFY BUILD LOG: "${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"
    all_ok=no
    logs_ok=no
    build_success="no"
    [[ "${SKIP_IMAGETEST}" = "yes" ]] && { (echo SKIPPED IMAGETEST ;echo  build_ok:yes ) |tee  ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" ; } ;
    cat ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log"  |tail -n 50 | grep  -e "error: failed to solve:" -e "did not terminate successfully"  || logs_ok=yes;echo "#######"
    tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  && build_success=yes ;
    tail -n10 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log" |grep -q "build_ok:yes"  ||  { echo "test run failed" ;echo;tail -n20 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".TESTRUN.log"  ; } ;
    ## if we skipped the image test , we pretend it went well
    [[ "${SKIP_IMAGETEST}" = "yes" ]] && { echo "TESTNRUN skipped";build_success=yes ; } ;
    [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] && all_ok=yes
    echo -n "all OK:"|purple;
    echo $all_ok
   [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] && {
   echo "BUILD SUCESSFUL(according to logs and tests)"|green
   docker system df|red;docker image ls|grep -e buildx -e apt-cache  -e ${REGISTRY_PROJECT} -e ${PROJECT_NAME} -e ${IMAGETAG_SHORT}
#   _docker_push ${IMAGETAG_SHORT}
   echo -n ; } ;
   [[ "$logs_ok" = "yes" ]] && [[ "${build_success}" = "yes" ]] || {
     echo "BUILD FAILED logs OK: $logs_ok  ..  TEST RUN OK:  $build_success "|red;
     tail -n 25 ${startdir}/buildlogs/build-${IMAGETAG}.${TARGETARCH_NOSLASH}".log" ;
     runbuildfail=$((${runbuildfail}+100))
     echo -n ; } ;
     #uncomment next line to keep the image for the second run
             _docker_rm_buildimage ${IMAGETAG_SHORT} 2>/dev/null | _oneline || true
#remove all pulled old images from dockerhub
test -e /dev/shm/pulled_docker_digests && cat /dev/shm/pulled_docker_digests|while read digest;do docker image rm ${digest};done;rm /dev/shm/pulled_docker_digests
   echo return val currently: ${runbuildfail} |green
fi # end if mode

fi ## if NOMYSQL
done # end for current_target in ${BUILD_TARGET_PLATFORMS//,/ };do


## write-back registry + apt-cacher
( cd /tmp/;env|grep -e "COMMIT_SHA" -e "GITLAB" -e "GITHUB" && test -e /tmp/buildcache_persist &&  (
    echo "CICACHE_WRITE_BACK"
    (docker stop buildregistry;docker rm buildregistry) &
    (docker stop apt-cacher-ng;docker rm apt-cacher-ng) &
    (docker stop ultra-apt-cacher;docker rm ultra-apt-cacher) &
    wait
    echo "REMOVING AND GETTING ${CICACHETAG} AGAIN ( MERGE )"
    docker rmi ${CICACHETAG}
    docker pull ${CICACHETAG} &&             (
        cd /tmp/;docker save ${CICACHETAG} > /tmp/.importCI ;
                                       cat /tmp/.importCI |tar xv --to-stdout  $(cat /tmp/.importCI|tar t|grep layer.tar) |tar xv
    rm /tmp/.importCI
    )
    echo "SAVING ${CICACHETAG}"
    cd /tmp/;sudo tar cv buildcache_persist |docker import - "${CICACHETAG}" && docker push "${CICACHETAG}"  )
)

_docker_purge|_reformat_docker_purge|red
return ${runbuildfail}
echo -n ; } ;
### END BUILD WHEL DEFINITION

_build_latest() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} "
    for FILENAME in $(ls -1 Dockerfile*latest |sort -r);do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+10000));fi
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_latest_nomysql() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} "
    for FILENAME in $(ls -1 Dockerfile*latest |sort -r);do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}" NOMYSQL
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+10000));fi
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php5() {
  localbuildfail=0
  echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php5*  | grep -v nodejs);
  echo "building for ${DFILES}"
      for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+10));fi
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php72() {
  localbuildfail=0
  echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php7.2* |grep -v latest$ |sort -r | grep -v nodejs);
  echo "building for ${DFILES}"
      for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php72_nomysql() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php7.2* |grep -v latest$ |sort -r | grep -v nodejs);
    echo "building for ${DFILES}"
        for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}" NOMYSQL
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php74() {
  localbuildfail=0
  echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php7.4* |grep -v latest$ |sort -r | grep -v nodejs);
  echo "building for ${DFILES}"
    for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}" |yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php74() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php7.4* |grep -v latest$ |sort -r | grep -v nodejs);
    echo "building for ${DFILES}"
    for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php74_nomysql() {
localbuildfail=0
  echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php7.4* |grep -v latest$ |sort -r | grep -v nodejs);
  echo "building for ${DFILES}" >&2
  for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}" NOMYSQL
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;


_build_php80() {
  echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php8.0* |grep -v latest$ |sort -r | grep -v nodejs|grep -v alpine);
  echo "building for ${DFILES}" >&2
  for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php80_nomysql() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php8.0* |grep -v latest$ |sort -r | grep -v nodejs|grep -v alpine);
    echo "building for ${DFILES}"
    for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}" NOMYSQL
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php80_alpine() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php8.0-alpine* |grep -v latest$ |sort -r | grep -v nodejs);
    echo "building for ${DFILES}"
    for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php80_alpine_nomysql() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php8.0-alpine* |grep -v latest$ |sort -r | grep -v nodejs);
    echo "building for ${DFILES}"
    for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}" NOMYSQL
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php81_alpine() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php8.1-alpine* |grep -v latest$ |sort -r | grep -v nodejs);
    echo "building for ${DFILES}"
    for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php81_alpine_nomysql() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php8.1-alpine* |grep -v latest$ |sort -r | grep -v nodejs);
    echo "building for ${DFILES}"
    for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}" NOMYSQL
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;



_build_php81() {
  echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php8.1* |grep -v latest$ |sort -r | grep -v nodejs);
  echo "building for ${DFILES}" >&2
  for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_php81_nomysql() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} ";DFILES=$(ls -1 Dockerfile-php8.1* |grep -v latest$ |sort -r | grep -v nodejs);
    echo "building for ${DFILES}"
    for FILENAME in ${DFILES};do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}" NOMYSQL
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;


_build_base() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} "
    for FILENAME in $(ls -1 Dockerfile-base-$1 |grep -v latest$ |sort -r | grep -v nodejs);do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
        export SKIP_IMAGETEST=yes
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+100));fi ;
        [[ "${FORCE_UPLOAD}" = "true" ]] && localbuildfail=0;
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;


_build_aux() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} "
    export SKIP_IMAGETEST=yes
    for FILENAME in $(ls -1 Dockerfile-*|grep -v Dockerfile-php|grep -v latest$ |grep -v Dockerfile-base |sort -r);do
        echo "DOCKERFILE: ${FILENAME}"|yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+1000));fi
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;

_build_all() {
    localbuildfail=0
    echo "BUILDFUNCTION=${FUNCNAME[0]} "
    for FILENAME in $(ls -1 Dockerfile-*|grep -v latest$ |sort -r | grep -v nodejs);do
        echo "DOCKERFILE: ${FILENAME}" |yellow
        #test -f Dockerfile.current && rm Dockerfile.current
       _run_buildwheel "${FILENAME}"
        if [ "$?" -ne 0 ] ;then localbuildfail=$((${localbuildfail}+1000000));fi
    done
echo "#############################"|blue
echo -n "${FUNCNAME[0]} RETURNING:"|yellow ;echo ${localbuildfail}
echo "##############################"|blue
return ${localbuildfail} ; } ;


## AFTER FUNCTIONS
### LAUNCHING ROCKET
echo -n "::SYS:PREP=DONE ... " |green ;echo '+++WELCOME+++'|blue |yellowb
(echo '|||+++>> SYS: '$(uname -a|yellow)" | binfmt count: "$(ls /proc/sys/fs/binfmt_misc/ |wc -l |blue) " | BUILDX: "$(docker buildx 2>&1 |grep -q "imagetools"  && echo OK || echo NO )" |";echo "| Docker vers. : "$(docker --version|yellow)"| IDentity :  "$(id -u|blue) " == "$(id -un|yellow)"@"$(hostname -f|red)' | ARGZ : '"$@"' <<+++|||' )|green
#test -f Dockerfile.current && rm Dockerfile.current

## CACHES INIT

( test -e /tmp/buildcache_persist && test -e "$LOCAL_REGISTRY_CACHE" ) || (
    echo "GETTING CICACHE ${CICACHETAG}"
    [[ -z "${CICACHETAG}" ]] || (
       docker pull ${CICACHETAG} &&  (
        cd /tmp/;docker save "${CICACHETAG}" > /tmp/.importCI ;
                                           cat /tmp/.importCI |tar xv --to-stdout  $(cat /tmp/.importCI|tar t|grep layer.tar) |tar xv
        rm /tmp/.importCI
        )
    docker rmi "${CICACHETAG}"
) ) |red

echo "finding or starting apt proxy"|yellow
docker ps -a |grep -e ultra-apt-cacher -e apt-cacher-ng || (
    docker run  -d --restart unless-stopped --name ultra-apt-cacher  -v /tmp/buildcache_persist/apt-cacher-ng:/var/cache/apt-cacher-ng registry.gitlab.com/the-foundation/ultra-apt-cacher-ng 2>&1 |grep -v -e "Already exists" -e "Pulling fs layer" -e "Waiting$" -e "Verifying Checksum" -e "Download complete" -e ^Digest: |tr -d '\n'
)

echo
echo "finding or starting docker registry localcache"|yellow
docker ps -a |grep -v apt-cacher |grep -e buildregistry -e harbor  || (
    docker ps -a |grep buildregistry|grep -v Exited|grep buildregistry|| docker run -d  --restart=always  -p 5000:5000 --name buildregistry   -v "/"$LOCAL_REGISTRY_CACHE:/var/lib/registry   registry:2  2>&1 |grep -v -e "Already exists" -e "Pulling fs layer" -e "Waiting$" -e "Verifying Checksum" -e "Download complete" -e ^Digest: |tr -d '\n'
)


buildfail=0

case $1 in
  buildx)                                      _build_docker_buildx ;;
  latest)                                      _build_latest "$@" ;               buildfail=$? ;;
  base-focal)                                  _build_base focal  "$@" ;          buildfail=$? ;;
  base-bionic)                                 _build_base bionic "$@" ;          buildfail=$? ;;

  latest_nomysql)                              _build_latest_nomysql "$@";        buildfail=$? ;;
  php5|p5)                                     _build_php5 "$@" ;                 buildfail=$? ;;
  php72|p72)                                   _build_php72 "$@" ;                buildfail=$? ;;
  php72-mini|p72-mini)                         _build_php72 "$@" ;                buildfail=$? ;;
  php72-nomysql|p72_nomysql)                   _build_php72_nomysql "$@" ;        buildfail=$? ;;
  php72-maxi|p72-maxi)                         _build_php72 "$@" ;                buildfail=$? ;;

  php74|p74)                                   _build_php74 "$@" ;                buildfail=$? ;;
  php74-mini|p74-mini)                         _build_php74 "$@" ;                buildfail=$? ;;
  php74-nomysql|p74-nomysql)                   _build_php74_nomysql "$@" ;        buildfail=$? ;;
  php74-maxi|p74-maxi)                         _build_php74 "$@" ;                buildfail=$? ;;

  php80|p80)                                   _build_php80 "$@" ;                buildfail=$? ;;
  php80-mini|p80-mini)                         _build_php80 "$@" ;                buildfail=$? ;;
  php80-nomysql|p80-nomysql)                   _build_php80_nomysql "$@" ;        buildfail=$? ;;
  php80-maxi|p80-maxi)                         _build_php80 "$@" ;                buildfail=$? ;;
  php80-alpine|p80-alpine)                     _build_php80_alpine "$@" ;         buildfail=$? ;;
  php80-nomysql-alpine|p80-mini-alpine)        _build_php80_alpine_nomysql "$@" ; buildfail=$? ;;

  php81|p81)                                   _build_php81 "$@" ;                buildfail=$? ;;
  php81-mini|p81-mini)                         _build_php81 "$@" ;                buildfail=$? ;;
  php81-nomysql|p81-nomysql)                   _build_php81_nomysql "$@" ;        buildfail=$? ;;
  php81-maxi|p81-maxi)                         _build_php81 "$@" ;                buildfail=$? ;;
  php81-alpine|p81-alpine)                     _build_php81_alpine "$@" ;         buildfail=$? ;;
  php81-nomysql-alpine|p81-mini-alpine)        _build_php81_alpine_nomysql "$@" ; buildfail=$? ;;

  rest|aux)                   _build_aux  "$@" ;          buildfail=$? ;;
  **  )                       _build_all ;                buildfail=$? ; _build_latest ; buildfail=$((${buildfail}+$?)) ;;

esac

[[ -z "$CICACHETAG" ]] && export CICACHETAG=${FINAL_CACHE_REGISTRY_HOST}/${CACHE_REGISTRY_PROJECT}/${CACHE_PROJECT_NAME}:cicache_${REGISTRY_PROJECT}_${PROJECT_NAME}


## write-back registry + apt-cacher
( cd /tmp/;env|grep -e "COMMIT_SHA" -e "GITLAB" -e "GITHUB" && test -e /tmp/buildcache_persist &&  (
    echo "CICACHE_WRITE_BACK"
    (docker stop buildregistry;docker rm buildregistry) &
    (docker stop apt-cacher-ng;docker rm apt-cacher-ng) &
    (docker stop ultra-apt-cacher;docker rm ultra-apt-cacher) &
    wait
    echo "REMOVING AND GETTING ${CICACHETAG} AGAIN ( MERGE )"
    docker rmi ${CICACHETAG}
    docker pull ${CICACHETAG} &&             (
        cd /tmp/;docker save ${CICACHETAG} > /tmp/.importCI ;
                                       cat /tmp/.importCI |tar xv --to-stdout  $(cat /tmp/.importCI|tar t|grep layer.tar) |tar xv
    rm /tmp/.importCI
    )
    echo "SAVING CICACHE ${CICACHETAG}"
    cd /tmp/;sudo tar cv buildcache_persist |docker import - "${CICACHETAG}" && docker push "${CICACHETAG}"  )
)


docker buildx rm mybuilder_${BUILDER_TOK}|red

docker logout 2>&1 | _oneline
test -f Dockerfile && rm Dockerfile
echo "#############################"|blue
echo -n "exiting with:"|yellow ;echo ${buildfail}
echo "##############################"|blue
echo "${buildfail}" > /tmp/hocker.build.result
[[ "$FORCE_UPLOAD" = "true" ]] || exit ${buildfail}
[[ "$FORCE_UPLOAD" = "true" ]] && { echo "FORCE_UPLOAD set , pretending everything went well ..." ;echo 0 >  > /tmp/hocker.build.result; exit 0 ; } ;

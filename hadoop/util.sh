#!/bin/bash

source /usr/lib/hustler/bin/qubole-bash-lib.sh
source /usr/lib/qubole/bootstrap-functions/common/utils.sh
export PROFILE_FILE=${PROFILE_FILE:-/etc/profile}
export HADOOP_ETC_DIR=${HADOOP_ETC_DIR:-/usr/lib/hadoop2/etc/hadoop}
declare -A SVC_USERS=([namenode]=hdfs [timelineserver]=yarn [historyserver]=mapred [resourcemanager]=yarn [datanode]=hdfs)

function start_daemon() {
  daemon=$1;
  case "${SVC_USERS[$daemon]}" in
    yarn)
      /bin/su -s /bin/bash -c "/usr/lib/hadoop2/sbin/yarn-daemon.sh start $daemon" yarn
      ;;
    hdfs)
      /bin/su -s /bin/bash -c "/usr/lib/hadoop2/sbin/hadoop-daemon.sh start $daemon" hdfs
      ;;
    mapred)
      /bin/su -s /bin/bash -c "HADOOP_LIBEXEC_DIR=/usr/lib/hadoop2/libexec /usr/lib/hadoop2/sbin/mr-jobhistory-daemon.sh start $daemon" mapred
      ;;
    *)
      echo "Invalid daemon $daemon"
      ;;
  esac
}

function stop_daemon() {
  daemon=$1;
  case "${SVC_USERS[$daemon]}" in
    yarn)
      /bin/su -s /bin/bash -c "/usr/lib/hadoop2/sbin/yarn-daemon.sh stop $daemon" yarn
      ;;
    hdfs)
      /bin/su -s /bin/bash -c "/usr/lib/hadoop2/sbin/hadoop-daemon.sh stop $daemon" hdfs
      ;;
    mapred)
      /bin/su -s /bin/bash -c "HADOOP_LIBEXEC_DIR=/usr/lib/hadoop2/libexec /usr/lib/hadoop2/sbin/mr-jobhistory-daemon.sh stop $daemon" mapred
      ;;
    *)
      echo "Invalid daemon $daemon"
      ;;
  esac
}

function restart_services() {
  svcs=("$@")
  running_svcs=($(get_running_services "${svcs[@]}"))
  for s in "${running_svcs[@]}"; do
    monit unmonitor "$s"
  done

  for s in "${running_svcs[@]}"; do
    stop_daemon "$s"
  done

  last=${#running_svcs[@]}

  # Restart services in reverse order of how
  # they were stopped
  for (( i=0; i <last; i++ )); do
    start_daemon "${running_svcs[~i]}"
  done

  # Order doesn't matter for (un)monitor
  for s in "${running_svcs[@]}"; do
    monit monitor "$s"
  done
}

##
# Restart hadoop services on the cluster master
#
# This may be used if you're using a different version
# of Java, for example
#
function restart_master_services() {
  restart_services timelineserver historyserver resourcemanager namenode
}


##
# Restart hadoop services on cluster workers
#
# This only restarts the datanode service since the
# nodemanager is started after the bootstrap is run
#
function restart_worker_services() {
  restart_services datanode
  # No need to restart nodemanager since it starts only
  # after thhe bootstrap is finished
}

##
# Use Java 8 for hadoop daemons and jobs
#
# By default, the hadoop daemons and jobs on Qubole
# clusters run on Java 7. Use this function if you would like
# to use Java 8. This is only required if your cluster:
# is in AWS, and
# is running Hive or Spark < 2.2
#
function use_java8() {
 export JAVA_HOME=/usr/lib/jvm/java-1.8.0
 export PATH=$JAVA_HOME/bin:$PATH
 echo "export JAVA_HOME=/usr/lib/jvm/java-1.8.0" >> "$PROFILE_FILE"
 echo "export PATH=$JAVA_HOME/bin:$PATH" >> "$PROFILE_FILE"
 
 sed -i 's/java-1.7.0/java-1.8.0/' "$HADOOP_ETC_DIR/hadoop-env.sh"

 is_master=$(nodeinfo is_master)
 if [[ "$is_master" == "1" ]]; then
   restart_master_services
 else
   restart_worker_services
 fi
}

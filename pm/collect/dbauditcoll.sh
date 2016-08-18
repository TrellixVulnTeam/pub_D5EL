#!/bin/sh
###########################################################
# �ɼ�������ȳ���
#----------------------------------------------------------
# ���÷�ʽ��* * * * *��crontab��
# �����������
# �����������
# ���ã�    �ɼ����������ļ�
#----------------------------------------------------------
# �ɼ����������ļ���ʽ
# EquipID|�ͻ�ID|�ɼ�����|�Ự�û���|ִ������|�ɼ�����|��������ʱ��|���ɼ�ʱ��|�ɼ�����(min)
#----------------------------------------------------------
# Written by zhung 
#               2007-01-05
############################################################
#set -x
WORK_DIR=/ioss/pm/collect

. $WORK_DIR/snmpcol.env

#----------------------------------------------------------------------------------------------
# ��������
#----------------------------------------------------------------------------------------------
#ִ�вɼ�
ExecSnmpCol ()
{
	EquipId=$3
	ColIp=$1
	ExecFileName=$2
	BlockName=$4
	ColPeriod=$5
	CommUser='cs_dbone';
	#Ϊ�˱���������Ϊ�쳣û��ִ�е���ʱ��ͣ�ͣ��ϴ�ִ�вɼ�ʱ���뵱ǰϵͳʱ��Ƚ�
	#��ͬʱ���������б��ļ�
	NowTime=`date +"%Y%m%d%H%M"`
	IntTime=`date +"%Y%m%d%H00"`
	I30Time=`date +"%Y%m%d%H30"`
	#ϵͳҪ��ɼ���С���Ϊ5���ӣ�����ÿСʱ��0�ֶ��ǲɼ��㣬���Դ������С�Ĳɼ��㿪ʼ����
	#���ɼ�ʱ����ܴ����쳣�����޷������ɼ�����ʱ����ӣ�ͨ���жϿ��Լ����������
	if [[ $NowTime -ge $I30Time ]]
	then 
		PeriodTime=$I30Time
	else
		PeriodTime=$IntTime
	fi
	while [[ $NowTime -ge $PeriodTime ]]
	do
		PeriodTime=`GetPeriodTime $PeriodTime $ColPeriod`
	done
	#ѭ��������ʱ��϶��ȵ�ǰʱ���ǰ��һ���ɼ�����Ϊ����ʱ�䣬2������Ϊ��ʼʱ��
	iTemp=`expr 0 - $ColPeriod`
	EndTime=`GetPeriodTime $PeriodTime $iTemp`
	StartTime=`GetPeriodTime $EndTime $iTemp`
  #����ļ�����
  ColFileName="${EquipId}-#-${BlockName}-#-${StartTime}-#-${EndTime}-#-${ColPeriod}.pt"
  
  #ִ�вɼ�����
  #�滻�����еı���
  cat $CMDFILE_DIR/$ExecFileName | sed -e "s/__CommUser__/$CommUser/" \
                                    -e "s/__IP__/$ColIp/" \
                              > $CMDFILE_DIR/$ExecFileName.cmd
  while read aExecCmd
  do
  	echo "`date +'%Y-%m-%d %H:%M:%S'` Exec ${aExecCmd} to File ${ColFileName}" >> $LOGFILE
  	eval $aExecCmd 1>> $COLFILE_DIR/$ColFileName 2>>$LOGFILE 		
  done < $CMDFILE_DIR/$ExecFileName.cmd
  RAWFILE="${EquipId}-#-${BlockName}-#-${StartTime}-#-${EndTime}-#-${ColPeriod}.raw"
  mv $COLFILE_DIR/$ColFileName $COLFILE_DIR/$RAWFILE
  rm -f $CMDFILE_DIR/$ExecFileName.cmd
  #�޸����ɼ�ʱ�䣬����SNMPû�в��ɵĿ����ԣ����Բ����ǲ���
}
#���ʱ��
GetPeriodTime ()
{
	echo `perl $WORK_DIR/GetPeriodTime.pl $1 $2 2>>$LOGFILE`
}
#-------------------------------------------------------------------------------------------------------
#�������ֽ���
#-------------------------------------------------------------------------------------------------------
echo "`date +'%Y-%m-%d %H:%M:%S'` Start Snmp Start Collect..." >> $LOGFILE
#�жϴ˽����Ƿ������У�����������˳�
#if test -f $WORK_DIR/.snmpcoll.pid
#then
#   # File exists so parser may be running, get the pid and see if is running
#   pid=`cat $WORK_DIR/.snmpcoll.pid`
#   # See if a process is running with that process id
#   if test -n "$pid"
#   then
#      PSOPTS="-p"
#      ps $PSOPTS $pid > /dev/null
#      if test $? -eq 0
#      then
#         ps $PSOPTS $pid | grep -i "snmpcoll.sh $1" > /dev/null
#         if test $? -eq 0
#         then
#            # Process is already running so exit
#            exit 3
#         fi
#      else
#         # Try the ps listing again as it is not always reliable
#         ps $PSOPTS $pid > /dev/null
#         if test $? -eq 0
#         then
#            ps $PSOPTS $pid | grep "snmpcoll.sh $1" > /dev/null
#            if test $? -eq 0
#            then
#               # Process is already running so exit
#               exit 3
#            fi
#         fi
#      fi
#   fi
#fi
echo $$ > $WORK_DIR/.snmpcoll.pid
NowTime=`date +"%Y%m%d%H%M"` 
ExecSnmpCol $1 $2 $3 $4 $5
#ɾ���������б���ļ�
rm -f $WORK_DIR/.snmpcoll.pid
echo "`date +'%Y-%m-%d %H:%M:%S'` End Snmp Collect..." >> $LOGFILE
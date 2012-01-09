#!/bin/bash
#
#    newsUpload.sh - Backup files to UseNet
#     View README file for full information
#
#    Usage:
#     1. Configure the variables below
#     2. Run the script with two arguments:
#         - the name of the file you want to upload (single file, use tar)
#         - the name of the posting you want to use in the usenet upload
#
#    Prerequisites:
#     - rar
#     - par2
#     - openssl
#     - newspost (http://newspost.unixcab.org) 
#
#    Decrypt with:
#     $ openssl enc -d -salt -in <filename>.enc -out <filename>
#
#    Copyright 2012 Merijntje Tak
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, version 3 of the License.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

TMPDIR='/var/tmp/newsupload'             # TMPDIR needs to be your filesize + 10%
LOGFILE='/tmp/newsupload.log'            # Logfile location (Optional)

ENCPW='randompw'                         # Password to encrypt with
NEWSSERVER='news.example.com'            # Hostname of newsserver
NEWSUSER='username'                      # Username for newsserver (Optional)
NEWSPASS='password'                      # Password for newsserver (Optional)
NEWSMAIL='username@example.com'          # From address
NEWSGROUP='alt.binaries.test'            # Newsgroup to post to

############################################################################

PATH=$PATH:/usr/bin:/usr/sbin
FILE=$1
PREFIX=$2
DATE=`date "+%Y%m%d"` 

# Check if parameters are given
if [[ ! -n $FILE ]]; then
  echo "Usage: $0 file prefix" >&2
  echo "No file specified. Exiting..." >&2
  exit 2
fi
if [[ ! -n $PREFIX ]]; then
  echo "Usage: $0 file post-name" >&2
  echo "No post-name specified. Exiting..." >&2
  exit 2
fi

# Check if logfile is writable and truncate it
if [ -n $LOGFILE ]; then

  cat /dev/null > $LOGFILE
  touch $LOGFILE
  chmod 644 $LOGFILE

  if [ ! -w $LOGFILE ]; then
    echo "Error: logfile is not writable. Exiting..." >&2
    exit 1
  fi

else 
  LOGFILE='/dev/null';
fi

# Check if all mandatory options are set
if [ -n $NEWSSERVER ]; then 
  echo "\$NEWSSERVER = $NEWSSERVER" >> $LOGFILE
else 
  echo "Error: \$NEWSSERVER is not set. Exiting..." >> $LOGFILE
  exit 1
fi

if [ -n $NEWSMAIL ]; then 
  echo "\$NEWSMAIL = $NEWSMAIL" >> $LOGFILE
else 
  echo "Error: \$NEWSMAIL is not set. Exiting..." >> $LOGFILE
  exit 1
fi

if [ -n $NEWSGROUP ]; then 
  echo "\$NEWSGROUP = $NEWSGROUP" >> $LOGFILE
else 
  echo "Error: \$NEWSGROUP is not set. Exiting..." >> $LOGFILE
  exit 1
fi

if [ -n $ENCPW ]; then 
  echo "\$ENCPW is set" >> $LOGFILE
else 
  echo "Error: \$ENCPW is not set. Exiting..." >> $LOGFILE
  exit 1
fi

if [ -n $PREFIX ]; then 
  echo "\$PREFIX = $PREFIX" >> $LOGFILE
else 
  echo "Error: \$PREFIX is not set. Exiting..." >> $LOGFILE
  exit 1
fi

if [ -n $NEWSUSER ]; then
  echo "\$NEWSUSER = $NEWSUSER" >> $LOGFILE
fi

if [ -n $NEWSPASS ]; then
  echo "\$NEWSPASS is set" >> $LOGFILE
fi


# Check if input file and temp dir exist
if [[ ! -f ${FILE} ]]; then
  echo "Error: file $FILE does not exist" >> $LOGFILE
  exit 1
fi

if [[ ! -d $TMPDIR ]]; then
  mkdir $TMPDIR
  if [[ $? -ne 0 ]]; then
    echo "ERROR: Could not create $TMPDIR" >> $LOGFILE
    exit 1
  fi
fi

# bigWrite function
function bigWrite {
  echo "###############################################" >> $LOGFILE
  echo $1 >> $LOGFILE
}

# Check if there is enough space for the rar and par files 
#  in the temporary directory (filesize + 10%).
FILESIZE=`stat -c "%s" $FILE`
TENPCT=`echo "scale=0;${FILESIZE}/10" | bc`
TOTSIZE=`echo "${FILESIZE}+${TENPCT}" | bc`

FREEBLK=`stat -c "%a" -f $TMPDIR`
BLKSIZE=`stat -c "%s" -f $TMPDIR`
FREEBYTES=`echo "${FREEBLK}*${BLKSIZE}" | bc`

if [[ $TOTSIZE -gt $FREEBYTES ]]; then
  echo "Error: not enough space available in $TMPDIR" >> $LOGFILE
  exit 1
fi

# Cleanup the temp dir
rm -- ${TMPDIR}/* >/dev/null 2>&1

# Encrypt the source file
bigWrite "Encrypting source file:"
openssl enc -aes-256-cbc -salt -in "${FILE}" -out "${TMPDIR}/${FILE}.enc" -pass "pass:${ENCPW}" >> $LOGFILE 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Could not encrypt file, exiting..." >> $LOGFILE
  exit 1
else
  echo "Finished encrypting source file" >> $LOGFILE
fi

cd $TMPDIR

# Rar the source file (20M per RAR file, no compression)
bigWrite "Creating rar files:" 
rar a "${PREFIX}-${DATE}.rar" -v20m -m0 "${FILE}.enc" >> $LOGFILE 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Could not rar file, exiting..." >> $LOGFILE
  exit 1
else
  echo "Finished creating rar files" >> $LOGFILE
fi

# Par the rar files ( 10% par, 7 par files, tune as needed )
bigWrite "Creating par files:"
par2create -r10 -n7 "${PREFIX}-${DATE}.par2" "*.rar" >> $LOGFILE 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Could not par file, exiting..." >> $LOGFILE
  exit 1
else
  echo "Finished creating par files" >> $LOGFILE
fi

rm "${FILE}.enc" >/dev/null 2>&1

# Generate newspost command (we dont need -u and -p if NEWSUSER and NEWSPASS aren't required)
POSTCMD="newspost -i $NEWSSERVER" 
if [ -n $NEWSUSER ]; then 
  POSTCMD="$POSTCMD -u $NEWSUSER"
  if [ -n $NEWSPASS ]; then
    POSTCMD="$POSTCMD -p $NEWSPASS"
  fi
fi

POSTCMD="$POSTCMD -f $NEWSMAIL -n $NEWSGROUP -y -s "${PREFIX}-${DATE}" ${TMPDIR}/*.part*.rar ${TMPDIR}/*.par2" 

# Run the newspost command
bigWrite "Posting to usenet:"
$POSTCMD >> $LOGFILE 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Could not upload file, exiting..." >> $LOGFILE
  exit 1
else
  echo "Finished posting to usenet" >> $LOGFILE
fi

rm -r -- $TMPDIR >/dev/null 2>&1

#!/bin/bash

#
# Copyright (c) 2017, Carnegie Mellon University.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the University nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
# HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
# WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

### instant death on misc errors ###
set -euo pipefail

######################
# Tunable parameters #
######################

# "n" - normal send run: RPC, vary request size and limit
n_protos=("na+sm" "bmi+tcp")                    # protocols to test
n_sizes=(4 64 256 1024 2048 4096)               # RPC snd size ("-i" flag)
n_limits=(1 2 4 8 16)                           # outstanding RPCs ("-l" flag)
n_repeats=3                                     # repeat runs
n_nrpcs=100000                                  # nrpcs in 1 run ("-c" flag)
n_timeout=120                                   # timeout  ("-t" flag)

# "b" - bulk read run: RPC, vary bulk read size and limit
b_protos=("na+sm" "bmi+tcp")                    # protocols to test
b_Sizes=(2m)                                    # bulk sizes ("-S" flag)
b_limits=(1 2)                                  # outstanding RPCs ("-l" flag)
b_repeats=5                                     # repeat runs
b_nrpcs=10000                                   # nrpcs in 1 run ("-c" flag)
b_timeout=300                                   # timeout  ("-t" flag)

dryrun=1                                        # set to 1 for script debug

instances=(1)                                   # currently not changing this
###############
# Core script #
###############

source @CMAKE_INSTALL_PREFIX@/scripts/common.sh

message "Script begin..."
# keep track of start time so we can see how long this takes
timein=`date`

get_jobdir

runner="${dfsu_prefix}/bin/mercury-runner"

message ">>> Output is available in $jobdir"

#
# run_one: run one instance
#
# uses: jobdir, dryrun
# Arguments:
# @1 protocol to use
# @2 number of mercury instances
# @3 req size ("-s")
# @4 bulk send size ("-S")
# @5 outstanding RPC limit ("-l")
# @6 current current iteration number
# @7 number of rpcs ("-c")
# @8 number repeats we target
# @9 timeout
run_one() {
    proto="$1"
    num="$2"
    reqsz=$3
    bulksz=$4
    limit=$5
    iter=$6
    nrpcs=$7
    repeats=$8
    timeo=$9

    now=`date`

    message ""
    message "====================================================="
    message "Starting new test at: ${now}"
    message "Testing protocol '$proto' with $num Mercury instances"
    message "reqsz=${reqsz:-'n/a'}, bulksz=${bulksz:-'n/a'}, limit=$limit, nrpcs=$nrpcs"
    message "Iteration $iter out of $repeats"
    message "====================================================="
    message ""

    saddress="h0=${proto}"
    caddress="h1=${proto}"

    # generate log file names (maybe they should be passed in?)
    if [ ! -d $jobdir/$proto ]; then
        mkdir -p $jobdir/$proto
    fi
    if [ x$bulksz != x ]; then
        clogfile=$jobdir/$proto/bcli-$proto-$num-$bulksz-$limit-$iter-log.txt
        slogfile=$jobdir/$proto/bsrv-$proto-$num-$bulksz-$limit-$iter-log.txt
    else
        clogfile=$jobdir/$proto/ncli-$proto-$num-$reqsz-$limit-$iter-log.txt
        slogfile=$jobdir/$proto/nsrv-$proto-$num-$reqsz-$limit-$iter-log.txt
    fi

    # build command line
    cmd="$runner -d ${jobdir} -c ${nrpcs} -l $limit -q -r $iter -t ${timeo}"
    if [ x$bulksz != x ]; then
        cmd="$cmd -S $bulksz -L $bulksz"
    fi
    if [ x$reqsz != x ]; then
        cmd="$cmd -i $reqsz"
    fi

    srvr_cmd="$cmd -m s $num $saddress"
    clnt_cmd="$cmd -m c $num $caddress $saddress"

    # start the server
    message "!!! NOTICE !!! starting server (Instances: $num, Address spec: $saddress)..."
    if [ $dryrun = 1 ]; then
        message "DRY RUN SERVER -> $srvr_cmd"
    else
        do_mpirun 1 1 "" "" "$srvr_cmd" "" "$logfile" "$slogfile" &
        server_pid=$!
    fi

    sleep 0.1

    # Start the client
    message "!!! NOTICE !!! starting client (Instances: $num, Address spec: $caddress)..."
    message "Please be patient while the test is in progress..."
    if [ $dryrun = 1 ]; then
        message "DRY RUN CLIENT -> $clnt_cmd"
    else
        do_mpirun 1 1 "" "" "$clnt_cmd" "" "$logfile" "$clogfile"
    fi

    # Collect return codes
    if [ x$dryrun != x ]; then
        client_ret=0      # fake return values
        server_ret=0
    else
        client_ret=$?
        wait $server_pid
        server_ret=$?
    fi

    if [[ $client_ret != 0 || $server_ret != 0 ]]; then
        if [ $client_ret != 0 ]; then
            message "!!! ERROR !!! client returned $client_ret."
        fi
        if [ $server_ret != 0 ]; then
            message "!!! ERROR !!! server returned $server_ret."
        fi
    else
        message "Test completed successfully."
    fi

    now=`date`
    message "Finished at ${now}"
}

# do normal test first
now=`date`
message "== Starting normal tests: ${now}"
for proto in ${n_protos[@]-}; do
    for num in ${instances[@]-}; do
        for sz in ${n_sizes[@]-}; do
            for lm in ${n_limits[@]-}; do

                if [[ $proto == "bmi+tcp" && $num -gt 1 ]]; then
                    continue;  # BMI doesn't do well with >1 instances
                fi

                i=1
                while [ $i -le $n_repeats ]; do
                    run_one $proto $num $sz "" $lm $i $n_nrpcs \
                            $n_repeats $n_timeout
                    i=$((i + 1))
                done

            done
        done
    done
done
now=`date`
message "DONE normal tests: ${now}"

message "Generate result files"
for proto in ${n_protos[@]-}; do
    for num in ${instances[@]-}; do
        for sz in ${n_sizes[@]-}; do
            find ${jobdir}/${proto} -iname "n*-${proto}-${num}-${sz}-*" | xargs cat | \
                ${dfsu_prefix}/scripts/process_runner.pl > \
                ${jobdir}/norm-${proto}-${num}-${sz}.result
            if [ ! -s ${jobdir}/norm-${proto}-${num}-${sz}.result ]; then
                message "!!! WARN !!! NO RESULTS: ${jobdir}/norm-${proto}-${num}-${sz}"
                rm -f ${jobdir}/norm-${proto}-${num}-${sz}.result
            fi
        done
    done
done
message "DONE generate result files"


# do bulk test next
now=`date`
message "== Starting bulk tests: ${now}"
for proto in ${b_protos[@]-}; do
    for num in ${instances[@]-}; do
        for sz in ${b_Sizes[@]-}; do
            for lm in ${b_limits[@]-}; do

                if [[ $proto == "bmi+tcp" && $num -gt 1 ]]; then
                    continue;  # BMI doesn't do well with >1 instances
                fi

                i=1
                while [ $i -le $b_repeats ]; do
                    run_one $proto $num "" $sz $lm $i $b_nrpcs \
                            $b_repeats $b_timeout
                    i=$((i + 1))
                done

            done
        done
    done
done
now=`date`
message "DONE bulk tests: ${now}"

message "Generate result files"
for proto in ${b_protos[@]-}; do
    for num in ${instances[@]-}; do
        for sz in ${b_Sizes[@]-}; do
            find ${jobdir}/${proto} -iname "b*-${proto}-${num}-${sz}-*" | xargs cat | \
                ${dfsu_prefix}/scripts/process_runner.pl > \
                ${jobdir}/bulk-${proto}-${num}-${sz}.result
            if [ ! -s ${jobdir}/bulk-${proto}-${num}-${sz}.result ]; then
                message "!!! WARN !!! NO RESULTS: ${jobdir}/bulk-${proto}-${num}-${sz}"
                rm -f ${jobdir}/bulk-${proto}-${num}-${sz}.result
            fi
        done
    done
done
message "DONE generate result files"

message "== Listing results ..."
for result in $(find $jobdir -iname "*.result"); do
    message ""
    message "$result"
    cat $result | tee -a $logfile
    message ""
    message "----------"
done
message "DONE listing results"

# overall time
timeout=`date`
message "Script complete."
message "start: ${timein}"
message "  end: ${timeout}"

exit 0

# BIDIR
# ./mercury-runner -d . -m cs 1 h1=na+sm h0
# ./mercury-runner -d . -m cs 1 h0=na+sm h1

# ONE DIR
# ./mercury-runner -d . -m s 1 h0=na+sm 
# ./mercury-runner -d . -m c 1 h1=na+sm h0

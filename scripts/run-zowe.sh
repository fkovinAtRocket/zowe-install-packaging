#!/bin/sh

################################################################################
# This program and the accompanying materials are made available under the terms of the
# Eclipse Public License v2.0 which accompanies this distribution, and is available at
# https://www.eclipse.org/legal/epl-v20.html
#
# SPDX-License-Identifier: EPL-2.0
#
# Copyright IBM Corporation 2018
################################################################################

#
# Script to start node server and Atlas server.
#
#
# Your JCL must invoke it like this:
#
# //        EXEC PGM=BPXBATSL,REGION=0M,TIME=NOLIMIT,
# //  PARM='PGM /bin/sh &SRVRPATH/../scripts/internal/run-zowe.sh'
#
#
#export "NODE_PATH='"$ZOWE_ROOT_DIR"/zlux-example-server/bin':$NODE_PATH"
export NODE_HOME=$nodehome
`dirname $0`/../../zlux-example-server/bin/nodeServer.sh --allowInvalidTLSProxy=true &
`dirname $0`/../../api-mediation/scripts/api-mediation-start-discovery.sh
`dirname $0`/../../api-mediation/scripts/api-mediation-start-catalog.sh
`dirname $0`/../../api-mediation/scripts/api-mediation-start-gateway.sh
`dirname $0`/../../explorer-server/wlp/lib/native/zos/s390x/bbgzsrv Atlas


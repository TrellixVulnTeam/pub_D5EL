#!/usr/bin/env perl
#
#
# This program implements a SNMP agent for MySQL servers
#
# (c) Copryright 2008, 2009 - Brice Figureau
#
# The INNODB parsing code is originally Copyright 2008 Baron Schwartz,
# and was released as GPL,v2.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.    See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

use strict;

my $VERSION = "v1.0";
$VERSION = eval $VERSION;

## Packages ##
package InnoDBParser;

use strict;
use warnings;
use Data::Dumper;

# Math::BigInt reverts to perl only
# automatically if GMP is not installed
use Math::BigInt try => 'GMP';

sub new {
   bless {}, shift;
}

sub parse_innodb_status {
    my $self = shift;
    my $lines = shift;
    my %status = (
        'current_transactions' => 0,
        'locked_transactions'  => 0,
        'active_transactions'  => 0,
        'current_transactions'  => 0,
        'locked_transactions'   => 0,
        'active_transactions'   => 0,
        'innodb_locked_tables'  => 0,
        'innodb_tables_in_use'  => 0,
        'innodb_lock_structs'   => 0,
        'innodb_lock_wait_secs' => 0,
        'pending_normal_aio_reads'  => 0,
        'pending_normal_aio_writes' => 0,
        'pending_ibuf_aio_reads'    => 0,
        'pending_aio_log_ios'       => 0,
        'pending_aio_sync_ios'      => 0,
        'pending_log_flushes'       => 0,
        'pending_buf_pool_flushes'  => 0,
        'file_reads'                => 0,
        'file_writes'               => 0,
        'file_fsyncs'               => 0,
        'ibuf_inserts'              => 0,
        'ibuf_merged'               => 0,
        'ibuf_merges'               => 0,
        'log_bytes_written'         => 0,
        'unflushed_log'             => 0,
        'log_bytes_flushed'         => 0,
        'pending_log_writes'        => 0,
        'pending_chkp_writes'       => 0,
        'log_writes'                => 0,
        'pool_size'                 => 0,
        'free_pages'                => 0,
        'database_pages'            => 0,
        'modified_pages'            => 0,
        'pages_read'                => 0,
        'pages_created'             => 0,
        'pages_written'             => 0,
        'queries_inside'            => 0,
        'queries_queued'            => 0,
        'read_views'                => 0,
        'rows_inserted'             => 0,
        'rows_updated'              => 0,
        'rows_deleted'              => 0,
        'rows_read'                 => 0,
        'innodb_transactions'       => 0,
        'unpurged_txns'             => 0,
        'history_list'              => 0,
        'current_transactions'      => 0,
        'hash_index_cells_total'    => 0,
        'hash_index_cells_used'     => 0,
        'total_mem_alloc'           => 0,
        'additional_pool_alloc'     => 0,
        'last_checkpoint'           => 0,
        'uncheckpointed_bytes'      => 0,
        'ibuf_used_cells'           => 0,
        'ibuf_free_cells'           => 0,
        'ibuf_cell_count'           => 0,
        'adaptive_hash_memory'      => 0,
        'page_hash_memory'          => 0,
        'dictionary_cache_memory'   => 0,
        'file_system_memory'        => 0,
        'lock_system_memory'        => 0,
        'recovery_system_memory'    => 0,
        'thread_hash_memory'        => 0,
        'innodb_sem_waits'          => 0,
        'innodb_sem_wait_time_ms'   => 0
    );
    my $flushed_to;
    my $innodb_lsn;
    my $purged_to;
    my @spin_waits;
    my @spin_rounds;
    my @os_waits;
    my $txn_seen = 0;
    my $merged_op_seen = 0;

    foreach my $line (@$lines) {
        my @row = split(/ +/, $line);

        # SEMAPHORES
        if ($line =~ m/Mutex spin waits/) {
            push(@spin_waits,  $self->tonum($row[3]));
            push(@spin_rounds, $self->tonum($row[5]));
            push(@os_waits,    $self->tonum($row[8]));
        }
        elsif ($line =~ m/RW-shared spins/) {
            push(@spin_waits, $self->tonum($row[2]));
            push(@spin_waits, $self->tonum($row[8]));
            push(@os_waits,   $self->tonum($row[5]));
            push(@os_waits,   $self->tonum($row[11]));
        }
        elsif ($line =~ /seconds the semaphore:/) {
           # --Thread 907205 has waited at handler/ha_innodb.cc line 7156 for 1.00 seconds the semaphore:
           $status{'innodb_sem_waits'} += 1;
           $status{'innodb_sem_wait_time_ms'} += $self->tonum($row[9]) * 1000;
        }

        # TRANSACTIONS
        elsif ($line =~ m/Trx id counter/) {
            # The beginning of the TRANSACTIONS section: start counting
            # transactions
            # Trx id counter 0 1170664159
            # Trx id counter 861B144C
            $status{'innodb_transactions'} = $self->make_bigint($row[3], $row[4]);
            $txn_seen = 1;
        }
        elsif ($line =~ m/Purge done for trx/) {
            # Purge done for trx's n:o < 0 1170663853 undo n:o < 0 0
            # Purge done for trx's n:o < 861B135D undo n:o < 0
            $purged_to = $self->make_bigint($row[6], $row[7] eq 'undo' ? undef : $row[7]);
            $status{'unpurged_txns'} = $status{'innodb_transactions'} - $purged_to;
        }
        elsif ($line =~ m/History list length/) {
            $status{'history_list'} = $self->tonum($row[3]);
        }
        elsif ($txn_seen && $line =~ m/---TRANSACTION/) {
            $status{'current_transactions'} = $status{'current_transactions'} + 1;
            if ($line =~ m/ACTIVE/) {
                $status{'active_transactions'} = $status{'active_transactions'} + 1;
            }
        }
        elsif ($txn_seen && $line =~ m/------- TRX HAS BEEN/) {
           # ------- TRX HAS BEEN WAITING 32 SEC FOR THIS LOCK TO BE GRANTED:
           $status{'innodb_lock_wait_secs'} = $self->tonum($row[5]);
        }
        elsif ($line =~ m/read views open inside/) {
            $status{'read_views'} = $self->tonum($row[0]);
        }
        elsif ($line =~ m/mysql tables in use/) {
           # mysql tables in use 2, locked 2
           $status{'innodb_tables_in_use'} += $self->tonum($row[4]);
           $status{'innodb_locked_tables'} += $self->tonum($row[6]);
        }
        elsif ($txn_seen && $line =~ m/lock struct\(s\)/) {
            # 23 lock struct(s), heap size 3024, undo log entries 27
            # LOCK WAIT 12 lock struct(s), heap size 3024, undo log entries 5
            # LOCK WAIT 2 lock struct(s), heap size 368
            if ( $line =~ m/LOCK WAIT/ ) {
               $status{'innodb_lock_structs'} += $self->tonum($row[2]);
               $status{'locked_transactions'} += 1;
            }
            else {
                $status{'innodb_lock_structs'} += $self->tonum($row[0]);
            }
        }
        # FILE I/O
        elsif ($line =~ m/OS file reads/) {
            $status{'file_reads'}  = $self->tonum($row[0]);
            $status{'file_writes'} = $self->tonum($row[4]);
            $status{'file_fsyncs'} = $self->tonum($row[8]);
        }
        elsif ($line =~ m/Pending normal aio/) {
            $status{'pending_normal_aio_reads'}  = $self->tonum($row[4]);
            $status{'pending_normal_aio_writes'} = $self->tonum($row[7]);
        }
        elsif ($line =~ m/ibuf aio reads/) {
            $status{'pending_ibuf_aio_reads'} = $self->tonum($row[4]);
            $status{'pending_aio_log_ios'}    = $self->tonum($row[7]);
            $status{'pending_aio_sync_ios'}   = $self->tonum($row[10]);
        }
        elsif ($line =~ m/Pending flushes \(fsync\)/) {
            $status{'pending_log_flushes'}      = $self->tonum($row[4]);
            $status{'pending_buf_pool_flushes'} = $self->tonum($row[7]);
        }
        # INSERT BUFFER AND ADAPTIVE HASH INDEX
        elsif ($line =~ m/^Ibuf for space 0: size /) {
           # Older InnoDB code seemed to be ready for an ibuf per tablespace.  It
           # had two lines in the output.  Newer has just one line, see below.
           # Ibuf for space 0: size 1, free list len 887, seg size 889, is not empty
           # Ibuf for space 0: size 1, free list len 887, seg size 889,
           $status{'ibuf_used_cells'} = $self->tonum($row[5]);
           $status{'ibuf_free_cells'} = $self->tonum($row[9]);
           $status{'ibuf_cell_count'} = $self->tonum($row[12]);
        }
        elsif ($line =~ m/^Ibuf: size /) {
           # Ibuf: size 1, free list len 4634, seg size 4636,
           $status{'ibuf_used_cells'} = $self->tonum($row[2]);
           $status{'ibuf_free_cells'} = $self->tonum($row[6]);
           $status{'ibuf_cell_count'} = $self->tonum($row[9]);
           if ($line =~ m/merges$/) {
             # newer innodb plugin
             $status{'ibuf_merges'}  = $self->tonum($row[10]);
           }
        }
        elsif ($line =~ m/ merged recs, /) {
           # 19817685 inserts, 19817684 merged recs, 3552620 merges
           $status{'ibuf_inserts'} = $self->tonum($row[0]);
           $status{'ibuf_merged'}  = $self->tonum($row[2]);
           $status{'ibuf_merges'}  = $self->tonum($row[5]);
        }
        elsif ($line =~ m/merged operations:/) {
           #merged operations:
           # insert 0, delete mark 0, delete 0
           $merged_op_seen = 1;
        }
        elsif ($merged_op_seen && $line =~ m/ insert \d+, delete mark/) {
           #merged operations:
           # insert 0, delete mark 0, delete 0
           $status{'ibuf_inserts'} = $self->tonum($1);
        }
        elsif ($line =~ m/^Hash table size /) {
           # In some versions of InnoDB, the used cells is omitted.
           # Hash table size 4425293, used cells 4229064, ....
           # Hash table size 57374437, node heap has 72964 buffer(s) <-- no used cells
           $status{'hash_index_cells_total'} = $self->tonum($row[3]);
           $status{'hash_index_cells_used'} = $line =~ m/used cells/ ? $self->tonum($row[6]) : '0';
        }
        # LOG
        elsif ($line =~ m/ log i\/o's done, /) {    #'
            $status{'log_writes'} = $self->tonum($row[0]);
        }
        elsif ($line =~ m/ pending log writes, /) {
            $status{'pending_log_writes'}  = $self->tonum($row[0]);
            $status{'pending_chkp_writes'} = $self->tonum($row[4]);
        }
        elsif ($line =~ m/^Log sequence number/) {
            # This number is NOT printed in hex in InnoDB plugin.
            # Log sequence number 13093949495856 //plugin
            # Log sequence number 125 3934414864 //normal
            $innodb_lsn = defined($row[4]) ? $self->make_bigint($row[3], $row[4]) : $self->tonum($row[3]);
        }
        elsif ($line =~ m/^Log flushed up to/) {
            # This number is NOT printed in hex in InnoDB plugin.
            # Log flushed up to   13093948219327
            # Log flushed up to   125 3934414864
            $flushed_to = defined($row[5]) ? $self->make_bigint($row[4], $row[5]) : $self->tonum($row[4]);
        }
        elsif ($line =~ m/^Last checkpoint at/) {
           # Last checkpoint at  125 3934293461
           $status{'last_checkpoint'} = defined($row[4]) ? $self->make_bigint($row[3], $row[4]) : $self->tonum($row[3]);
        }
        # BUFFER POOL AND MEMORY
        elsif ($line =~ m/^Total memory allocated/) {
           # Total memory allocated 29642194944; in additional pool allocated 0
           $status{'total_mem_alloc'}       = $self->tonum($row[3]);
           $status{'additional_pool_alloc'} = $self->tonum($row[8]);
        }
        elsif($line =~ m/Adaptive hash index /) {
           #   Adaptive hash index 1538240664   (186998824 + 1351241840)
           $status{'adaptive_hash_memory'} = $self->tonum($row[4]);
        }
        elsif($line =~ m/Page hash           /) {
           #   Page hash           11688584
           $status{'page_hash_memory'} = $self->tonum($row[3]);
        }
        elsif($line =~ m/Dictionary cache    /) {
           #   Dictionary cache    145525560    (140250984 + 5274576)
           $status{'dictionary_cache_memory'} = $self->tonum($row[3]);
        }
        elsif($line =~ m/File system         /) {
           #   File system         313848   (82672 + 231176)
           $status{'file_system_memory'} = $self->tonum($row[3]);
        }
        elsif($line =~ m/Lock system/) {
           #   Lock system         29232616     (29219368 + 13248)
           $status{'lock_system_memory'} = $self->tonum($row[3]);
        }
        elsif($line =~ m/Recovery system     /) {
           #   Recovery system     0    (0 + 0)
           $status{'recovery_system_memory'} = $self->tonum($row[3]);
        }
        elsif($line =~ m/Threads             /) {
           #   Threads             409336   (406936 + 2400)
           $status{'thread_hash_memory'} = $self->tonum($row[2]);
        }
        elsif($line =~ m/innodb_io_pattern   /) {
           #   innodb_io_pattern   0    (0 + 0)
           $status{'innodb_io_pattern_memory'} = $self->tonum($row[2]);
        }
        elsif ($line =~ m/Buffer pool size /) {
            # The " " after size is necessary to avoid matching the wrong line:
            # Buffer pool size        1769471
            # Buffer pool size, bytes 28991012864
            $status{'pool_size'} = $self->tonum($row[3]);
        }
        elsif ($line =~ m/Free buffers/) {
            $status{'free_pages'} = $self->tonum($row[2]);
        }
        elsif ($line =~ m/Database pages/) {
            $status{'database_pages'} = $self->tonum($row[2]);
        }
        elsif ($line =~ m/Modified db pages/) {
            $status{'modified_pages'} = $self->tonum($row[3]);
        }
        elsif ($line =~ m/Pages read/) {
            $status{'pages_read'}    = $self->tonum($row[2]);
            $status{'pages_created'} = $self->tonum($row[4]);
            $status{'pages_written'} = $self->tonum($row[6]);
        }
        # ROW OPERATIONS
        elsif ($line =~ m/Number of rows inserted/) {
            $status{'rows_inserted'} = $self->tonum($row[4]);
            $status{'rows_updated'}  = $self->tonum($row[6]);
            $status{'rows_deleted'}  = $self->tonum($row[8]);
            $status{'rows_read'}     = $self->tonum($row[10]);
        }
        elsif ($line =~ m/queries inside InnoDB/) {
            $status{'queries_inside'} = $self->tonum($row[0]);
            $status{'queries_queued'} = $self->tonum($row[4]);
        }
    }

    # Derive some values from other values.
    $status{'unflushed_log'} = $innodb_lsn - $flushed_to;
    $status{'log_bytes_written'} = $innodb_lsn;
    $status{'log_bytes_flushed'} = $flushed_to;
    $status{'uncheckpointed_bytes'} = $status{'log_bytes_written'} - $status{'last_checkpoint'};

    my $val;
    foreach $val (@spin_waits) {
        $status{'spin_waits'} += $val;
    }

    foreach $val (@spin_rounds) {
        $status{'spin_rounds'} += $val;
    }

    foreach $val (@os_waits) {
        $status{'os_waits'} += $val;
    }
    return \%status;
}

# takes only numbers from a string
sub tonum {
    my $self = shift;
    my $str = shift;
    return 0 if !$str;
    return new Math::BigInt $1 if $str =~ m/(\d+)/;
    return 0;
}

# return a 64 bit number from either an hex encoding or
# a hi lo representation
sub make_bigint {
    my ($self, $hi, $lo) = @_;
    unless ($lo) {
        $hi = new Math::BigInt '0x' . $hi;
        return $hi;
    }

    $hi = new Math::BigInt $hi;
    $lo = new Math::BigInt $lo;
 
    return $lo->badd($hi->blsft(32));
}

# end of package InnoDBParser

package main;

use strict;
use warnings;
use Carp;
use Data::Dumper;
use Unix::Syslog qw(:subs :macros);
use Getopt::Long qw(:config auto_help auto_version no_ignore_case);
use POSIX qw( setsid );
use DBI;
use DBD::mysql;
use Pod::Usage;

my %opt = (
    daemon_pid => '/var/run/mysql-snmp.pid',
    oid        => '1.3.6.1.4.1.20267.200.1',
    port       => 3306,
    refresh    => 300,
    master     => 1,
    slave      => 0,
    innodb     => 1,
    procs      => 0,
    host       => 'localhost',
    heartbeat  => ''
);

my %global_status       = ();
my $global_last_refresh = 0;
my $error   = 0;
# this will hold a table of conversion between numerical oids and oidnames
my %oids    = ();
my $lowestOid;
my $highestOid;
my @ks;
my $regOID;

# various types & definitions
my @types = (
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 1 - 4
    'Gauge32',   'Counter64', 'Gauge32',   'Gauge32',      # 5 - 8
    'Gauge32',   'Gauge32',   'Gauge32',   'Gauge32',      # 9 - 12
    'Gauge32',   'Gauge32',   'Counter32', 'Counter32',    # 13 - 16
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 17 - 20
    'Counter32', 'Gauge32',   'Gauge32',   'Gauge32',      # 21 - 24
    'Gauge32',   'Gauge32',   'Gauge32',   'Gauge32',      # 25 - 28
    'Gauge32',   'Gauge32',   'Counter32', 'Counter32',    # 29 - 32
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 33 - 36
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 37 - 40
    'Counter32', 'Counter32', 'Counter32', 'Gauge32',      # 41 - 44
    'Gauge32',   'Counter32', 'Counter32', 'Counter32',    # 45 - 48
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 49 - 52
    'Counter32', 'Gauge32',   'Gauge32',   'Counter32',    # 53 - 56
    'Gauge32',   'Gauge32',   'Gauge32',   'Counter32',    # 57 - 60
    'Gauge32',   'Gauge32',   'Counter32', 'Gauge32',      # 61 - 64
    'Gauge32',   'Gauge32',   'Gauge32',   'Counter32',    # 65 - 68
    'Counter32', 'Counter32', 'Counter32', 'Gauge32',      # 69 - 72
    'Gauge32',   'Counter32', 'Counter32', 'Counter32',    # 73 - 76
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 77 - 80
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 81 - 84
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 85 - 88
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 89 - 92
    'Counter32', 'Counter32', 'Counter32', 'Counter32',    # 93 - 96
    'Counter32', 'Counter64', 'Counter64', 'Gauge32',      # 97 - 100
    'Gauge32',   'Counter64', 'Counter64', 'Counter32',    # 101 - 104
    'Gauge32',   'Counter32', 'Counter32', 'Counter32',    # 105 - 108
    'Gauge32',   'Gauge32',   'Gauge32',   'Gauge32',      # 109 - 112
    'Gauge32',   'Gauge32',   'Gauge32',   'Gauge32',      # 113 - 116
    'Gauge32',   'Gauge32',   'Gauge32',   'Gauge32',      # 117 - 120
    'Gauge32',   'Gauge32',   'Gauge32',   'Gauge32',      # 121 - 124
    'Counter64', 'Counter64', 'Gauge32',   'Gauge32',      # 125 - 128
    'Gauge32',   'Gauge32',   'Gauge32',   'Gauge32',      # 129 - 132
    'Gauge32',   'Gauge32',   'Gauge32',   'Gauge32',      # 133 - 136
    'Counter64', 'Counter64', 'Counter64', 'Counter64',    # 137 - 140
    'Counter64', 'Counter64', 'Counter64', 'Counter64',    # 141 - 144
    'Counter64', 'Counter64', 'Counter64', 'Counter64',    # 145 - 148
    'Counter64', 'Counter64',                              # 149 - 150
);

my @newkeys = (
    'myKeyReadRequests',          'myKeyReads',                  # 1 - 2
    'myKeyWriteRequests',         'myKeyWrites',                 # 3 - 4
    'myHistoryList',              'myInnodbTransactions',        # 5 - 6
    'myReadViews',                'myCurrentTransactions',       # 7 - 8
    'myLockedTransactions',       'myActiveTransactions',        # 9 - 10
    'myPoolSize',                 'myFreePages',                 # 11 - 12
    'myDatabasePages',            'myModifiedPages',             # 13 - 14
    'myPagesRead',                'myPagesCreated',              # 15 - 16
    'myPagesWritten',             'myFileFsyncs',                # 17 - 18
    'myFileReads',                'myFileWrites',                # 19 - 20
    'myLogWrites',                'myPendingAIOLogIOs',          # 21 - 22
    'myPendingAIOSyncIOs',        'myPendingBufPoolFlushes',     # 23 - 24
    'myPendingChkpWrites',        'myPendingIbufAIOReads',       # 25 - 26
    'myPendingLogFlushes',        'myPendingLogWrites',          # 27 - 28
    'myPendingNormalAIOReads',    'myPendingNormalAIOWrites',    # 29 - 30
    'myIbufInserts',              'myIbufMerged',                # 31 - 32
    'myIbufMerges',               'mySpinWaits',                 # 33 - 34
    'mySpinRounds',               'myOsWaits',                   # 35 - 36
    'myRowsInserted',             'myRowsUpdated',               # 37 - 38
    'myRowsDeleted',              'myRowsRead',                  # 39 - 40
    'myTableLocksWaited',         'myTableLocksImmediate',       # 41 - 42
    'mySlowQueries',              'myOpenFiles',                 # 43 - 44
    'myOpenTables',               'myOpenedTables',              # 45 - 46
    'myInnodbOpenFiles',          'myOpenFilesLimit',            # 47 - 48
    'myTableCache',               'myAbortedClients',            # 49 - 50
    'myAbortedConnects',          'myMaxUsedConnections',        # 51 - 52
    'mySlowLaunchThreads',        'myThreadsCached',             # 53 - 54
    'myThreadsConnected',         'myThreadsCreated',            # 55 - 56
    'myThreadsRunning',           'myMaxConnections',            # 57 - 58
    'myThreadCacheSize',          'myConnections',               # 59 - 60
    'mySlaveRunning',             'mySlaveStopped',              # 61 - 62
    'mySlaveRetriedTransactions', 'mySlaveLag',                  # 63 - 64
    'mySlaveOpenTempTables',      'myQcacheFreeBlocks',          # 65 - 66
    'myQcacheFreeMemory',         'myQcacheHits',                # 67 - 68
    'myQcacheInserts',            'myQcacheLowmemPrunes',        # 69 - 70
    'myQcacheNotCached',          'myQcacheQueriesInCache',      # 71 - 72
    'myQcacheTotalBlocks',        'myQueryCacheSize',            # 73 - 74
    'myQuestions',                'myComUpdate',                 # 75 - 76
    'myComInsert',                'myComSelect',                 # 77 - 78
    'myComDelete',                'myComReplace',                # 79 - 80
    'myComLoad',                  'myComUpdateMulti',            # 81 - 82
    'myComInsertSelect',          'myComDeleteMulti',            # 83 - 84
    'myComReplaceSelect',         'mySelectFullJoin',            # 85 - 86
    'mySelectFullRangeJoin',      'mySelectRange',               # 87 - 88
    'mySelectRangeCheck',         'mySelectScan',                # 89 - 90
    'mySortMergePasses',          'mySortRange',                 # 91 - 92
    'mySortRows',                 'mySortScan',                  # 93 - 94
    'myCreatedTmpTables',         'myCreatedTmpDiskTables',      # 95 - 96
    'myCreatedTmpFiles',          'myBytesSent',                 # 97 - 98
    'myBytesReceived',            'myInnodbLogBufferSize',       # 99 - 100
    'myUnflushedLog',             'myLogBytesFlushed',           # 101 - 102
    'myLogBytesWritten',          'myRelayLogSpace',             # 103 - 104
    'myBinlogCacheSize',          'myBinlogCacheDiskUse',        # 105 - 106
    'myBinlogCacheUse',           'myBinaryLogSpace',            # 107 - 108
    'myStateClosingTables',       'myStateCopyingToTmpTable',    # 109 - 110
    'myStateEnd',                 'myStateFreeingItems',         # 111 - 112
    'myStateInit',                'myStateLocked',               # 113 - 114
    'myStateLogin',               'myStatePreparing',            # 115 - 116
    'myStateReadingFromNet',      'myStateSendingData',          # 117 - 118
    'myStateSortingResult',       'myStateStatistics',           # 119 - 120
    'myStateUpdating',            'myStateWritingToNet',         # 121 - 122
    'myStateNone',                'myStateOther',                # 123 - 124
    'myAdditionalPoolAlloc',      'myTotalMemAlloc',             # 125 - 126
    'myHashIndexCellsTotal',      'myHashIndexCellsUsed',        # 127 - 128
    'myInnoDBLockStructs',        'myInnoDBLockWaitSecs',        # 129 - 130
    'myInnoDBTablesInUse',        'myInnoDBLockedTables',        # 131 - 132
    'myUncheckpointedBytes',      'myIBufCellCount',             # 133 - 134
    'myIBufUsedCells',            'myIBufFreeCells',             # 135 - 136
    'myAdaptiveHashMemory',       'myPageHashMemory',            # 137 - 138
    'myDictionaryCacheMemory',    'myFileSystemMemory',          # 139 - 140
    'myLockSystemMemory',         'myRecoverySystemMemory',      # 141 - 142
    'myThreadHashMemory',         'myInnoDBSemWaits',            # 143 - 144
    'myInnoDBSemWaitTime',        'myKeyBufBytesUnflushed',      # 145 - 146
    'myKeyBufBytesUsed',          'myKeyBufferSize',             # 147 - 148
    'myInnoDBRowLockTime',        'myInnoDBRowLockWaits',        # 149 - 150
);

my @oldkeys = (
    'Key_read_requests',          'Key_reads',                     # 1 - 2
    'Key_write_requests',         'Key_writes',                    # 3 - 4
    'history_list',               'innodb_transactions',           # 5 - 6
    'read_views',                 'current_transactions',          # 7 - 8
    'locked_transactions',        'active_transactions',           # 9 - 10
    'pool_size',                  'free_pages',                    # 11 - 12
    'database_pages',             'modified_pages',                # 13 - 14
    'pages_read',                 'pages_created',                 # 15 - 16
    'pages_written',              'file_fsyncs',                   # 17 - 18
    'file_reads',                 'file_writes',                   # 19 - 20
    'log_writes',                 'pending_aio_log_ios',           # 21 - 22
    'pending_aio_sync_ios',       'pending_buf_pool_flushes',      # 23 - 24
    'pending_chkp_writes',        'pending_ibuf_aio_reads',        # 25 - 26
    'pending_log_flushes',        'pending_log_writes',            # 27 - 28
    'pending_normal_aio_reads',   'pending_normal_aio_writes',     # 29 - 30
    'ibuf_inserts',               'ibuf_merged',                   # 31 - 32
    'ibuf_merges',                'spin_waits',                    # 33 - 34
    'spin_rounds',                'os_waits',                      # 35 - 36
    'rows_inserted',              'rows_updated',                  # 37 - 38
    'rows_deleted',               'rows_read',                     # 39 - 40
    'Table_locks_waited',         'Table_locks_immediate',         # 41 - 42
    'Slow_queries',               'Open_files',                    # 43 - 44
    'Open_tables',                'Opened_tables',                 # 45 - 46
    'innodb_open_files',          'open_files_limit',              # 47 - 48
    'table_cache',                'Aborted_clients',               # 49 - 50
    'Aborted_connects',           'Max_used_connections',          # 51 - 52
    'Slow_launch_threads',        'Threads_cached',                # 53 - 54
    'Threads_connected',          'Threads_created',               # 55 - 56
    'Threads_running',            'max_connections',               # 57 - 58
    'thread_cache_size',          'Connections',                   # 59 - 60
    'slave_running',              'slave_stopped',                 # 61 - 62
    'Slave_retried_transactions', 'slave_lag',                     # 63 - 64
    'Slave_open_temp_tables',     'Qcache_free_blocks',            # 65 - 66
    'Qcache_free_memory',         'Qcache_hits',                   # 67 - 68
    'Qcache_inserts',             'Qcache_lowmem_prunes',          # 69 - 70
    'Qcache_not_cached',          'Qcache_queries_in_cache',       # 71 - 72
    'Qcache_total_blocks',        'query_cache_size',              # 73 - 74
    'Questions',                  'Com_update',                    # 75 - 76
    'Com_insert',                 'Com_select',                    # 77 - 78
    'Com_delete',                 'Com_replace',                   # 79 - 80
    'Com_load',                   'Com_update_multi',              # 81 - 82
    'Com_insert_select',          'Com_delete_multi',              # 83 - 84
    'Com_replace_select',         'Select_full_join',              # 85 - 86
    'Select_full_range_join',     'Select_range',                  # 87 - 88
    'Select_range_check',         'Select_scan',                   # 89 - 90
    'Sort_merge_passes',          'Sort_range',                    # 91 - 92
    'Sort_rows',                  'Sort_scan',                     # 93 - 94
    'Created_tmp_tables',         'Created_tmp_disk_tables',       # 95 - 96
    'Created_tmp_files',          'Bytes_sent',                    # 97 - 98
    'Bytes_received',             'innodb_log_buffer_size',        # 99 - 100
    'unflushed_log',              'log_bytes_flushed',             # 101 - 102
    'log_bytes_written',          'relay_log_space',               # 103 - 104
    'binlog_cache_size',          'Binlog_cache_disk_use',         # 105 - 106
    'Binlog_cache_use',           'binary_log_space',              # 107 - 108
    'State_closing_tables',       'State_copying_to_tmp_table',    # 109 - 110
    'State_end',                  'State_freeing_items',           # 111 - 112
    'State_init',                 'State_locked',                  # 113 - 114
    'State_login',                'State_preparing',               # 115 - 116
    'State_reading_from_net',     'State_sending_data',            # 117 - 118
    'State_sorting_result',       'State_statistics',              # 119 - 120
    'State_updating',             'State_writing_to_net',          # 121 - 122
    'State_none',                 'State_other',                   # 123 - 124
    'additional_pool_alloc',      'total_mem_alloc',               # 125 - 126
    'hash_index_cells_total',     'hash_index_cells_used',         # 127 - 128
    'innodb_lock_structs',        'innodb_lock_wait_secs',         # 129 - 130
    'innodb_tables_in_use',       'innodb_locked_tables',          # 131 - 132
    'uncheckpointed_bytes',       'ibuf_cell_count',               # 133 - 134
    'ibuf_used_cells',            'ibuf_free_cells',               # 135 - 136
    'adaptive_hash_memory',       'page_hash_memory',              # 137 - 138
    'dictionary_cache_memory',    'file_system_memory',            # 139 - 140
    'lock_system_memory',         'recovery_system_memory',        # 141 - 142
    'thread_hash_memory',         'innodb_sem_waits',              # 143 - 144
    'innodb_sem_wait_time_ms',    'key_buf_bytes_unflushed',       # 145 - 146
    'key_buf_bytes_used',         'key_buffer_size',               # 147 - 148
    'Innodb_row_lock_time',       'Innodb_row_lock_waits',         # 149 - 150
);

# daemonize the program

sub max {
    my ($a, $b) = @_;
    return $a if $a > $b;
    return $b;
}

sub bigint($) {
    my $str = shift;
    return Math::BigInt->bzero() if !$str;
    return new Math::BigInt $1 if $str =~ m/(\d+)/;
    return Math::BigInt->bzero();
}

# This function has been translated from PHP to Perl from the
# excellent Baron Schwartz's MySQL Cacti Templates
sub fetch_mysql_data {
    my ($datasource, $dbuser, $dbpass) = @_;
    my %output;
    eval {
        my $dbh = DBI->connect($datasource, $dbuser, $dbpass, {RaiseError => 1, AutoCommit => 1});
        if (!$dbh) {
            dolog(LOG_CRIT, "Can't connect to database: $datasource, $@");
            return;
        }

        my %status = (
            'transactions'         => 0,
            'relay_log_space'      => 0,
            'binary_log_space'     => 0,
            'slave_lag'            => 0,
            'slave_running'        => 0,
            'slave_stopped'        => 0,
            'State_closing_tables'       => 0,
            'State_copying_to_tmp_table' => 0,
            'State_end'                  => 0,
            'State_freeing_items'        => 0,
            'State_init'                 => 0,
            'State_locked'               => 0,
            'State_login'                => 0,
            'State_preparing'            => 0,
            'State_reading_from_net'     => 0,
            'State_sending_data'         => 0,
            'State_sorting_result'       => 0,
            'State_statistics'           => 0,
            'State_updating'             => 0,
            'State_writing_to_net'       => 0,
            'State_none'                 => 0,
            'State_other'                => 0,
            'have_innodb'                =>'YES',
        );

        my $result = $dbh->selectall_arrayref("SHOW /*!50002 GLOBAL */ STATUS");
        foreach my $row (@$result) {
            $status{$row->[0]} = $row->[1];
        }

        # Get SHOW VARIABLES and convert the name-value array into a simple
        # associative array.
        $result = $dbh->selectall_arrayref("SHOW VARIABLES");
        foreach my $row (@$result) {
            $status{$row->[0]} = $row->[1];
        }

        # Make table_open_cache backwards-compatible.
        if ( defined($status{'table_open_cache'}) ) {
           $status{'table_cache'} = $status{'table_open_cache'};
        }

        if ($opt{slave}) {
            $result = $dbh->selectall_arrayref("SHOW SLAVE STATUS", { Slice => {} });

            foreach my $row (@$result)
            {
                # Must lowercase keys because different versions have different
                # lettercase.
                my %newrow = map { lc($_) => $row->{$_} } keys %$row;
                $status{'relay_log_space'}  = $newrow{'relay_log_space'};
                $status{'slave_lag'}        = $newrow{'seconds_behind_master'};

                # Check replication heartbeat, if present.
                if ( $opt{heartbeat} ne '' ) {
                    my $row2 = $dbh->selectrow_arrayref("SELECT GREATEST(0, UNIX_TIMESTAMP() - UNIX_TIMESTAMP(ts) - 1) FROM $opt{heartbeat} WHERE server_id != \@\@SERVER_ID ORDER BY ts DESC LIMIT 1");
                    $status{'slave_lag'} = $row2->[0];
                }

                $status{'slave_running'} = ($newrow{'slave_sql_running'} eq 'Yes') ? 1 : 0;
                $status{'slave_stopped'} = ($newrow{'slave_sql_running'} eq 'Yes') ? 0 : 1;
            }
        }

        # Get info on master logs.
        my @binlogs = (0);
        if ($opt{master} && $status{'log_bin'} eq 'ON') {    # See issue #8
            $result = $dbh->selectall_arrayref(
                "SHOW MASTER LOGS",
                {Slice => {}}
            );
            foreach my $row (@$result) {
                my %newrow = map {lc($_) => $row->{$_}} keys %$row;

                # Older versions of MySQL may not have the File_size column in the
                # results of the command.
                if (exists($newrow{'file_size'}) && $newrow{'file_size'} > 0) {
                    push(@binlogs, $newrow{'file_size'});
                }
                else {
                    last;
                }
            }
        }

        if (scalar @binlogs) {
            $status{'binary_log_space'} = 0;
            foreach my $log (@binlogs) {
                $status{'binary_log_space'} += $log;
            }
        }

        # Get SHOW INNODB STATUS and extract the desired metrics from it.
        if ($opt{innodb} && $status{'have_innodb'} eq 'YES') {
            my $innodb_array = $dbh->selectall_arrayref("SHOW /*!50000 ENGINE*/ INNODB STATUS",{Slice => {}});
            my @lines = split("\n", $innodb_array->[0]{'Status'});

            my $innodb_parser = InnoDBParser->new();
            my $out = $innodb_parser->parse_innodb_status(\@lines);
 
            # Override values from InnoDB parsing with values from SHOW STATUS,
            # because InnoDB status might not have everything and the SHOW STATUS is
            # to be preferred where possible.
            my %overrides = (
               'Innodb_buffer_pool_pages_data'  => 'database_pages',
               'Innodb_buffer_pool_pages_dirty' => 'modified_pages',
               'Innodb_buffer_pool_pages_free'  => 'free_pages',
               'Innodb_buffer_pool_pages_total' => 'pool_size',
               'Innodb_buffer_pool_reads'       => 'pages_read',
               'Innodb_data_fsyncs'             => 'file_fsyncs',
               'Innodb_data_pending_reads'      => 'pending_normal_aio_reads',
               'Innodb_data_pending_writes'     => 'pending_normal_aio_writes',
               'Innodb_os_log_pending_fsyncs'   => 'pending_log_flushes',
               'Innodb_pages_created'           => 'pages_created',
               'Innodb_pages_read'              => 'pages_read',
               'Innodb_pages_written'           => 'pages_written',
               'Innodb_rows_deleted'            => 'rows_deleted',
               'Innodb_rows_inserted'           => 'rows_inserted',
               'Innodb_rows_read'               => 'rows_read',
               'Innodb_rows_updated'            => 'rows_updated',
            );

            # If the SHOW STATUS value exists, override...
            foreach my $key (keys %overrides) {
               if ( defined($status{$key}) ) {
                  $out->{$overrides{$key}} = $status{$key};
               }
            }
 
            foreach my $key (keys %$out) {
                $status{$key} = $out->{$key};
            }
 
            if (defined($status{'unflushed_log'})) {
                # it seems that unflushed_log is sometimes not defined...
                $status{'unflushed_log'} = max($status{'unflushed_log'}, $status{'innodb_log_buffer_size'});
            }
        }

        $status{'key_buf_bytes_used'} = bigint($status{'key_buffer_size'})->bsub(bigint($status{'Key_blocks_unused'})->bmul($status{'key_cache_block_size'}));
        $status{'key_buf_bytes_unflushed'} = bigint($status{'Key_blocks_not_flushed'})->bmul(bigint($status{'key_cache_block_size'}));

        # Get SHOW PROCESSLIST and aggregate it by state, then add it to the array
        # too.
        if ( $opt{procs} ) {
            $result = $dbh->selectall_arrayref("SHOW PROCESSLIST",{Slice => {}});
            foreach my $row (@$result) {
                my %newrow = map {lc($_) => $row->{$_}} keys %$row;
                my $state = $newrow{'State'};
                if ( !defined($state) ) {
                    $state = 'NULL';
                }
                if ( $state eq '' ) {
                    $state = 'none';
                }
                $state = lc($state);
                $state =~ s/ /_/;
                if ( defined($status{"State_$state"}) ) {
                    $status{"State_$state"} += 1;
                }
                else {
                    $status{"State_other"} += 1;
                }
            }
        }
 
        $dbh->disconnect();

        my %trans;
        my $i = 0;
        foreach my $key (@oldkeys) {
            $trans{$key} = $newkeys[$i++];
        }
 
        foreach my $key (keys %status) {
            $output{$trans{$key}} = $status{$key} if (exists($trans{$key}));
        }
   
    };
    if ($@) {
        dolog(LOG_CRIT, "can't refresh data from mysql: $@\n");
        return (undef, undef, undef);
    }
    
    return (\@newkeys, \@types, \%output);
}

###
### Called automatically now and then
### Refreshes the $global_status and $global_variables
### caches.
###
sub refresh_status {
    my $startOID = shift;
    my $dsn      = shift;
    my $now      = time();

    # Check if we have been called quicker than once every $refresh
    if (($now - $global_last_refresh) < $opt{refresh}) {
        # if yes, do not do anything
        dolog(LOG_DEBUG, "not refreshing: " . ($now - $global_last_refresh) . " < $opt{refresh}") if ($opt{verbose});
        return;
    }
    my ($oid, $types, $status) = fetch_mysql_data($dsn, $opt{user}, $opt{password});
    #print Dumper(\$oid);
    #print Dumper(\$types);
    #print Dumper(\$status);
  
    if ($oid) {
        dolog(LOG_DEBUG, "Setting error to 0") if ($opt{verbose});
        $error = 0;
        my $index = 0;
        foreach my $key (@$oid) {
            $global_status{$key}{'value'} = $status->{$key};
            $global_status{$key}{'type'}  = $types->[$index];
            $index++;
        }
   
        dolog(LOG_DEBUG, "Refreshed at $now " . (time() - $now)) if ($opt{verbose});
        print Dumper(\%global_status) if ($opt{verbose});
    }
    else {
        dolog(LOG_DEBUG, "Setting error to 1") if ($opt{verbose});
        $error = 1;
    }
    foreach my $key (@$oid) {
        $global_status{$key}{'value'}=0 if (!defined ($global_status{$key}{'value'}));
        $global_status{$key}{'value'}=0 unless($global_status{$key}{'value'});
    	print "MYSQL::"."$key".".0 = ".$global_status{$key}{'type'}.":".$global_status{$key}{'value'}."\n";
    }
    $global_last_refresh = $now;
    return;
}

sub dolog {
    my ($level, $msg) = @_;
    syslog($level, $msg);
    print STDERR $msg . "\n" if ($opt{verbose});
}

sub VersionMessage {
    print "mysql-snmp $VERSION by zhung.根据开源程序修改,向劳动者致敬。\n";
}

#main 
GetOptions(
    \%opt,
    'host|h=s',
    'port|P=i',
    'user|u=s',
    'password|p=s',
    'config|c=s',
    'master|m!',
    'slave|s!',
    'innodb|i!',
    'oid|o=s',
    'procs|l|process-list!',
    'refresh|r=i',
    'daemon_pid|daemon-pid=s',
    'heartbeat|b=s',
    'no-daemon|n',
    'man',
    'usage',
    'verbose|v+',
    'version|V' => sub {VersionMessage()},
) or pod2usage(-verbose => 0);

#print Dumper(\%opt);
pod2usage(-verbose => 0) if $opt{usage};
pod2usage(-verbose => 1) if $opt{help};
pod2usage(-verbose => 2) if $opt{man};

my $dsn = 'DBI:mysql:';
if ($opt{config}) {
    $dsn .= "mysql_read_default_file=$opt{config}";
}
else {
    $dsn .= join(';', "host=$opt{host}", "port=$opt{port}");
}

openlog("mysql-snmp", LOG_PID | LOG_PERROR, LOG_DAEMON);

if ($opt{verbose}) {
    foreach my $k (@ks) {
        dolog(LOG_DEBUG, "$k -> " . $oids{$k}->{'name'});
    }
}
refresh_status($opt{oid}, $dsn);

__END__

=head1 NAME

    mysql-snmp - report mysql statistics via SNMP

=head1 SYNOPSIS

    mysql-snmp [options]

    -h HOST, --host=HOST      connect to MySQL DB on HOST
    -P PORT, --port=PORT      port to connect (default 3306)
    -u USER, --user=USER      use USER as user to connect to mysql
    -p PASS, --password=PASS  use PASS as password to connect to mysql
    -c FILE, --config=FILE    read mysql connection details from FILE
    -m, --master              check master
    -s, --slave               check slave
    -b, --heartbeat DB.TABLE  table for checking slave lag with mk-hearbeat
    -i, --innodb              read innodb settings
    -o OID, --oid=OID         registering OID
    -l, --process-list, --procs  enable the process list
    -r INT, --refresh=INT     set refresh interval to INT (seconds)
    --daemon-pid=FILE         write PID to FILE instead of $default{pid}
    -n, --no-daemon           do not detach and become a daemon
    -v, --verbose             be verbose about what you do

    -?, --help                display this help and exit
    --usage                   display detailed usage information
    --man                     display program man page
    -V, --version             output version information and exit

=head1 OPTIONS

=over 8

=item B<-h HOST, --host=HOST>

connect to MySQL DB on HOST

=item B<-P PORT, --port=PORT>

port to connect (default 3306)

=item B<-u USER, --user=USER>

use USER as user to connect to mysql

=item B<-p PASS, --password=PASS>

use PASS as password to connect to mysql

=item B<-c FILE, --config=FILE>

read mysql connection details from file FILE.

These should be stored in a section named [client]. Eg:

  [client]
  host=dbserver
  port=3306
  user=monitor
  password=secret

=item B<-m, --master>

check master

=item B<-s, --slave>

check slave

=item B<-b DB.TABLE, --heartbeat DB.TABLE>

specifies the table containing the mk-heartbeat timestamp for computing slave lag

=item B<-i, --innodb>

check innodb details

=item B<-o OID, --oid=OID>

registering OID

=item B<-l, --process-list, --procs>

enable the process list

=item B<-r INT, --refresh=INT>

refresh interval in seconds

=item B<--daemon-pid=FILE>

write PID to FILE instead of $default{pid}

=item B<-n, --no-daemon>

do not detach and become a daemon

=item B<-v, --verbose>

be verbose about what you do

=item B<--man>

Prints the manual page and exits.

=item B<--usage>

Prints detailed usage information and exits.

=item B<-?, --help>

Print a brief help message and exits.

=item B<-V, --version>

output version information and exit

=back

=head1 DESCRIPTION

B<mysql-snmp> is a small daemon that connects to a local snmpd daemon
to report statistics on a local or remote MySQL server.

=cut

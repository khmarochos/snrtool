#!/usr/local/bin/perl
#
#   snr, Collects, stores and shows SNR for Lucent AcessPoint devices.
#   Copyright (C) 2001  V.Melnik <melnik@raccoon.kiev.ua>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

use strict;
use DBI;
use POSIX qw(setsid);
use FindBin qw($Bin);
use RRDs;

use lib "$Bin/../lib";

use debug qw(:debug_levels);
use snr::config;
use snr::configure;
use snr::ap;

my $timestamp = time;

my $conf = snr::configure->new();
unless (defined($conf)) {
    exit(1);
}

my($debug, $debug_err) = debug->new(
    debug_level     => $conf->{debug_level},
    syslog_ident    => 'snr',
    logfile         => $conf->{log_file}
);
unless (defined($debug)) {
    print(STDERR "Can't able logging: $debug_err\n");
    exit(1);
}

if (-e $conf->{pid_file}) {
    if ((stat($conf->{pid_file}))[8] >= $timestamp - 3600) {
        $debug->write(DEBUG_ERRORS,
            "Found a pid-file '$conf->{pid_file}', is it my brother?");
        exit(1);
    } else {
        $debug->write(DEBUG_WARNINGS,
            "Found a stale lock-file '$conf->{pid_file}', ignoring it");
    }
}

$debug->write(DEBUG_ACTIONS, "Writing a pid-file '$conf->{pid_file}'");
unless (open(PF, ">$conf->{pid_file}")) {
    $debug->write(DEBUG_ERRORS, "Can't write a pid-file '$conf->{pid_file}'");
    exit(1);
}
print(PF $$);
unless (close(PF)) {
    $debug->write(DEBUG_WARNINGS,
        "Can't close a pid-file (pretty strange, isn't it?)");
}

$debug->write(DEBUG_ACTIONS, "Fetching information about bases");
my %ap_list;
foreach my $ap_name (glob("$conf->{rrd_dir}/*")) {
#    $ap_name =~ s/^.+\/([^\/]+)$/\1/g;
    $ap_name =~ s/^\Q$conf->{rrd_dir}\E\/(.+)$/\1/g;
    if ($ap_name !~ /^\w[\w\-\.]*$/) {
        $debug->write(DEBUG_WARNINGS,
            "Directory '$ap_name' is possibly insecure");
        next;
    }
    if (-d "$conf->{rrd_dir}/$ap_name") {
        $debug->write(DEBUG_ACTIONS, "Found base '$ap_name'");
        unless (defined(open(
            AP_COMM,
            "$conf->{rrd_dir}/$ap_name/.community"
        ))) {
            $debug->write(DEBUG_WARNINGS,
                "Can't open community file for '$ap_name'");
            next;
        }
        my $ap_comm;
        while (<AP_COMM>) {
            chomp;
            if ($_ =~ /^\s*(\w+)\s*$/) {
                $ap_comm = $1;
            }
        }
        unless (close(AP_COMM)) {
            $debug->write(DEBUG_WARNINGS,
                "Can't close commynity file for '$ap_name'");
        }
        $ap_list{$ap_name} = $ap_comm;
    }
}

$debug->write(DEBUG_ACTIONS, "Gathering link quality statistics for AP-stations");

$SIG{HUP}       = \&signal_main;
$SIG{TERM}      = \&signal_main;
$SIG{QUIT}      = \&signal_main;
$SIG{INT}       = \&signal_main;

my %children_list;
my $shutdown;
foreach my $ap_name (keys(%ap_list)) {
    last if ($shutdown);
    catch_child() if (scalar(values(%children_list)) >= $conf->{max_children});
    my $ap_comm = $ap_list{$ap_name};
    $debug->write(DEBUG_ACTIONS, "Trying to fork link quality tester");
    my $new_pid;
    if (defined($new_pid = fork)) {
        if ($new_pid) {
            $children_list{$new_pid} = $ap_name;
            $debug->write(DEBUG_NOTES,
                "New child ($new_pid) has born for '$ap_name'"
            );
        } else {
            unless (setsid) {
                $debug->write(DEBUG_ERRORS, "Can't detach a session");
                exit;
            }
            $SIG{HUP}       = \&signal_child;
            $SIG{TERM}      = \&signal_child;
            $SIG{QUIT}      = \&signal_child;
            $SIG{INT}       = \&signal_child;
            tester($ap_name, $ap_comm, $debug);
            exit;
        }
    } else {
        $debug->write->(DEBUG_ERRORS, "Can't fork link quality tester: $!");
    }
}

while (scalar(values(%children_list))) {
    catch_child();
}

unless (unlink($conf->{pid_file})) {
    $debug->write(DEBUG_WARNINGS,
        "Can't unlink a pid-file '$conf->{pid_file}'");
}

$debug->close;

exit;

#
# Additional subrotines
#

sub signal_main {
    my $signal = shift;
    $debug->write(DEBUG_EVENTS, "Got signal 'SIG$signal', terminating kids");
    foreach my $child (keys(%children_list)) {
        kill(1, keys(%children_list));
    }
    $shutdown = 1;
}

sub signal_child {
    my $signal = shift;
    $debug->write(DEBUG_EVENTS, "Got signal 'SIG$signal', terminating job");
    $shutdown = 1;
}

sub catch_child {
    if (my $dead_child = wait) {
        $debug->write(DEBUG_NOTES, "Child '$dead_child' is dead");
        delete($children_list{$dead_child});
    }
}

sub tester {
    my($ap_name, $ap_comm, $debug) = @_;
    $0 = "snr.pl [testing $ap_name]";
    $debug->write(DEBUG_ACTIONS, "Initializing device '$ap_name'");
    my($ap, $ap_error) = snr::ap->new(
        -debug          => $debug,
        -ap_addr        => $ap_name,
        -ap_comm        => $ap_comm
    );
    if (defined($ap)) {
        if ($ap->{peers_up} > 0) {
            foreach my $i (1..$ap->{peers_up}) {
                my $pname;
                last if ($shutdown);
                $debug->write(DEBUG_ACTIONS,
                    "Testing '$ap->{peers_names}{$i}' at '$ap_name'");
                my $test_result = $ap->test($i);
                unless (defined($test_result)) {
                    $debug->write(DEBUG_WARNINGS,
                        "Can't get link quality stats of '$ap_name':",
                        $ap->{error});
                    next;
                }
                my $sig_l = $test_result->{".1.3.6.1.4.1.762.2.5.2.1.52.$i"};
                my $noi_l = $test_result->{".1.3.6.1.4.1.762.2.5.2.1.53.$i"};
                my $snr_l = $test_result->{".1.3.6.1.4.1.762.2.5.2.1.51.$i"};
                my $pkl_l = eval {
                    ($test_result->{".1.3.6.1.4.1.762.2.5.2.1.30.$i"} -
                    $test_result->{".1.3.6.1.4.1.762.2.5.2.1.31.$i"}) /
                    $test_result->{".1.3.6.1.4.1.762.2.5.2.1.30.$i"}
                } * 100;
                my $sig_r = $test_result->{".1.3.6.1.4.1.762.2.5.2.1.48.$i"};
                my $noi_r = $test_result->{".1.3.6.1.4.1.762.2.5.2.1.49.$i"};
                my $snr_r = $test_result->{".1.3.6.1.4.1.762.2.5.2.1.47.$i"};
                my $pkl_r = eval {
                    ($test_result->{".1.3.6.1.4.1.762.2.5.2.1.28.$i"} -
                    $test_result->{".1.3.6.1.4.1.762.2.5.2.1.29.$i"}) /
                    $test_result->{".1.3.6.1.4.1.762.2.5.2.1.28.$i"}
                } * 100;
                $debug->write(DEBUG_NOTES,
                    "'$ap->{peers_names}{$i}' have: " .
                    "SIG_L = $sig_l " .
                    "NOI_L = $noi_l " .
                    "SNR_L = $snr_l " .
                    "PKL_L = $pkl_l " .
                    "SIG_R = $sig_r " .
                    "NOI_R = $noi_r " .
                    "SNR_R = $snr_r " .
                    "PKL_R = $pkl_r");
                $debug->write(DEBUG_ACTIONS,
                    "Updating log-records for '$ap->{peers_names}{$i}'");
                unless ($pname = get_pname($debug, $conf, $ap, $i)) {
                    $debug->write(DEBUG_WARNINGS,
                        "Can't identify '$ap->{peers_names}{$i}'");
                    next;
                }
                $debug->write(DEBUG_ACTIONS,
                    "Updating log-records for '$ap->{peers_names}{$i}'");
                RRDs::update(
                    $pname,
                    "--template",
                    "sig_l:noi_l:snr_l:pkl_l:sig_r:noi_r:snr_r:pkl_r",
                    "N" . ":" .
                    "$sig_l:$noi_l:$snr_l:$pkl_l" . ":" .
                    "$sig_r:$noi_r:$snr_r:$pkl_r"
                );
                if (RRDs::error) {
                    $debug->write(DEBUG_ERRORS,
                        "Can't update log-records for",
                        "'$ap->{peers_names}{$i}':",
                        RRDs::error);
                    next;
                }
            }
        } else {
            $debug->write(DEBUG_WARNINGS,
                "Can't find any peer on '$ap_name'");
        }
        $ap->close;
    } else {
        $debug->write(DEBUG_ERRORS,
            "Can't initialize device '$ap_name': $ap_error");
    }
}

sub get_pname {
    my($debug, $conf, $ap, $i) = @_;
    my $pname;
    my $pname_desired =
        $conf->{rrd_dir} .
        "/" .
        $ap->{ap_addr} .
        "/" .
        $ap->{peers_macaddrs}{$i} . "-" . $ap->{peers_names}{$i} . ".rrd";
    if ($ap->{peers_macaddrs}{$i} !~ /^0x\w{12}$/) {
        $debug->write(DEBUG_WARNINGS,
            "MAC-address '$ap->{peers_macaddrs}{$i}' is possibly insecure");
        return($pname);
    }
    if ($ap->{peers_names}{$i} !~ /^\w[\w\s\-\.]*$/) {
        $debug->write(DEBUG_WARNINGS,
            "Name '$ap->{peers_names}{$i}' is possibly insecure");
        return($pname);
    }
    $debug->write(DEBUG_ACTIONS,
        "Determining RRD of peer '$ap->{peers_names}{$i}'");
    unless (($pname) = glob(
        "$conf->{rrd_dir}/$ap->{ap_addr}/$ap->{peers_macaddrs}{$i}-*.rrd"
    )) {
        $debug->write(DEBUG_EVENTS,
            "Found a new peer at '$ap->{ap_addr}':",
            "'$ap->{peers_names}{$i}'",
            "'$ap->{peers_macaddrs}{$i}'"
        );
        RRDs::create(
            $pname_desired,
            "-s", 300,
            "DS:sig_l:GAUGE:600:0:100",
            "DS:noi_l:GAUGE:600:0:100",
            "DS:snr_l:GAUGE:600:0:100",
            "DS:pkl_l:GAUGE:600:0:100",
            "DS:sig_r:GAUGE:600:0:100",
            "DS:noi_r:GAUGE:600:0:100",
            "DS:snr_r:GAUGE:600:0:100",
            "DS:pkl_r:GAUGE:600:0:100",
            "RRA:AVERAGE:0.5:1:1200",
            "RRA:AVERAGE:0.5:12:2400"
        );
        if (RRDs::error) {
            $debug->write(DEBUG_WARNINGS,
                "Can't create RRD for peer",
                "'$ap->{peers_names}{$i}'",
                "'$ap->{peers_macaddrs}{$i}':",
                RRDs::error);
        } else {
            $pname = $pname_desired;
        }
    }
    return($pname);
}

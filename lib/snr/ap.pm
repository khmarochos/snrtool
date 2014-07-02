# 
#   snr, Collects, stores and shows SNR for Lucent AcessPoint devices.
#   Copyright (C) 2001  V.Melnik <melnik@raccoon.kiev.ua>
#
#   NOTE: This is not a standalone library, it's just a module!
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

package snr::ap;

use strict;

use Exporter;
use vars qw(@ISA);

use Net::SNMP;
use FindBin qw($Bin);

use lib "$Bin/../lib";

use debug qw(:debug_levels);
use snr::config;

@ISA            = qw(Exporter);

sub new {
    my($class, %argv) = @_;
    my $self = {
        debug           => undef,
        ap_addr         => undef,
        ap_comm         => undef,
        snmp_session    => undef,
        peers_up        => 0,
        peers_names     => {},
        peers_macaddrs  => {},
        error           => undef
    };
    bless($self, $class);
    foreach (keys(%argv)) {
        if (/^-?debug$/) {
            $self->{debug} = $argv{$_};
        } elsif (/^-?ap_addr/i) {
            $self->{ap_addr} = $argv{$_};
        } elsif (/^-?ap_comm$/i) {
            $self->{ap_comm} = $argv{$_};
        } else {
            return(undef, "Unknown parameter $_");
        }
    }
    # Opening SNMP-session
    $self->{debug}->write(DEBUG_ACTIONS,
        "Connecting to $self->{ap_comm}\@$self->{ap_addr} via SNMP");
    my($snmp_session, $snmp_error) = Net::SNMP->session(
        -retries    => 3,
        -hostname   => $self->{ap_addr},
        -community  => $self->{ap_comm});
    unless (defined($snmp_session)) {
        $self->{debug}->write(DEBUG_ERRORS, 
            "Can't connect to $self->{ap_comm}\@$self->{ap_addr}: $snmp_error");
        return(undef, "Can't open SNMP-session");
    }
    # Sending initializing sequence
    $self->{debug}->write(DEBUG_ACTIONS,
        "Initializing $self->{ap_comm}\@$self->{ap_addr}");
    my @ap_init = (
        ['.1.3.6.1.4.1.762.2.5.5.1', INTEGER, 50],
        ['.1.3.6.1.4.1.762.2.5.5.2', INTEGER, 50],
        ['.1.3.6.1.4.1.762.2.5.5.3', INTEGER, 50],
        ['.1.3.6.1.4.1.762.2.5.4.1', INTEGER, 3],
        ['.1.3.6.1.4.1.762.2.5.4.2', INTEGER, 3],
        ['.1.3.6.1.4.1.762.2.5.4.3', INTEGER, 3]);
    foreach my $ap_init_val (@ap_init) {
        my $snmp_result = $snmp_session->set_request(
            @$ap_init_val[0],
            @$ap_init_val[1],
            @$ap_init_val[2]);
        unless (defined($snmp_result)) {
            $self->{debug}->write(DEBUG_ERRORS,
                "Can't initialize $self->{ap_comm}\@$self->{ap_addr}:",
                $snmp_session->error);
            return(undef, "Can't initialize device");
        }
    }
    sleep(3);
    # Fetching number of active peers
    $self->{debug}->write(DEBUG_ACTIONS,
        "Fetching number of active peers on $self->{ap_addr}");
    my $peers_up = $snmp_session->get_request('.1.3.6.1.4.1.762.2.5.1.0');
    unless (defined($peers_up)) {
        $self->{debug}->write(DEBUG_ERRORS,
            "Can't fetch number of active peers $self->{ap_addr}: ".
            $snmp_session->error);
        return(undef, "Can't fetch number of active peers");
    }
    $peers_up = $peers_up->{'.1.3.6.1.4.1.762.2.5.1.0'};
    $self->{debug}->write(DEBUG_NOTES,
        "Found $peers_up active peer(s) on $self->{ap_addr}");
    foreach my $i (1..$peers_up) {
        # Filling $self->{peers_names}
        $self->{debug}->write(DEBUG_ACTIONS,
            "Determining station name of peer number $i");
        my $peer_sn = $snmp_session->get_request(
            ".1.3.6.1.4.1.762.2.5.2.1.3.$i");
        unless (defined($peer_sn)) {
            $self->{debug}->write(DEBUG_WARNINGS,
                "Can't determine station name of peer number $i: ".
                $snmp_session->error);
            next;
        }
        $peer_sn = $peer_sn->{".1.3.6.1.4.1.762.2.5.2.1.3.$i"};
        $self->{debug}->write(DEBUG_NOTES,
            "Peer number $i called as '$peer_sn'");
        ${$self->{peers_names}}{$i} = $peer_sn;
        # Filling $self->{peers_macaddrs}
        $self->{debug}->write(DEBUG_ACTIONS,
            "Determining MAC-address of peer '$peer_sn'");
        my $peer_mac = $snmp_session->get_request(
            ".1.3.6.1.4.1.762.2.5.2.1.11.$i");
        unless (defined($peer_mac)) {
            $self->{debug}->write(DEBUG_WARNINGS,
                "Can't determine MAC-address of peer '$peer_sn': ".
                $snmp_session->error);
            next;
        }
        $peer_mac = $peer_mac->{".1.3.6.1.4.1.762.2.5.2.1.11.$i"};
        $self->{debug}->write(DEBUG_NOTES,
            "Peer '$peer_sn' has a MAC-address $peer_mac");
        ${$self->{peers_macaddrs}}{$i} = $peer_mac;
    }
    # OK, we are ready for any tests
    $self->{snmp_session}   = $snmp_session;
    $self->{peers_up}       = $peers_up;
    return($self);
}

sub close {
    my $self = shift;
    $self->{debug}->write(DEBUG_ACTIONS, "Closing SNMP-session");
    $self->{snmp_session}->close;
}

sub test {
    my $self = shift;
    my $i = shift;
    unless ($i) {
        $self->{debug}->write(0, "NIHUYA SEBE!");
        $self->{debug}->write(0, "Unspecified number of peer, fuck the developer!");
        $self->{error} = "Unspecified number of peer";
        return(undef, undef);
    }
    $self->{debug}->write(DEBUG_ACTIONS, "Testing link quality of $self->{peers_names}{$i}");
    my $snmp_result = $self->{snmp_session}->set_request(
        ".1.3.6.1.4.1.762.2.5.2.1.27.$i", INTEGER, 1500);
    unless (defined($snmp_result)) {
        $self->{debug}->write(DEBUG_WARNINGS,
            "Can't test link quality of $self->{peers_names}{$i}:",
            $self->{snmp_session}->error);
        $self->{error} = "Can't run tests";
        return(undef);
    }
    sleep(1);
    my $snmp_result = $self->{snmp_session}->set_request(
        ".1.3.6.1.4.1.762.2.5.2.1.25.$i", INTEGER, 24);
    unless (defined($snmp_result)) {
        $self->{debug}->write(DEBUG_WARNINGS,
            "Can't test link quality of $self->{peers_names}{i}:",
            $self->{snmp_session}->error);
        $self->{error} = "Can't run tests";
        return(undef);
    }
    sleep(4);
    my @request = (
        ".1.3.6.1.4.1.762.2.5.2.1.28.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.29.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.30.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.31.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.47.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.48.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.49.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.51.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.52.$i",
        ".1.3.6.1.4.1.762.2.5.2.1.53.$i"
    );
    $self->{debug}->write(DEBUG_ACTIONS,
        "Determining test-results for peer $self->{peers_names}{$i}");
    my $test_result = $self->{snmp_session}->get_request(@request);
    unless (defined($test_result)) {
        $self->{debug}->write(DEBUG_WARNINGS,
            "Can't determine test-results for peer $self->{peers_names}{$i}: ".
            $self->{snmp_session}->error);
        $self->{error} = "Can't get results of test";
    }
    $self->{debug}->write(DEBUG_ACTIONS,
        "Stopping tests of $self->{peers_names}{$i}");
    my $snmp_result = $self->{snmp_session}->set_request(
        ".1.3.6.1.4.1.762.2.5.2.1.25.$i", INTEGER, 0);
    unless (defined($snmp_result)) {
        $self->{debug}->write(DEBUG_WARNINGS,
            "Can't stop testing link quality of $self->{peers_names}{$i}:",
            $self->{snmp_session}->error);
    }
    return($test_result);
}


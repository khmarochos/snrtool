#!/usr/bin/perl
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
use POSIX qw(strftime);
use CGI;
use GD;
use GD::Text::Align;
use GD::Graph::lines;
use RRDs;
use FindBin qw($Bin);

use lib "$Bin/../lib";
use snr::config;

my $query = new CGI;
my $base = $query->param('base');
my $peer = $query->param('peer');
my $step = $query->param('step');
my $type = $query->param('type');

my @wts;

print $query->header(
    -type       => "image/png",
    -expires    => '+10m');

if ($base !~ /^\w[\w\-\.]*$/) {
    display_error("Base '$base' is possibly insecure");
    exit(-1);
}
if ($peer !~ /^0x\w{12}-\w[\w\s\-\.]*$/) {
    display_error("Peer '$peer' is possibly insecure");
    exit(-1);
}

my $rrd = "$Bin/../rrd/$base/$peer.rrd";

RRDs::graph(
    "-",
    "-s", time - $step,
    "-h", "300",
    "-w", "500",
    "-t", $peer,
    "DEF:t_sig_l=$rrd:sig_l:AVERAGE",
    "DEF:t_noi_l=$rrd:noi_l:AVERAGE",
    "DEF:t_snr_l=$rrd:snr_l:AVERAGE",
    "DEF:t_pkl_l=$rrd:pkl_l:AVERAGE",
    "DEF:t_sig_r=$rrd:sig_r:AVERAGE",
    "DEF:t_noi_r=$rrd:noi_r:AVERAGE",
    "DEF:t_snr_r=$rrd:snr_r:AVERAGE",
    "DEF:t_pkl_r=$rrd:pkl_r:AVERAGE",
    "CDEF:sig_l=t_sig_l",
    "CDEF:noi_l=t_noi_l",
    "CDEF:snr_l=t_snr_l",
    "CDEF:pkl_l=t_pkl_l",
    "CDEF:sig_r=0,t_sig_r,-",
    "CDEF:noi_r=0,t_noi_r,-",
    "CDEF:snr_r=0,t_snr_r,-",
    "CDEF:pkl_r=0,t_pkl_r,-",
    "AREA:sig_l#00cf00:Local Signal     ",
    "AREA:sig_r#008f00:Remote Signal\\l",
    "AREA:noi_l#cfcfcf:Local Noise      ",
    "AREA:noi_r#9f9f9f:Remote Noise\\l",
    "LINE1:snr_l#000000:Local SNR        ",
    "LINE1:snr_r#000000:Remote SNR\\l",
    "LINE1:pkl_l#ff0000:Local Packet Test",
    "LINE1:pkl_r#cf0000:Remote Packet Test\\l",
    "GPRINT:t_sig_l:AVERAGE:Local Signal = %3.0lf       ",
    "GPRINT:t_sig_r:AVERAGE:Remote Signal = %3.0lf  \\r",
    "GPRINT:t_noi_l:AVERAGE:Local Noise = %3.0lf        ",
    "GPRINT:t_noi_r:AVERAGE:Remote Noise = %3.0lf  \\r",
    "GPRINT:t_snr_l:AVERAGE:Local SNR = %3.0lf          ",
    "GPRINT:t_snr_r:AVERAGE:Remote SNR = %3.0lf  \\r",
    "GPRINT:t_pkl_l:AVERAGE:Local Packet Test = %3.0lf %%",
    "GPRINT:t_pkl_r:AVERAGE:Remote Packet Test = %3.0lf %%\\r"
);
if (RRDs::error) {
    display_error("Can't RRD::Graph: " . RRDs::error);
    exit(-1);
}

exit;

sub display_error {
    my($errmsg) = @_;
    my $pic = GD::Image->new(800, 200);
    my $white = $pic->colorAllocate(255, 255, 255);
    my $black = $pic->colorAllocate(0, 0, 0);
    my $align = GD::Text::Align->new($pic,
        valign      => 'center',
        halign      => 'center',
        color       => $black);
    $align->set_font(gdLargeFont);
    $align->set_text($errmsg);
    $align->draw(400, 100, 0);
    binmode STDOUT;
    print $pic->png();
}
